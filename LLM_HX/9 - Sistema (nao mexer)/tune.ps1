# LLM-HX otimizador - mede configuracoes no SEU PC e salva a mais rapida de cada modelo.
# Os lancadores (1- a 4-) passam a usar o resultado automaticamente (C:\LLM\tuned\<modelo>.json).
# Compativel com Windows PowerShell 5.1. Mantenha este arquivo so com ASCII.
# Obs.: variaveis do PowerShell NAO diferenciam maiusculas/minusculas - use nomes distintos.
param([string[]] $Only)   # opcional: -Only gemma4-12b-heretic  (testa so esse modelo)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$Root = 'C:\LLM'
if ($env:LLMHX_ROOT) { $Root = $env:LLMHX_ROOT }          # apenas para testes
$benchPort = 8089
if ($env:LLMHX_BENCH_PORT) { $benchPort = [int]$env:LLMHX_BENCH_PORT }
$serverExe = Join-Path (Join-Path $Root 'llama.cpp') 'llama-server.exe'
$tunedDir  = Join-Path $Root 'tuned'
$outDir    = Join-Path $PSScriptRoot 'otimizacao'
$logDir    = Join-Path $outDir 'logs'
New-Item -ItemType Directory -Force -Path $tunedDir, $outDir, $logDir | Out-Null
if (-not (Test-Path $serverExe)) { throw 'llama.cpp nao esta instalado. Rode 0-INSTALAR.bat primeiro.' }

