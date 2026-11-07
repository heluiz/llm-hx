# LLM-HX Agente - servidor do modelo para o agente (llama-server com contexto grande, na porta do agente).
# Fica vigiando: desliga o modelo na pausa do pregao / quando voce pausa, e religa depois sozinho.
# Fechar esta janela desliga o modelo e libera a placa de video.
# Compativel com Windows PowerShell 5.1. Mantenha este arquivo so com ASCII.
# Obs.: variaveis do PowerShell NAO diferenciam maiusculas/minusculas - use nomes distintos.
param(
    [string] $Dir,        # pasta do modelo em C:\LLM\models (sem isso, mostra o menu)
    [switch] $Simular     # so mostra o comando que seria usado e sai (diagnostico)
)
. (Join-Path $PSScriptRoot 'agente-comum.ps1')
$cfg = Get-AgConfig

$serverExe = Join-Path (Join-Path $AgRoot 'llama.cpp') 'llama-server.exe'
if (-not (Test-Path $serverExe)) { throw 'O llama.cpp nao esta instalado. Rode "1 - Texto (LLMs)\INSTALAR-ATUALIZAR" primeiro.' }
$models = @(Get-AgModels)
if ($models.Count -eq 0) { throw "Nenhum modelo em $AgRoot\models. Rode INSTALAR-ATUALIZAR." }

# ---------- escolha do modelo
if ($Dir) {
    $model = $models | Where-Object { $_.Dir -eq $Dir } | Select-Object -First 1
    if (-not $model) { throw "Modelo '$Dir' nao encontrado em $AgRoot\models." }
} else {
    Write-Host ''
    Write-Host '=== Agente HX: escolha o modelo do agente ===' -ForegroundColor Cyan
    $defaultPick = 1
    for ($idx = 0; $idx -lt $models.Count; $idx++) {
        $item = $models[$idx]
        $speedTxt = ''
        if ($item.Tuned -and $item.Tuned.gen_tok_s) { $speedTxt = ", ~$($item.Tuned.gen_tok_s) tok/s" }
        $star = ' '
        if ($item.Dir -eq "$($cfg.modeloPadrao)") { $star = '*'; $defaultPick = $idx + 1 }
        Write-Host ('  {0}{1}) {2}  ({3} GB{4})' -f $star, ($idx + 1), $item.Dir, $item.SizeGb, $speedTxt)
        if ($item.Nota) { Write-Host ('       {0}' -f $item.Nota) -ForegroundColor DarkGray }
    }
    $answer = Read-Host ('Numero do modelo [Enter = {0}]' -f $defaultPick)
    $pickNum = $defaultPick
    if ($answer -match '^\s*\d+\s*$') { $pickNum = [int]$answer }
    if (($pickNum -lt 1) -or ($pickNum -gt $models.Count)) { throw "Opcao invalida: $answer" }
    $model = $models[$pickNum - 1]
}

# ---------- argumentos (mesma base do run-model.ps1, com contexto do agente e sem visao)
$port = [int]$cfg.porta
$ctx  = [int]$cfg.contexto
$threadCount = '8'
$tunedArgs = @()
$tunedLoadMode = ''
$ramNeedMiB = 0
if ($model.Tuned) {
    if ($model.Tuned.fitTarget) { $tunedArgs += @('--fit-target', "$($model.Tuned.fitTarget)") }
    if ($model.Tuned.ubatch)    { $tunedArgs += @('-ub', "$($model.Tuned.ubatch)") }
    if ($model.Tuned.threads)   { $threadCount = "$($model.Tuned.threads)" }
    if ($model.Tuned.loadMode)  { $tunedLoadMode = "$($model.Tuned.loadMode)"; $ramNeedMiB = [int]$model.Tuned.ramMiB + 2048 }
}
$srvLog = Join-Path $AgLogs ('servidor-{0}.log' -f $model.Dir)
$outFile = Join-Path $AgLogs 'servidor-console-out.txt'
$errFile = Join-Path $AgLogs 'servidor-console-err.txt'
$baseArgs = @(
    '-m', $model.File.FullName,
    '-a', $model.Dir,                               # nome que o agente ve em /v1/models
    '--host', '127.0.0.1', '--port', "$port",
    '-c', "$ctx",                                   # contexto grande: agente le arquivos e saidas de comandos
    '--fit', 'on',
    '--cache-type-k', 'q8_0', '--cache-type-v', 'q8_0',
    '--parallel', '1',
    '--threads', $threadCount,
    '--jinja',                                      # necessario para o modelo chamar ferramentas
    '--log-file', $srvLog
)
$baseArgs += $tunedArgs
$baseArgs += (Get-AgSamplingArgs $model.Preset)
if ("$($cfg.raciocinio)" -eq 'desligado') { $baseArgs += @('--reasoning', 'off') }

