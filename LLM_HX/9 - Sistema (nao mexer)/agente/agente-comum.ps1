# LLM-HX Agente - funcoes comuns. Os outros scripts carregam este com:  . (Join-Path $PSScriptRoot 'agente-comum.ps1')
# Compativel com Windows PowerShell 5.1. Mantenha este arquivo so com ASCII (5.1 le .ps1 sem BOM como ANSI).
# Obs.: variaveis do PowerShell NAO diferenciam maiusculas/minusculas - use nomes distintos.

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$env:WSL_UTF8 = '1'      # faz o wsl.exe responder em UTF-8 (sem isso vem UTF-16 e a leitura quebra)
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }   # e o PowerShell le essa saida como UTF-8

$AgKit = $PSScriptRoot                                   # ...\9 - Sistema (nao mexer)\agente
$AgRoot = 'C:\LLM'
if ($env:LLMHX_ROOT) { $AgRoot = $env:LLMHX_ROOT }       # apenas para testes
$AgLogs = Join-Path $AgKit 'logs'
New-Item -ItemType Directory -Force -Path $AgLogs | Out-Null
$AgPauseFlag = Join-Path $AgKit 'PAUSADO.flag'
$AgWslUser = 'agente'
$AgWslKit  = '/opt/agente-hx'
$AgWslProj = '/home/agente/projetos'

function Say([string]$Msg, [string]$Color = 'Cyan') {
    Write-Host ''
    Write-Host ">>> $Msg" -ForegroundColor $Color
}

function Get-AgConfig {
    $cfgPath = Join-Path $AgKit 'config.json'
    if (-not (Test-Path $cfgPath)) { throw "Nao achei o arquivo de configuracao: $cfgPath" }
    try {
        $cfgObj = Get-Content -Path $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "O config.json tem erro de digitacao (virgula ou aspas faltando?): $($_.Exception.Message)"
    }
    return $cfgObj
}

# Roda o wsl.exe e devolve codigo + texto. Nao lanca erro (stderr de programa nativo no PS 5.1 viraria excecao).
function Invoke-Wsl([string[]]$WslArgs) {
    $ErrorActionPreference = 'Continue'
    $outLines = & wsl.exe @WslArgs 2>&1
    $exitCode = $LASTEXITCODE
    $joined = (@($outLines) | ForEach-Object { "$_" }) -join "`n"
    $joined = $joined -replace "`0", ''
    return [pscustomobject]@{ Code = $exitCode; Text = $joined }
}

