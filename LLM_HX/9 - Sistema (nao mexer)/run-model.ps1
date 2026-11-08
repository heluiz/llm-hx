# LLM-HX launcher - sobe o llama-server ajustado para:
# Predator PHN16-72: i9-14900HX (8P+16E), 32 GB RAM, RTX 4070 Laptop 8 GB
# Compativel com Windows PowerShell 5.1. Mantenha este arquivo so com ASCII.
# Obs.: variaveis do PowerShell NAO diferenciam maiusculas/minusculas - use nomes distintos.
param(
    [Parameter(Mandatory = $true)] [string] $Dir,   # pasta do modelo dentro de C:\LLM\models
    [ValidateSet('qwen', 'gemma', 'coder', 'gptoss')] [string] $Preset = 'qwen',
    [int] $Ctx = 32768,
    [switch] $Vision,
    [int] $Port = 8080
)
$ErrorActionPreference = 'Stop'

$Root = 'C:\LLM'
if ($env:LLMHX_ROOT) { $Root = $env:LLMHX_ROOT }   # apenas para testes
$serverExe = Join-Path (Join-Path $Root 'llama.cpp') 'llama-server.exe'
$modelDir  = Join-Path (Join-Path $Root 'models') $Dir
if (-not (Test-Path $serverExe)) { throw 'llama.cpp nao esta instalado. Rode 0-INSTALAR.bat primeiro.' }
if (-not (Test-Path $modelDir))  { throw "A pasta $modelDir nao existe. Rode 0-INSTALAR.bat primeiro." }

# Modelo principal = maior .gguf que nao seja projetor de visao (mmproj) nem cabeca MTP.
# Downloads incompletos ficam como .part e nunca entram aqui.
$modelFile = Get-ChildItem -Path $modelDir -Filter '*.gguf' |
    Where-Object { ($_.Name -notmatch 'mmproj') -and ($_.Name -notmatch '^mtp') } |
    Sort-Object Length -Descending | Select-Object -First 1
if (-not $modelFile) { throw "Nenhum modelo completo em $modelDir. Rode 0-INSTALAR.bat de novo." }
$mmprojFile = Get-ChildItem -Path $modelDir -Filter '*mmproj*.gguf' | Select-Object -First 1

# Porta ocupada = outro modelo ja aberto.
$portBusy = $null
try { $portBusy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop } catch { $portBusy = $null }
if ($portBusy) { throw "A porta $Port ja esta em uso (outro modelo aberto?). Feche a outra janela e tente de novo." }