# Servidor de teste esquecido de uma execucao interrompida (porta de teste) -> encerra.
try {
    Get-CimInstance -ClassName Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction Stop |
        Where-Object { $_.CommandLine -match "--port $benchPort\b" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
} catch { }
if (Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue) {
    throw 'Ha um modelo aberto. Feche a janela do modelo antes de otimizar (os testes precisam da placa de video livre).'
}

Write-Host ''
Write-Host '=== LLM-HX: otimizacao de desempenho ===' -ForegroundColor Cyan
Write-Host 'Leva uns 15-20 minutos. Deixe o notebook na tomada, em modo Desempenho/Turbo (PredatorSense),'
Write-Host 'e evite usar programas pesados (jogos, NinjaTrader em pregao) enquanto mede.'
try {
    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1
    if ($battery -and $battery.BatteryStatus -eq 1) {
        Write-Host 'ATENCAO: o notebook esta na BATERIA - a GPU fica limitada e o resultado sai pior. Ligue o carregador.' -ForegroundColor Yellow
    }
} catch { }

# Mesmas bases dos lancadores; o que varia: margem de VRAM do --fit, tamanho do lote (-ub) e threads.
$modelList = @(
    @{ Dir = 'gemma4-12b-heretic';     Kind = 'dense'; Ctx = 16384 },
    @{ Dir = 'qwen36-35b-a3b-heretic'; Kind = 'moe';   Ctx = 32768 },
    @{ Dir = 'qwen38-35b-a3b-apex';    Kind = 'moe';   Ctx = 32768 },
    @{ Dir = 'qwen36-35b-a3b';         Kind = 'moe';   Ctx = 32768 },
    @{ Dir = 'qwen3-coder-30b-a3b';         Kind = 'moe'; Ctx = 32768 },
    @{ Dir = 'qwen3-coder-30b-a3b-heretic'; Kind = 'moe'; Ctx = 32768 },
    @{ Dir = 'gpt-oss-20b';                 Kind = 'moe'; Ctx = 32768 },
    @{ Dir = 'gpt-oss-20b-heretic';         Kind = 'moe'; Ctx = 32768 }
)
if ($Only) {
    $onlyDirs  = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $modelList = @($modelList | Where-Object { $onlyDirs -contains $_.Dir })
    if ($modelList.Count -eq 0) { throw "Nenhum modelo conhecido em -Only: $($onlyDirs -join ', ')" }
}

$genPrompt = 'Escreva um relatorio detalhado sobre a historia do mercado financeiro brasileiro, com datas e exemplos.'
$ppBuilder = New-Object System.Text.StringBuilder
for ($lineNo = 1; $lineNo -le 100; $lineNo++) {
    [void]$ppBuilder.AppendLine("Item $lineNo do relatorio: o contrato futuro de indice tem vencimento definido, ajuste diario, margem de garantia e liquidez concentrada no primeiro vencimento.")
}
$ppPrompt = $ppBuilder.ToString() + 'Resuma o texto acima em uma frase.'

function Invoke-Llama([string]$Path, [hashtable]$Body) {
    $json = $Body | ConvertTo-Json -Compress
    return Invoke-RestMethod -Uri ("http://127.0.0.1:{0}{1}" -f $benchPort, $Path) -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 900
}

function Wait-Ready($ServerProc) {
    $deadline = (Get-Date).AddSeconds(900)
    while ((Get-Date) -lt $deadline) {
        if ($ServerProc.HasExited) { return $false }
        try {
            $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri ("http://127.0.0.1:{0}/health" -f $benchPort)
            if ($resp.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Seconds 2
    }
    return $false
}

# $LoadMode: '' = padrao (mmap, le o arquivo sob demanda) | 'none' = carrega a parte da CPU direto na RAM
function Measure-Config($Info, $ModelFile, [int]$FitMiB, [int]$Ubatch, [int]$Threads, [string]$LoadMode = '') {
    $carga = 'mmap'
    if ($LoadMode -eq 'none') { $carga = 'ram' }
    $tag     = '{0}_margem{1}_ub{2}_t{3}_{4}' -f $Info.Dir, $FitMiB, $Ubatch, $Threads, $carga
    $logFile = Join-Path $logDir "$tag.log"
    $res = [ordered]@{ Fit = $FitMiB; Ub = $Ubatch; Threads = $Threads; Carga = $carga; Gen = 0.0; PP = 0.0; Score = 99999.0; ScoreRaw = 99999.0;
                       Ok = $false; Layers = '?'; GpuMiB = 0; CpuMiB = 0; Note = '' }
    Write-Host ("   testando margem {0} MiB, lote {1}, threads {2}, carga {3} ..." -f $FitMiB, $Ubatch, $Threads, $carga) -NoNewline
    if (Test-Path $logFile) { Remove-Item $logFile -Force }
    $srvArgs = @(
        '-m', ('"{0}"' -f $ModelFile.FullName),
        '--host', '127.0.0.1', '--port', "$benchPort",
        '-c', "$($Info.Ctx)",
        '--fit', 'on', '--fit-target', "$FitMiB",
        '-ub', "$Ubatch",
        '--cache-type-k', 'q8_0', '--cache-type-v', 'q8_0',
        '--parallel', '1', '--threads', "$Threads",
        '--log-file', ('"{0}"' -f $logFile), '-lv', '4'
    )
    if ($LoadMode) { $srvArgs += @('--load-mode', $LoadMode) }
    $srvProc = Start-Process -FilePath $serverExe -ArgumentList ($srvArgs -join ' ') -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $logDir 'console-out.txt') -RedirectStandardError (Join-Path $logDir 'console-err.txt')
    try {
        if (-not (Wait-Ready $srvProc)) {
            $res.Note = 'nao carregou (veja o log)'
        } else {
            [void](Invoke-Llama '/completion' @{ prompt = 'Ola, tudo bem?'; n_predict = 48; cache_prompt = $false })   # aquecimento
            $bestGen = 0.0
            for ($rep = 0; $rep -lt 2; $rep++) {
                $out = Invoke-Llama '/completion' @{ prompt = $genPrompt; n_predict = 192; ignore_eos = $true; cache_prompt = $false; temperature = 0 }
                if ($out.timings.predicted_per_second -gt $bestGen) { $bestGen = [double]$out.timings.predicted_per_second }
            }
            # Leitura: texto longo cortado em ate 3000 tokens (e no maximo metade do contexto do modelo).
            $slotCtx  = [int](Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/props" -f $benchPort) -TimeoutSec 60).default_generation_settings.n_ctx
            $tokenIds = @((Invoke-Llama '/tokenize' @{ content = $ppPrompt }).tokens)
            $takeN    = [math]::Min($tokenIds.Count, [math]::Min(3000, [int]($slotCtx / 2)))
            $ppIds    = $tokenIds[0..($takeN - 1)]
            $bestPP = 0.0
            for ($rep = 0; $rep -lt 2; $rep++) {
                $out = Invoke-Llama '/completion' @{ prompt = $ppIds; n_predict = 1; cache_prompt = $false }
                if ($out.timings.prompt_per_second -gt $bestPP) { $bestPP = [double]$out.timings.prompt_per_second }
            }
            if ($bestGen -gt 0 -and $bestPP -gt 0) {
                $res.Gen   = [math]::Round($bestGen, 1)
                $res.PP    = [math]::Round($bestPP, 0)
                # Tempo para responder uma mensagem tipica: ler 1000 tokens + escrever 400.
                $res.ScoreRaw = (1000.0 / $bestPP) + (400.0 / $bestGen)   # comparacao: valor exato
                $res.Score    = [math]::Round($res.ScoreRaw, 1)              # exibicao
                $res.Ok    = $true
            } else {
                $res.Note = 'medicao vazia'
            }
        }
    } catch {
        $res.Note = 'erro: ' + $_.Exception.Message
    } finally {
        if (-not $srvProc.HasExited) {
            Stop-Process -Id $srvProc.Id -Force -ErrorAction SilentlyContinue
            try { [void]$srvProc.WaitForExit(30000) } catch { }
        }
        Start-Sleep -Seconds 3   # tempo para o driver liberar a VRAM
    }
    if (Test-Path $logFile) {
        foreach ($logLine in Get-Content $logFile) {
            if ($logLine -match 'offloaded (\d+)/(\d+) layers to GPU') { $res.Layers = '{0}/{1}' -f $Matches[1], $Matches[2] }
            # "CUDA0 model buffer" = placa; qualquer outro (CPU, CPU_Mapped, CPU_REPACK, CUDA_Host, AMX...) = RAM.
            if ($logLine -match '(\S+) model buffer size =\s*([\d\.]+) MiB') {
                $bufName = $Matches[1]                          # guardar antes: o proximo -match sobrescreve $Matches
                $bufMiB  = [math]::Round([double]$Matches[2])
                if ($bufName -match '^CUDA\d+$') { $res.GpuMiB += $bufMiB } else { $res.CpuMiB += $bufMiB }
            }
        }
    }
    if ($res.Ok) {
        Write-Host (" {0} tok/s gerando, {1} tok/s lendo" -f $res.Gen, $res.PP) -ForegroundColor Green
    } else {
        Write-Host (" falhou: {0}" -f $res.Note) -ForegroundColor Yellow
    }
    return [pscustomobject]$res
}

$tunedCount = 0
$report = New-Object System.Collections.ArrayList
[void]$report.Add('LLM-HX - resultado da otimizacao (' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ')')
[void]$report.Add('Msg tipica = segundos para ler 1000 tokens e escrever 400 (menor e melhor).')

foreach ($info in $modelList) {
    $modelDir = Join-Path (Join-Path $Root 'models') $info.Dir
    $modelFile = $null
    if (Test-Path $modelDir) {
        $modelFile = Get-ChildItem -Path $modelDir -Filter '*.gguf' |
            Where-Object { ($_.Name -notmatch 'mmproj') -and ($_.Name -notmatch '^mtp') } |
            Sort-Object Length -Descending | Select-Object -First 1
    }
    if (-not $modelFile) { Write-Host "`n>>> $($info.Dir): modelo nao encontrado, pulando." -ForegroundColor Yellow; continue }

    Write-Host "`n>>> $($info.Dir)  ($([math]::Round($modelFile.Length / 1GB, 1)) GB)" -ForegroundColor Cyan
    $results = New-Object System.Collections.ArrayList
    if ($info.Kind -eq 'dense') {
        $plan = @(@(1024, 512, 8), @(512, 512, 8), @(256, 512, 8), @(256, 256, 8))
    } else {
        $plan = @(@(1024, 512, 8), @(256, 512, 8), @(256, 2048, 8))
    }
    foreach ($cfg in $plan) { [void]$results.Add((Measure-Config $info $modelFile $cfg[0] $cfg[1] $cfg[2])) }
    $winner = @($results | Where-Object { $_.Ok } | Sort-Object ScoreRaw) | Select-Object -First 1
    if ($winner -and $info.Kind -eq 'moe') {
        # 2a etapa: 16 threads (P-cores com HT) so se for >= 2% melhor - 8 deixa nucleos livres p/ outros programas.
        $cand = Measure-Config $info $modelFile $winner.Fit $winner.Ub 16
        [void]$results.Add($cand)
        if ($cand.Ok -and ($cand.ScoreRaw -lt ($winner.ScoreRaw * 0.98))) { $winner = $cand }
        # 3a etapa: parte da CPU direto na RAM (sugestao do proprio llama.cpp) so se for >= 3% melhor - usa mais RAM.
        $cand = Measure-Config $info $modelFile $winner.Fit $winner.Ub $winner.Threads 'none'
        [void]$results.Add($cand)
        if ($cand.Ok -and ($cand.ScoreRaw -lt ($winner.ScoreRaw * 0.97))) { $winner = $cand }
    }
    $baseline = @($results | Where-Object { $_.Ok -and $_.Fit -eq 1024 -and $_.Ub -eq 512 -and $_.Threads -eq 8 -and $_.Carga -eq 'mmap' }) | Select-Object -First 1
    if ($winner -and $baseline -and ($winner.ScoreRaw -gt ($baseline.ScoreRaw * 0.97))) {
        $winner = $baseline   # ganho < 3% e ruido de medicao: fica com o padrao (mais folga de VRAM)
    }

    [void]$report.Add('')
    [void]$report.Add(('Modelo: {0}  (contexto {1})' -f $info.Dir, $info.Ctx))
    [void]$report.Add('  margem  lote  threads  carga  gera tok/s  le tok/s  msg tipica  camadas GPU  modelo GPU/CPU (MiB)  obs')
    foreach ($row in $results) {
        $mark = ' '
        if ($winner -and ($row -eq $winner)) { $mark = '*' }
        [void]$report.Add(('{0} {1,6}  {2,4}  {3,7}  {4,5}  {5,10}  {6,8}  {7,10}  {8,11}  {9,8} / {10,-8}  {11}' -f
            $mark, $row.Fit, $row.Ub, $row.Threads, $row.Carga, $row.Gen, $row.PP, $row.Score, $row.Layers, $row.GpuMiB, $row.CpuMiB, $row.Note))
    }
    if ($winner) {
        $winnerLoad = ''
        if ($winner.Carga -eq 'ram') { $winnerLoad = 'none' }
        $tunedCfg = [ordered]@{ fitTarget = $winner.Fit; ubatch = $winner.Ub; threads = $winner.Threads;
                                loadMode = $winnerLoad; ramMiB = $winner.CpuMiB;
                                gen_tok_s = $winner.Gen; pp_tok_s = $winner.PP; data = (Get-Date -Format 'yyyy-MM-dd HH:mm') }
        $tunedCfg | ConvertTo-Json | Set-Content -Path (Join-Path $tunedDir "$($info.Dir).json") -Encoding ASCII
        $tunedCount++
        $line = '  * escolhido: margem {0} MiB, lote {1}, {2} threads, carga {3} -> {4} tok/s gerando, {5} tok/s lendo' -f $winner.Fit, $winner.Ub, $winner.Threads, $winner.Carga, $winner.Gen, $winner.PP
        if ($baseline) { $line += ('  (antes: {0} / {1})' -f $baseline.Gen, $baseline.PP) }
        [void]$report.Add($line)
        Write-Host $line -ForegroundColor Green
    } else {
        [void]$report.Add('  nenhuma configuracao funcionou - o lancador continua com o padrao. Veja otimizacao\logs.')
        Write-Host '  nenhuma configuracao funcionou; o lancador continua com o padrao.' -ForegroundColor Yellow
    }
}

$reportFile = Join-Path $outDir 'resultado.txt'
$report | Set-Content -Path $reportFile -Encoding ASCII
Write-Host ''
Write-Host "Relatorio salvo em: $reportFile" -ForegroundColor Cyan
if ($tunedCount -gt 0) {
    Write-Host "Pronto: $tunedCount modelo(s) otimizado(s). Os lancadores ja usam a configuracao vencedora." -ForegroundColor Green
} else {
    Write-Host 'Nenhum modelo foi otimizado; os lancadores continuam com o padrao. Me envie o resultado.txt.' -ForegroundColor Yellow
}
