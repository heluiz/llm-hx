# LLM-HX Agente - diagnostico: confere scripts, configuracao, modelos, WSL e servidor.
# Grava tudo em 9 - Sistema (nao mexer)\agente\logs\diagnostico.txt (para me mandar se algo der errado).
# Compativel com Windows PowerShell 5.1. Mantenha este arquivo so com ASCII.
# Obs.: variaveis do PowerShell NAO diferenciam maiusculas/minusculas - use nomes distintos.
. (Join-Path $PSScriptRoot 'agente-comum.ps1')
$ErrorActionPreference = 'Continue'
$reportPath = Join-Path $AgLogs 'diagnostico.txt'
if (Test-Path $reportPath) { Remove-Item $reportPath -Force }
try { Start-Transcript -Path $reportPath | Out-Null } catch { }
$problemCount = 0
function Mark-Ok([string]$Text) { Write-Host "  OK    $Text" -ForegroundColor Green }
function Mark-Bad([string]$Text) { Write-Host "  FALHA $Text" -ForegroundColor Red; $script:problemCount++ }
function Mark-Info([string]$Text) { Write-Host "  --    $Text" }

Write-Host ("=== Agente HX: diagnostico ({0:dd/MM/yyyy HH:mm}) ===" -f (Get-Date)) -ForegroundColor Cyan

Write-Host ''
Write-Host '[scripts]'
$sysDir = Split-Path $AgKit -Parent
$scriptList = @(Get-ChildItem -Path $AgKit -Filter '*.ps1' -File) + @(Get-ChildItem -Path $sysDir -Filter '*.ps1' -File)
foreach ($scriptFile in $scriptList) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -eq 0) { Mark-Ok "sintaxe de $($scriptFile.Name)" }
    else { Mark-Bad ("{0}: {1} (linha {2})" -f $scriptFile.Name, $parseErrors[0].Message, $parseErrors[0].Extent.StartLineNumber) }
}

Write-Host ''
Write-Host '[configuracao]'
$cfg = $null
try { $cfg = Get-AgConfig; Mark-Ok 'config.json lido' } catch { Mark-Bad $_.Exception.Message }
if ($cfg) {
    Mark-Info ("distro {0} | porta {1} | contexto {2} | agente padrao {3} | modelo padrao {4}" -f $cfg.distro, $cfg.porta, $cfg.contexto, $cfg.agentePadrao, $cfg.modeloPadrao)
    try {
        $inWindow = Test-AgPregao $cfg (Get-Date)
        Mark-Ok ("pausa do pregao: {0} {1}-{2} (agora: {3})" -f $cfg.pausaPregao.dias, $cfg.pausaPregao.inicio, $cfg.pausaPregao.fim, $(if ($inWindow) { 'DENTRO da pausa' } else { 'fora da pausa' }))
    } catch { Mark-Bad "pausa do pregao com horario invalido: $($_.Exception.Message)" }
}
if (Test-Path $AgPauseFlag) { Mark-Info 'servidor PAUSADO por voce (arquivo PAUSADO.flag)' }

Write-Host ''
Write-Host '[llama.cpp e modelos]'
$serverExe = Join-Path (Join-Path $AgRoot 'llama.cpp') 'llama-server.exe'
if (Test-Path $serverExe) {
    $verTxt = ''
    $verPath = Join-Path (Join-Path $AgRoot 'llama.cpp') 'VERSION.txt'
    if (Test-Path $verPath) { $verTxt = (Get-Content $verPath -Raw).Trim() }
    Mark-Ok "llama-server.exe (build $verTxt)"
} else { Mark-Bad "nao achei $serverExe" }
$modelList = @(Get-AgModels)
if ($modelList.Count -eq 0) { Mark-Bad "nenhum modelo em $AgRoot\models" }
foreach ($m in $modelList) {
    $tunedTxt = 'sem otimizacao'
    if ($m.Tuned) { $tunedTxt = "otimizado: ~$($m.Tuned.gen_tok_s) tok/s" }
    Mark-Ok ("{0}  ({1} GB, {2})" -f $m.Dir, $m.SizeGb, $tunedTxt)
    $tplNow = Get-AgTemplateState $m
    $tplTxt = @{ 'corrigido' = 'corrigido (aceita o OpenCode e o Claude Code)'; 'sem-correcao' = 'original (nao precisa de correcao)'; 'desconhecido' = 'ainda nao conferido (o 1-LIGAR-SERVIDOR confere e corrige no primeiro uso)' }[$tplNow]
    Mark-Info ("   molde de conversa: {0}" -f $tplTxt)
}
if ($cfg -and $modelList.Count -gt 0) {
    $simDir = ''
    foreach ($wanted in @("$($cfg.modeloPadrao)", 'qwen36-35b-a3b', 'qwen36-35b-a3b-heretic')) {
        if ((-not $simDir) -and ($modelList | Where-Object { $_.Dir -eq $wanted })) { $simDir = $wanted }
    }
    if (-not $simDir) { $simDir = $modelList[0].Dir }
    Write-Host "  comando do servidor para $simDir :"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $AgKit 'agente-servidor.ps1') -Dir $simDir -Simular 2>&1 | ForEach-Object { Write-Host "     $_" }
}
if ($cfg) {
    $procs = Get-AgLlamaProcs ([int]$cfg.porta)
    Mark-Info ("llama-server rodando agora: {0} do agente, {1} de chat" -f @($procs.Agent).Count, @($procs.Other).Count)
}