# Ajuste medido no seu PC pelo 4-OTIMIZAR.bat (se existir): margem de VRAM, lote e threads.
$threadCount = '8'                                  # padrao: so os 8 P-cores (E-cores atrasam)
$tunedArgs   = @()
$tunedNote   = 'padrao (rode 4-OTIMIZAR.bat para ajustar ao seu PC)'
$tunedFile   = Join-Path (Join-Path $Root 'tuned') "$Dir.json"
if (Test-Path $tunedFile) {
    try {
        $tunedCfg = Get-Content $tunedFile -Raw | ConvertFrom-Json
        if ($tunedCfg.fitTarget) { $tunedArgs += @('--fit-target', "$($tunedCfg.fitTarget)") }
        if ($tunedCfg.ubatch)    { $tunedArgs += @('-ub', "$($tunedCfg.ubatch)") }
        if ($tunedCfg.threads)   { $threadCount = "$($tunedCfg.threads)" }
        if ($tunedCfg.loadMode) {
            # Modo "RAM" so se houver memoria livre agora (ex.: NinjaTrader aberto pode consumir); senao usa mmap.
            $needMiB = [int]$tunedCfg.ramMiB + 2048
            $freeMiB = $null
            try { $freeMiB = [int]((Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory / 1024) } catch { }
            if (($null -eq $freeMiB) -or ($freeMiB -ge $needMiB)) {
                $tunedArgs += @('--load-mode', "$($tunedCfg.loadMode)")
            } else {
                Write-Host ("Pouca RAM livre agora ({0} MB; o modo rapido pede ~{1} MB). Usando o modo economico (mmap)." -f $freeMiB, $needMiB) -ForegroundColor Yellow
            }
        }
        $tunedNote = "otimizada em $($tunedCfg.data): ~$($tunedCfg.gen_tok_s) tok/s gerando, ~$($tunedCfg.pp_tok_s) tok/s lendo"
    } catch {
        Write-Host 'Aviso: arquivo de otimizacao invalido; usando o padrao.' -ForegroundColor Yellow
    }
}

$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$llamaArgs = @(
    '-m', $modelFile.FullName,
    '--host', '127.0.0.1', '--port', "$Port",
    '-c', "$Ctx",
    '--fit', 'on',                                  # calcula sozinho quanto do modelo cabe nos 8 GB (resto vai p/ RAM)
    '--cache-type-k', 'q8_0', '--cache-type-v', 'q8_0',
    '--parallel', '1',                              # 1 usuario: contexto inteiro para voce
    '--threads', $threadCount,
    '--jinja',
    '--log-file', (Join-Path $logDir "$Dir.log")    # copia do log em LLM_HX\logs (para diagnostico)
)
$llamaArgs += $tunedArgs
if ($Preset -eq 'gemma') {
    $llamaArgs += @('--temp', '1.0', '--top-p', '0.95', '--top-k', '64', '--min-p', '0')
} elseif ($Preset -eq 'coder') {
    # valores recomendados pela Qwen para o Qwen3-Coder
    $llamaArgs += @('--temp', '0.7', '--top-p', '0.8', '--top-k', '20', '--repeat-penalty', '1.05')
} elseif ($Preset -eq 'gptoss') {
    # GPT-OSS (OpenAI): amostragem neutra recomendada
    $llamaArgs += @('--temp', '1.0', '--top-p', '1.0', '--top-k', '0')
} else {
    $llamaArgs += @('--temp', '0.6', '--top-p', '0.95', '--top-k', '20', '--min-p', '0')
}
if ($Vision) {
    if ($mmprojFile) {
        # Projetor de visao na CPU: os 8 GB de VRAM ficam para o modelo (imagem leva alguns segundos a mais).
        $llamaArgs += @('--mmproj', $mmprojFile.FullName, '--no-mmproj-offload')
    } else {
        Write-Host 'Aviso: projetor de visao (mmproj) nao encontrado; iniciando so com texto.' -ForegroundColor Yellow
    }
}

$sizeGb = [math]::Round($modelFile.Length / 1GB, 1)
Write-Host "Modelo : $($modelFile.Name)  ($sizeGb GB)" -ForegroundColor Cyan
Write-Host "Config : $tunedNote" -ForegroundColor Cyan
Write-Host "Chat   : http://127.0.0.1:$Port   (API compativel com OpenAI: http://127.0.0.1:$Port/v1)" -ForegroundColor Cyan
Write-Host 'O navegador abre sozinho quando o modelo terminar de carregar.' -ForegroundColor Cyan
Write-Host "Feche esta janela para descarregar o modelo e liberar RAM/VRAM.`n" -ForegroundColor Yellow

# Abre o navegador quando /health responder 200 (desiste se esta janela fechar ou apos 10 min).
$probe = @'
$u = 'http://127.0.0.1:__PORT__'
for ($i = 0; $i -lt 300; $i++) {
    if (-not (Get-Process -Id __PID__ -ErrorAction SilentlyContinue)) { break }
    try {
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri ($u + '/health')
        if ($r.StatusCode -eq 200) { Start-Process $u; break }
    } catch { }
    Start-Sleep -Seconds 2
}
'@
$probe = $probe.Replace('__PORT__', "$Port").Replace('__PID__', "$PID")
$probeEnc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))
try {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-EncodedCommand', $probeEnc) -WindowStyle Hidden
} catch {
    Write-Host "Nao consegui abrir o navegador sozinho; acesse http://127.0.0.1:$Port quando aparecer 'server is listening'." -ForegroundColor Yellow
}

# llama-server escreve o log no stderr; isso nao e erro.
$ErrorActionPreference = 'Continue'
& $serverExe @llamaArgs
$serverExit = $LASTEXITCODE
if ($serverExit -ne 0) {
    Write-Host ''
    Write-Host "llama-server terminou com codigo $serverExit. Copie as ultimas linhas acima e me envie." -ForegroundColor Red
}
