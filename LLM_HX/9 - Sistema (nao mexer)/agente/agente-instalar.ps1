# LLM-HX Agente - instalacao (uma vez). Pode rodar de novo: so refaz o que falta e atualiza os scripts.
# Cria uma distro WSL separada ("AgenteHX", Ubuntu 24.04) onde o agente trabalha isolado do Windows:
# sem acesso ao disco C:, sem abrir programas do Windows e sem sudo. Instala OpenCode e Claude Code
# (versoes fixas), que conversam so com o seu llama-server local.
# Compativel com Windows PowerShell 5.1. Mantenha este arquivo so com ASCII.
# Obs.: variaveis do PowerShell NAO diferenciam maiusculas/minusculas - use nomes distintos.
param(
    [switch] $SoScripts,   # so atualiza os scripts dentro da distro (rapido; nao reinicia a distro)
    [switch] $Auto         # chamado pelos outros atalhos: atualiza e sai, sem conferencia nem mensagens finais
)

. (Join-Path $PSScriptRoot 'agente-comum.ps1')
$cfg = Get-AgConfig
$distro = "$($cfg.distro)"
$distroDir = "$($cfg.pastaDistro)"
$downloadDir = "$($cfg.pastaDownload)"
$ocVersion = "$($cfg.versaoOpenCode)"
$ccVersion = "$($cfg.versaoClaudeCode)"
$rootfsBase = 'https://cloud-images.ubuntu.com/wsl/releases/24.04/current'
$rootfsName = 'ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz'