Write-Host ''
Write-Host '[WSL]'
$wslVer = Invoke-Wsl @('--version')
if ($wslVer.Code -eq 0) { Mark-Ok (($wslVer.Text -split "`n" | Select-Object -First 1)) } else { Mark-Bad 'wsl.exe nao respondeu' }
$wslCfgPath = Join-Path $env:USERPROFILE '.wslconfig'
if ((Test-Path $wslCfgPath) -and ((Get-Content $wslCfgPath -Raw) -match '(?im)^\s*networkingMode\s*=\s*mirrored')) { Mark-Ok 'rede espelhada (networkingMode=mirrored)' }
else { Mark-Bad 'falta networkingMode=mirrored no .wslconfig (rode 0-INSTALAR-AGENTE)' }
if ($cfg -and (Test-AgDistro "$($cfg.distro)")) {
    Mark-Ok "distro $($cfg.distro) instalada"
    if (Test-AgScriptsAtualizados "$($cfg.distro)") { Mark-Ok 'scripts dentro da distro em dia com o kit' }
    else { Mark-Bad 'scripts dentro da distro desatualizados (rode ATUALIZAR-SCRIPTS)' }
    Write-Host ''
    Write-Host '[dentro da distro]'
    $inside = Invoke-Wsl @('-d', "$($cfg.distro)", '--cd', '~', '-e', "$AgWslKit/bin/agente-verificar.sh", '--porta', "$($cfg.porta)")
    $inside.Text -split "`n" | ForEach-Object { Write-Host ($_.TrimEnd("`r")) }
    if ($inside.Code -ne 0) { $problemCount++ }

    # Copia o fim dos arquivos de cada projeto (plano, diario, logs das rodadas, git) e dos logs do
    # OpenCode para logs\projetos: e o que eu preciso para entender o que o agente fez.
    Write-Host ''
    Write-Host '[evidencias para suporte]'
    $evidDir = Join-Path $AgLogs 'projetos'
    try {
        if (Test-Path -LiteralPath $evidDir) { Remove-Item -LiteralPath $evidDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path $evidDir | Out-Null
        $projRoot = Get-AgUncProjetos "$($cfg.distro)"
        $copiedCount = 0
        if (Test-Path -LiteralPath $projRoot) {
            foreach ($projDir in @(Get-ChildItem -LiteralPath $projRoot -Directory -ErrorAction SilentlyContinue)) {
                $projDest = Join-Path $evidDir $projDir.Name
                New-Item -ItemType Directory -Force -Path $projDest | Out-Null
                $pickList = @()
                foreach ($docName in @('SPEC.md', 'PLAN.md', 'PROGRESS.md', 'RELATORIO.md')) {
                    $docPath = Join-Path $projDir.FullName $docName
                    if (Test-Path -LiteralPath $docPath) { $pickList += Get-Item -LiteralPath $docPath }
                }
                $roundDir = Join-Path (Join-Path $projDir.FullName '.agente') 'logs'
                if (Test-Path -LiteralPath $roundDir) {
                    $pickList += @(Get-ChildItem -LiteralPath $roundDir -File -Filter 'rodada-*.log' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 6)
                }
                foreach ($srcFile in $pickList) {
                    Get-Content -LiteralPath $srcFile.FullName -Tail 400 -Encoding UTF8 -ErrorAction SilentlyContinue |
                        Set-Content -LiteralPath (Join-Path $projDest $srcFile.Name) -Encoding UTF8
                    $copiedCount++
                }
                $gitLog = Invoke-Wsl @('-d', "$($cfg.distro)", '--cd', '~', '-e', 'git', '-C', "projetos/$($projDir.Name)", 'log', '--oneline', '-30')
                if ($gitLog.Code -eq 0) { Set-Content -LiteralPath (Join-Path $projDest 'git-log.txt') -Value $gitLog.Text -Encoding UTF8 }
            }
        }
        $ocLogDir = Join-Path (Split-Path $projRoot -Parent) '.local\share\opencode\log'
        if (Test-Path -LiteralPath $ocLogDir) {
            $ocDest = Join-Path $evidDir '_opencode'
            New-Item -ItemType Directory -Force -Path $ocDest | Out-Null
            foreach ($ocLog in @(Get-ChildItem -LiteralPath $ocLogDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 3)) {
                Get-Content -LiteralPath $ocLog.FullName -Tail 400 -Encoding UTF8 -ErrorAction SilentlyContinue |
                    Set-Content -LiteralPath (Join-Path $ocDest $ocLog.Name) -Encoding UTF8
                $copiedCount++
            }
        }
        Mark-Ok ("{0} arquivo(s) copiados para {1}" -f $copiedCount, $evidDir)
    } catch {
        Mark-Info "nao consegui copiar as evidencias: $($_.Exception.Message)"
    }
} else {
    Mark-Bad 'a distro do agente nao existe (rode 0-INSTALAR-AGENTE)'
}

Write-Host ''
Write-Host '[servidor]'
if ($cfg -and (Test-AgServer ([int]$cfg.porta))) { Mark-Ok "respondendo em http://127.0.0.1:$($cfg.porta)" }
else { Mark-Info 'nao esta respondendo agora (normal se o 1-LIGAR-SERVIDOR estiver fechado ou em pausa)' }

Write-Host ''
if ($problemCount -eq 0) { Write-Host 'Tudo certo.' -ForegroundColor Green }
else { Write-Host "$problemCount problema(s). O relatorio ficou em: $reportPath" -ForegroundColor Yellow }
try { Stop-Transcript | Out-Null } catch { }