function Get-StartArgs {
    $startArgs = @($baseArgs)
    if ($tunedLoadMode) {
        # Modo "RAM" so se houver memoria livre agora (NinjaTrader aberto pode estar usando); senao fica no mmap.
        $freeMiB = $null
        try { $freeMiB = [int]((Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory / 1024) } catch { }
        if (($null -eq $freeMiB) -or ($freeMiB -ge $ramNeedMiB)) { $startArgs += @('--load-mode', $tunedLoadMode) }
    }
    return ,$startArgs
}

if ($Simular) {
    Write-Host "Modelo  : $($model.Dir)  ($($model.SizeGb) GB)"
    Write-Host "Comando : `"$serverExe`" $(ConvertTo-AgArgString (Get-StartArgs))"
    Write-Host ("Agora   : pausa do pregao = {0}; pausado por voce = {1}" -f (Test-AgPregao $cfg (Get-Date)), (Test-Path $AgPauseFlag))
    exit 0
}

# ---------- preparo
# Uma janela de servidor por vez (duas brigariam pela mesma porta e pela placa de video).
$createdNew = $false
$serverMutex = New-Object System.Threading.Mutex($true, 'Local\AgenteHX-Servidor', [ref]$createdNew)
if (-not $createdNew) {
    Write-Host 'Ja tem uma janela do 1-LIGAR-SERVIDOR aberta. Use aquela (ou feche-a antes de abrir outra).' -ForegroundColor Yellow
    exit 1
}
$host.UI.RawUI.WindowTitle = "Agente HX - servidor ($($model.Dir), porta $port)"
$procs = Get-AgLlamaProcs $port
foreach ($leftover in $procs.Agent) { Stop-Process -Id $leftover.ProcessId -Force -ErrorAction SilentlyContinue }   # sobra de uma janela antiga
if (@($procs.Other).Count -gt 0) {
    Write-Host 'ATENCAO: tem um modelo de chat aberto (atalhos de "1 - Texto"). Feche a janela dele:' -ForegroundColor Yellow
    Write-Host '         a placa de video aguenta um modelo por vez.' -ForegroundColor Yellow
}
try {
    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1
    if ($battery -and $battery.BatteryStatus -eq 1) { Write-Host 'ATENCAO: notebook na BATERIA - ligue o carregador para rodar por horas.' -ForegroundColor Yellow }
} catch { }
# Impede o Windows de suspender enquanto esta janela estiver aberta (a tela ainda pode apagar).
try {
    Add-Type -Namespace LlmHx -Name Energia -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);' -ErrorAction Stop
    [void][LlmHx.Energia]::SetThreadExecutionState([uint32]2147483649)   # ES_CONTINUOUS + ES_SYSTEM_REQUIRED
} catch {
    Write-Host 'Aviso: nao consegui impedir a suspensao automatica do Windows.' -ForegroundColor Yellow
}

$pausa = $cfg.pausaPregao
Write-Host ''
Write-Host "Modelo  : $($model.Dir)  ($($model.SizeGb) GB)  |  contexto $ctx tokens  |  porta $port" -ForegroundColor Cyan
if ($pausa -and $pausa.ativa) {
    Write-Host "Pregao  : desliga sozinho em $($pausa.dias), das $($pausa.inicio) as $($pausa.fim) (mude em 9 - Sistema\agente\config.json)" -ForegroundColor Cyan
}
Write-Host 'Feche esta janela para desligar o modelo e liberar a placa de video.' -ForegroundColor Yellow
Write-Host ''

function Write-Status([string]$Text, [string]$Color = 'Gray') {
    $line = '[{0:dd/MM HH:mm}] {1}' -f (Get-Date), $Text
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path (Join-Path $AgLogs 'servidor-historico.txt') -Value $line
}

# ---------- vigia
$srvProc = $null
$lastState = ''
$readyShown = $false
$crashTimes = New-Object System.Collections.ArrayList
$cooldownUntil = [datetime]::MinValue
try {
    while ($true) {
        $now = Get-Date
        $reason = ''
        if (Test-Path $AgPauseFlag) { $reason = 'pausado por voce (6-PAUSAR-OU-CONTINUAR)' }
        elseif (Test-AgPregao $cfg $now) { $reason = "pausa do pregao (volta as $($pausa.fim))" }
        elseif ($cfg.pausarSeNinjaTraderAberto -and (Get-Process -Name 'NinjaTrader' -ErrorAction SilentlyContinue)) { $reason = 'NinjaTrader aberto' }
        elseif ($now -lt $cooldownUntil) { $reason = ('o modelo caiu varias vezes; nova tentativa as {0:HH:mm}' -f $cooldownUntil) }

        $isRunning = ($null -ne $srvProc) -and (-not $srvProc.HasExited)
        if (($null -ne $srvProc) -and $srvProc.HasExited) {
            # caiu sozinho (nao fomos nos que paramos)
            Write-Status ("o llama-server fechou sozinho (codigo {0}). Ultimas linhas:" -f $srvProc.ExitCode) 'Red'
            if (Test-Path $errFile) { Get-Content $errFile -Tail 8 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray } }
            [void]$crashTimes.Add($now)
            $recent = @($crashTimes | Where-Object { $_ -gt $now.AddMinutes(-15) })
            if ($recent.Count -ge 3) {
                $cooldownUntil = $now.AddMinutes(15)
                $crashTimes.Clear()
            }
            $srvProc = $null
            $isRunning = $false
            $lastState = ''
            continue
        }

        if ($reason) {
            if ($isRunning) {
                Stop-Process -Id $srvProc.Id -Force -ErrorAction SilentlyContinue
                try { [void]$srvProc.WaitForExit(30000) } catch { }
                $srvProc = $null
            }
            $state = "DESLIGADO - $reason"
            $readyShown = $false
        } else {
            if (-not $isRunning) {
                $srvProc = Start-Process -FilePath $serverExe -ArgumentList (ConvertTo-AgArgString (Get-StartArgs)) -NoNewWindow -PassThru `
                    -RedirectStandardOutput $outFile -RedirectStandardError $errFile
                try { $srvProc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }   # NinjaTrader na frente
                $readyShown = $false
            }
            $state = 'LIGANDO (carregando o modelo...)'
            if (Test-AgServer $port) { $state = "LIGADO e pronto em http://127.0.0.1:$port" }
        }
        if ($state -ne $lastState) {
            $stateColor = 'Gray'
            if ($state -like 'LIGADO*') { $stateColor = 'Green' } elseif ($state -like 'DESLIGADO*') { $stateColor = 'Yellow' }
            Write-Status "servidor $state" $stateColor
            $lastState = $state
        }
        $waitSec = 20
        if ($state -like 'LIGANDO*') { $waitSec = 3 }
        Start-Sleep -Seconds $waitSec
    }
} finally {
    if (($null -ne $srvProc) -and (-not $srvProc.HasExited)) { Stop-Process -Id $srvProc.Id -Force -ErrorAction SilentlyContinue }
}