try { Start-Transcript -Path (Join-Path $AgLogs 'instalacao.log') -Append | Out-Null } catch { }
try {
    Write-Host ''
    Write-Host '=== Agente HX: instalacao ===' -ForegroundColor Cyan

    # ---------- 1. WSL
    Say 'Conferindo o WSL...'
    $wslVer = Invoke-Wsl @('--version')
    if ($wslVer.Code -ne 0) {
        throw 'O WSL nao respondeu. Abra o PowerShell como administrador, rode:  wsl --install --no-distribution  , reinicie o PC e rode este instalador de novo.'
    }
    ($wslVer.Text -split "`n" | Select-Object -First 2) | ForEach-Object { Write-Host "   $_" }

    # ---------- 2. rede espelhada (o agente no WSL alcanca o llama-server do Windows em 127.0.0.1)
    if (-not $SoScripts) {
        Say 'Rede do WSL (modo espelhado)...'
        $wslCfgPath = Join-Path $env:USERPROFILE '.wslconfig'
        $cfgLines = @()
        if (Test-Path $wslCfgPath) { $cfgLines = @(Get-Content -Path $wslCfgPath -Encoding UTF8) }
        $modeLine = $cfgLines | Where-Object { $_ -match '^\s*networkingMode\s*=' } | Select-Object -First 1
        $needShutdown = $false
        if ($modeLine -and ($modeLine -match '=\s*mirrored\s*$')) {
            Write-Host '   ja esta no modo espelhado (mirrored).' -ForegroundColor Green
        } elseif ($modeLine) {
            Write-Host "   ATENCAO: seu .wslconfig ja usa outro modo de rede: $modeLine" -ForegroundColor Yellow
            Write-Host '   O agente precisa de networkingMode=mirrored para enxergar o llama-server. Nao mexi no arquivo.' -ForegroundColor Yellow
        } else {
            if (Test-Path $wslCfgPath) { Copy-Item -Path $wslCfgPath -Destination "$wslCfgPath.antes-do-agente" -Force }
            $newLines = New-Object System.Collections.ArrayList
            $inserted = $false
            foreach ($cfgLine in $cfgLines) {
                [void]$newLines.Add($cfgLine)
                if ((-not $inserted) -and ($cfgLine -match '^\s*\[wsl2\]\s*$')) { [void]$newLines.Add('networkingMode=mirrored'); $inserted = $true }
            }
            if (-not $inserted) {
                if ($newLines.Count -gt 0) { [void]$newLines.Add('') }
                [void]$newLines.Add('[wsl2]')
                [void]$newLines.Add('networkingMode=mirrored')
            }
            Set-Content -Path $wslCfgPath -Value $newLines -Encoding ASCII
            Write-Host "   gravei networkingMode=mirrored em $wslCfgPath" -ForegroundColor Green
            $needShutdown = $true
        }
        if ($needShutdown) {
            Write-Host ''
            Write-Host 'Preciso reiniciar o WSL para a rede nova valer. Isso fecha qualquer distro aberta agora' -ForegroundColor Yellow
            Write-Host '(por exemplo, a do seu laboratorio). Nada e apagado.' -ForegroundColor Yellow
            [void](Read-Host 'Aperte Enter para continuar (ou feche esta janela para cancelar)')
            [void](Invoke-Wsl @('--shutdown'))
        }
    }

    # ---------- 3. distro do agente
    $hasDistro = Test-AgDistro $distro
    if ($SoScripts -and -not $hasDistro) { throw "A distro $distro nao existe ainda. Rode o 0-INSTALAR-AGENTE completo." }
    if (-not $hasDistro) {
        Say "Baixando o Ubuntu 24.04 para a distro $distro (~340 MB)..."
        New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
        $tarPath = Join-Path $downloadDir $rootfsName
        $sumsPath = Join-Path $downloadDir 'SHA256SUMS'
        $ErrorActionPreference = 'Continue'
        & curl.exe -sSL --fail --retry 5 -o $sumsPath "$rootfsBase/SHA256SUMS"
        $ErrorActionPreference = 'Stop'
        if (-not (Test-Path $sumsPath)) { throw "Nao consegui baixar $rootfsBase/SHA256SUMS (internet?)." }
        $sumLine = Get-Content -Path $sumsPath | Where-Object { $_ -match ([regex]::Escape($rootfsName) + '\s*$') } | Select-Object -First 1
        if (-not $sumLine) { throw "Nao achei o SHA256 de $rootfsName em $rootfsBase/SHA256SUMS." }
        $expectedHash = ($sumLine -split '\s+')[0].ToLower()
        $okFile = $false
        if (Test-Path $tarPath) { $okFile = ((Get-FileHash -Path $tarPath -Algorithm SHA256).Hash.ToLower() -eq $expectedHash) }
        if (-not $okFile) {
            $partPath = "$tarPath.part"
            $ErrorActionPreference = 'Continue'
            & curl.exe -L --fail --retry 10 --retry-delay 5 -C - -o $partPath "$rootfsBase/$rootfsName"
            $ErrorActionPreference = 'Stop'
            if (-not (Test-Path $partPath)) { throw 'O download do Ubuntu falhou. Rode o instalador de novo (ele retoma).' }
            $gotHash = (Get-FileHash -Path $partPath -Algorithm SHA256).Hash.ToLower()
            if ($gotHash -ne $expectedHash) {
                Remove-Item $partPath -Force
                throw 'O arquivo do Ubuntu veio corrompido (SHA256 nao bate). Apaguei; rode o instalador de novo.'
            }
            if (Test-Path $tarPath) { Remove-Item $tarPath -Force }
            Move-Item -Path $partPath -Destination $tarPath
        }
        Write-Host '   download conferido (SHA256 ok).' -ForegroundColor Green

        Say "Criando a distro $distro em $distroDir ..."
        New-Item -ItemType Directory -Force -Path $distroDir | Out-Null
        $imp = Invoke-Wsl @('--import', $distro, $distroDir, $tarPath, '--version', '2')
        if ($imp.Code -ne 0) { throw "wsl --import falhou: $($imp.Text)" }
        Write-Host "   distro $distro criada." -ForegroundColor Green
    } else {
        Write-Host ''
        Write-Host "A distro $distro ja existe; vou so atualizar o que for preciso." -ForegroundColor Green
    }

    # ---------- 4. copia os scripts para dentro da distro
    Say 'Copiando os scripts do agente para dentro da distro...'
    $prep = Invoke-Wsl @('-d', $distro, '-u', 'root', '--cd', '~', '-e', 'sh', '-c', 'rm -rf /opt/agente-hx-novo && mkdir -p /opt/agente-hx-novo && chmod 777 /opt/agente-hx-novo')
    if ($prep.Code -ne 0) { throw "Nao consegui preparar a pasta na distro: $($prep.Text)" }
    # mantem a distro ligada durante a copia
    $keepAlive = Start-Process -FilePath 'wsl.exe' -ArgumentList @('-d', $distro, '-u', 'root', '--cd', '~', '-e', 'sleep', '300') -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
    $destUnc = $null
    foreach ($prefix in @('\\wsl.localhost\', '\\wsl$\')) {
        $candidate = $prefix + $distro + '\opt\agente-hx-novo'
        if (Test-Path -LiteralPath $candidate) { $destUnc = $candidate; break }
    }
    if (-not $destUnc) { throw "Nao consegui abrir a distro pelo Explorer (\\wsl.localhost\$distro). Rode o instalador de novo." }
    Copy-Item -Path (Join-Path (Join-Path $AgKit 'wsl') '*') -Destination $destUnc -Recurse -Force
    Set-Content -LiteralPath (Join-Path $destUnc '.versao-kit') -Value (Get-AgKitHash) -Encoding ASCII
    try { Stop-Process -Id $keepAlive.Id -Force -ErrorAction SilentlyContinue } catch { }

    # ---------- 5. instalacao dentro da distro (pacotes, usuario, ferramentas, isolamento)
    if ($SoScripts) { Say 'Atualizando os scripts (sem mexer em pacotes)...' } else { Say 'Instalando dentro da distro (pacotes, OpenCode, Claude Code) - leva alguns minutos...' }
    $instArgs = @('-d', $distro, '-u', 'root', '--cd', '~', '-e', 'bash', '/opt/agente-hx-novo/instalar.sh', '--usuario', $AgWslUser, '--opencode', $ocVersion, '--claude', $ccVersion)
    if ($SoScripts) { $instArgs += '--so-scripts' }
    $ErrorActionPreference = 'Continue'
    & wsl.exe @instArgs
    $instExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    [void](Invoke-Wsl @('-d', $distro, '-u', 'root', '--cd', '~', '-e', 'rm', '-rf', '/opt/agente-hx-novo'))
    if ($instExit -ne 0) { throw "A instalacao dentro da distro falhou (codigo $instExit). Veja as mensagens acima e rode de novo." }

    # ---------- 5b. plugins, MCPs e ferramentas extras: REA (+ Ghidra e JADX do C:\tools), Ponytail, Pyright
    # Falha aqui nao derruba nada: o agente funciona sem os extras, e o ATUALIZAR-SCRIPTS tenta de novo.
    if ("$($cfg.extras)" -eq 'False') {
        Write-Host ''
        Write-Host 'Plugins e MCPs: desligados no config.json ("extras": false).'
    } else {
        $extrasStamp = Get-AgExtrasStamp $cfg
        $stampNow = Invoke-Wsl @('-d', $distro, '--cd', '~', '-e', 'cat', '/opt/agente-hx-extras/.versao')
        $extrasCurrent = ($stampNow.Code -eq 0) -and ("$($stampNow.Text)".Trim() -eq $extrasStamp)
        if (-not ($Auto -and $extrasCurrent)) {
            Say 'Plugins e MCPs do agente: REA (+ Ghidra e JADX do seu C:\tools), Ponytail e Pyright...'
            if (-not $extrasCurrent) { Write-Host '   Na primeira vez leva alguns minutos (baixa o Node.js, o REA e o Java).' -ForegroundColor Yellow }
            $prepX = Invoke-Wsl @('-d', $distro, '-u', 'root', '--cd', '~', '-e', 'sh', '-c', 'rm -rf /opt/agente-hx-staging && mkdir -p /opt/agente-hx-staging && chmod 777 /opt/agente-hx-staging')
            $toolsDir = 'C:\tools'
            $ghidraSrc = $null
            $jadxSrc = $null
            if (Test-Path -LiteralPath $toolsDir) {
                $ghidraSrc = Get-ChildItem -LiteralPath $toolsDir -Directory -Filter 'ghidra_*_PUBLIC' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
                $jadxSrc = Get-ChildItem -LiteralPath $toolsDir -File -Filter 'jadx*.jar' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
            }
            $needGhidra = $false
            $needJadx = $false
            if ($ghidraSrc) { $needGhidra = ((Invoke-Wsl @('-d', $distro, '--cd', '~', '-e', 'test', '-d', "/opt/agente-hx-extras/ghidra/$($ghidraSrc.Name)")).Code -ne 0) }
            if ($jadxSrc) { $needJadx = ((Invoke-Wsl @('-d', $distro, '--cd', '~', '-e', 'test', '-f', "/opt/agente-hx-extras/jadx/$($jadxSrc.Name)")).Code -ne 0) }
            if (($prepX.Code -eq 0) -and ($needGhidra -or $needJadx)) {
                $keepAlive2 = Start-Process -FilePath 'wsl.exe' -ArgumentList @('-d', $distro, '-u', 'root', '--cd', '~', '-e', 'sleep', '1800') -WindowStyle Hidden -PassThru
                Start-Sleep -Seconds 2
                $stageUnc = $null
                foreach ($prefix in @('\\wsl.localhost\', '\\wsl$\')) {
                    $candidate = $prefix + $distro + '\opt\agente-hx-staging'
                    if (Test-Path -LiteralPath $candidate) { $stageUnc = $candidate; break }
                }
                if ($stageUnc) {
                    if ($needJadx) {
                        Copy-Item -LiteralPath $jadxSrc.FullName -Destination $stageUnc -Force
                        Write-Host "   JADX: $($jadxSrc.Name)"
                    }
                    if ($needGhidra) {
                        Write-Host "   Ghidra: empacotando $($ghidraSrc.FullName) (~900 MB, alguns minutos)..."
                        New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
                        $tarLocal = Join-Path $downloadDir ($ghidraSrc.Name + '.tar')
                        $tarExit = 1
                        $ErrorActionPreference = 'Continue'
                        try { & tar.exe -cf $tarLocal -C $ghidraSrc.Parent.FullName $ghidraSrc.Name; $tarExit = $LASTEXITCODE } catch { $tarExit = 1 }
                        $ErrorActionPreference = 'Stop'
                        if (($tarExit -eq 0) -and (Test-Path -LiteralPath $tarLocal)) {
                            Copy-Item -LiteralPath $tarLocal -Destination (Join-Path $stageUnc 'ghidra.tar') -Force
                        } else {
                            Write-Host '   nao consegui empacotar o Ghidra; sigo sem ele.' -ForegroundColor Yellow
                        }
                        Remove-Item -LiteralPath $tarLocal -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Host '   nao abri a pasta de passagem da distro; sigo sem Ghidra e JADX.' -ForegroundColor Yellow
                }
                try { Stop-Process -Id $keepAlive2.Id -Force -ErrorAction SilentlyContinue } catch { }
            }
            $extrasArgs = @('-d', $distro, '-u', 'root', '--cd', '~', '-e', 'bash', "$AgWslKit/extras/instalar-extras.sh",
                            '--usuario', $AgWslUser,
                            '--node', (Get-AgCfgValue $cfg 'versaoNode' '24'),
                            '--rea', (Get-AgCfgValue $cfg 'versaoRea' '6.5.0'),
                            '--carimbo', $extrasStamp)
            $ErrorActionPreference = 'Continue'
            & wsl.exe @extrasArgs
            $extrasExit = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            [void](Invoke-Wsl @('-d', $distro, '-u', 'root', '--cd', '~', '-e', 'rm', '-rf', '/opt/agente-hx-staging'))
            if ($extrasExit -eq 0) {
                Write-Host 'Plugins e MCPs prontos.' -ForegroundColor Green
            } else {
                Write-Host 'Plugins e MCPs: faltou alguma parte (veja acima). O agente funciona normal; para tentar de novo, rode o ATUALIZAR-SCRIPTS.' -ForegroundColor Yellow
            }
        }
    }

    if ($Auto) {
        Write-Host 'Scripts atualizados.' -ForegroundColor Green
        return
    }

    # ---------- 6. reinicia a distro para o isolamento valer (so na instalacao) e confere
    # Na atualizacao dos scripts NAO reinicia: um agente rodando em outro projeto continua trabalhando.
    if (-not $SoScripts) {
        Say 'Reiniciando a distro para o isolamento valer...'
        [void](Invoke-Wsl @('--terminate', $distro))
        Start-Sleep -Seconds 3
    }
    Say 'Conferindo a instalacao...'
    $ErrorActionPreference = 'Continue'
    & wsl.exe -d $distro --cd '~' -e /opt/agente-hx/bin/agente-verificar.sh --porta "$($cfg.porta)"
    $verifExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    Write-Host ''
    if ($verifExit -eq 0) {
        Write-Host 'Instalacao concluida.' -ForegroundColor Green
    } else {
        Write-Host 'Instalacao concluida, mas a conferencia apontou problema(s) acima. Rode 9-DIAGNOSTICO e me mande o resultado.' -ForegroundColor Yellow
    }
    Write-Host 'Proximos passos: 1-LIGAR-SERVIDOR (deixe aberto), depois 2-NOVO-PROJETO e 3-RODAR-AGENTE.'
    Write-Host 'Para conversar com o agente (modo chat, voce da os comandos): 4-CONVERSAR-COM-O-AGENTE.'
    Write-Host 'Guia completo: COMO-USAR.txt nesta pasta.'
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