# Impressao digital dos scripts do kit (pasta wsl): diz se a copia dentro da distro esta em dia.
function Get-AgKitHash {
    $wslDir = Join-Path $AgKit 'wsl'
    $sb = New-Object System.Text.StringBuilder
    Get-ChildItem -LiteralPath $wslDir -Recurse -File | Sort-Object -Property FullName | ForEach-Object {
        $relPath = $_.FullName.Substring($wslDir.Length).TrimStart('\') -replace '\\', '/'
        $fileHash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        [void]$sb.Append("$relPath $fileHash`n")
    }
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $digest = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
    return (($digest | ForEach-Object { $_.ToString('x2') }) -join '')
}
# Valor do config.json com padrao (chaves novas podem nao existir no config.json de quem ja instalou).
function Get-AgCfgValue($CfgObj, [string]$Name, [string]$Default) {
    $cfgValue = $CfgObj.$Name
    if (($null -eq $cfgValue) -or ("$cfgValue" -eq '')) { return $Default }
    return "$cfgValue"
}
# Carimbo dos extras (plugins/MCPs): arquivos de wsl\extras + versoes pedidas. Mudou = reinstala.
function Get-AgExtrasStamp($CfgObj) {
    $extrasDir = Join-Path (Join-Path $AgKit 'wsl') 'extras'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(("node={0} rea={1}`n" -f (Get-AgCfgValue $CfgObj 'versaoNode' '24'), (Get-AgCfgValue $CfgObj 'versaoRea' '6.5.0')))
    if (Test-Path -LiteralPath $extrasDir) {
        Get-ChildItem -LiteralPath $extrasDir -Recurse -File | Sort-Object -Property FullName | ForEach-Object {
            $relPath = $_.FullName.Substring($extrasDir.Length).TrimStart('\') -replace '\\', '/'
            [void]$sb.Append("$relPath $((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)`n")
        }
    }
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $digest = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
    return (($digest | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Test-AgScriptsAtualizados([string]$DistroName) {
    $stamp = Invoke-Wsl @('-d', $DistroName, '--cd', '~', '-e', 'cat', "$AgWslKit/.versao-kit")
    if ($stamp.Code -ne 0) { return $false }
    return ("$($stamp.Text)".Trim() -eq (Get-AgKitHash))
}
function Test-AgDistro([string]$DistroName) {
    $listing = Invoke-Wsl @('--list', '--quiet')
    if ($listing.Code -ne 0) { return $false }
    $names = @($listing.Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    return ($names -contains $DistroName)
}

# Caminho do Windows para a pasta de projetos dentro da distro (\\wsl.localhost\... ou \\wsl$\...).
function Get-AgUncProjetos([string]$DistroName) {
    foreach ($prefix in @('\\wsl.localhost\', '\\wsl$\')) {
        $candidate = $prefix + $DistroName + '\home\' + $AgWslUser + '\projetos'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return ('\\wsl.localhost\' + $DistroName + '\home\' + $AgWslUser + '\projetos')
}

# Modelos de C:\LLM\models: arquivo principal = maior .gguf que nao seja mmproj nem cabeca MTP (mesma regra do run-model.ps1).
function Get-AgModelInfo([string]$DirName) {
    $preset = 'qwen'
    $nota = ''
    if ($DirName -match 'coder') { $preset = 'coder'; $nota = 'especialista em codigo - o mais indicado para o agente' }
    elseif ($DirName -match '^gemma') { $preset = 'gemma'; $nota = 'o mais rapido, porem o menos capaz em tarefas longas' }
    elseif ($DirName -match 'qwen36') { $nota = 'o melhor geral dos seus modelos' }
    elseif ($DirName -match 'apex') { $nota = 'mais leve na RAM; o autor avisa que pode se repetir em respostas longas' }
    return [pscustomobject]@{ Preset = $preset; Nota = $nota }
}

function Get-AgModels {
    $modelsRoot = Join-Path $AgRoot 'models'
    $found = @()
    if (-not (Test-Path $modelsRoot)) { return $found }
    foreach ($modelFolder in (Get-ChildItem -Path $modelsRoot -Directory | Sort-Object Name)) {
        $mainFile = Get-ChildItem -Path $modelFolder.FullName -Filter '*.gguf' -File |
            Where-Object { ($_.Name -notmatch 'mmproj') -and ($_.Name -notmatch '^mtp') } |
            Sort-Object Length -Descending | Select-Object -First 1
        if (-not $mainFile) { continue }
        $tunedObj = $null
        $tunedPath = Join-Path (Join-Path $AgRoot 'tuned') "$($modelFolder.Name).json"
        if (Test-Path $tunedPath) {
            try { $tunedObj = Get-Content -Path $tunedPath -Raw | ConvertFrom-Json } catch { $tunedObj = $null }
        }
        $meta = Get-AgModelInfo $modelFolder.Name
        $found += [pscustomobject]@{
            Dir = $modelFolder.Name; File = $mainFile; SizeGb = [math]::Round($mainFile.Length / 1GB, 1)
            Preset = $meta.Preset; Nota = $meta.Nota; Tuned = $tunedObj
        }
    }
    return $found
}

function Get-AgSamplingArgs([string]$PresetName) {
    if ($PresetName -eq 'gemma') { return @('--temp', '1.0', '--top-p', '0.95', '--top-k', '64', '--min-p', '0') }
    if ($PresetName -eq 'coder') { return @('--temp', '0.7', '--top-p', '0.8', '--top-k', '20', '--repeat-penalty', '1.05') }
    return @('--temp', '0.6', '--top-p', '0.95', '--top-k', '20', '--min-p', '0')
}

# Monta a linha de argumentos com aspas onde precisa (Start-Process do PS 5.1 nao poe aspas sozinho).
function ConvertTo-AgArgString([string[]]$ArgList) {
    $quoted = foreach ($item in $ArgList) {
        if ($item -match '[\s"]') { '"' + ($item -replace '"', '\"') + '"' } else { $item }
    }
    return ($quoted -join ' ')
}

# Pausa do pregao: dias "seg,ter,qua,qui,sex" e horario "09:00"-"13:30" (pode virar a meia-noite).
function Test-AgPregao($CfgObj, [datetime]$When) {
    $pausa = $CfgObj.pausaPregao
    if (-not $pausa) { return $false }
    if (-not $pausa.ativa) { return $false }
    $dayMap = @{ 'dom' = 0; 'seg' = 1; 'ter' = 2; 'qua' = 3; 'qui' = 4; 'sex' = 5; 'sab' = 6 }
    $plain = ("$($pausa.dias)".ToLower().Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '')
    $dayList = @()
    foreach ($token in ($plain -split '[,; ]+')) {
        if ($token.Length -ge 3) {
            $key = $token.Substring(0, 3)
            if ($dayMap.ContainsKey($key)) { $dayList += $dayMap[$key] }
        }
    }
    $startTs = [timespan]::Parse("$($pausa.inicio)")
    $endTs   = [timespan]::Parse("$($pausa.fim)")
    $nowTs   = $When.TimeOfDay
    $dow     = [int]$When.DayOfWeek
    if ($startTs -le $endTs) {
        return (($dayList -contains $dow) -and ($nowTs -ge $startTs) -and ($nowTs -lt $endTs))
    }
    if (($dayList -contains $dow) -and ($nowTs -ge $startTs)) { return $true }
    $yesterday = ($dow + 6) % 7
    return (($dayList -contains $yesterday) -and ($nowTs -lt $endTs))
}

function Test-AgServer([int]$PortNumber) {
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri ("http://127.0.0.1:{0}/health" -f $PortNumber)
        return ($resp.StatusCode -eq 200)
    } catch {
        return $false
    }
}

# llama-server.exe rodando: os do agente (na porta do agente) e os outros (chat aberto pelos atalhos 1-4).
function Get-AgLlamaProcs([int]$PortNumber) {
    $agentProcs = @()
    $otherProcs = @()
    try {
        $all = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction Stop)
        foreach ($proc in $all) {
            if ("$($proc.CommandLine)" -match "--port\s+$PortNumber\b") { $agentProcs += $proc } else { $otherProcs += $proc }
        }
    } catch { }
    return [pscustomobject]@{ Agent = $agentProcs; Other = $otherProcs }
}
