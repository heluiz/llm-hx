# LLM-HX Agente - acoes dos atalhos: novo projeto, rodar, conversar, andamento, pausar, parar, abrir pasta.
# Compativel com Windows PowerShell 5.1. Mantenha este arquivo so com ASCII.
# Obs.: variaveis do PowerShell NAO diferenciam maiusculas/minusculas - use nomes distintos.
param(
    [ValidateSet('novo', 'rodar', 'conversar', 'andamento', 'pausa', 'parar', 'abrir')]
    [string] $Acao = 'andamento'
)
. (Join-Path $PSScriptRoot 'agente-comum.ps1')
$cfg = Get-AgConfig
$distro = "$($cfg.distro)"
$port = [int]$cfg.porta

function Assert-Instalado {
    if (-not (Test-AgDistro $distro)) { throw 'O agente ainda nao foi instalado. Rode 0-INSTALAR-AGENTE primeiro.' }
    # Kit atualizado no Windows (ex.: atalho novo)? Leva os scripts novos para dentro da distro antes de seguir.
    if (-not (Test-AgScriptsAtualizados $distro)) {
        Write-Host ''
        Write-Host 'Os scripts do agente dentro da distro estao desatualizados: atualizando (leva alguns segundos)...' -ForegroundColor Yellow
        $ErrorActionPreference = 'Continue'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $AgKit 'agente-instalar.ps1') -SoScripts -Auto
        $syncExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($syncExit -ne 0) { throw 'Nao consegui atualizar os scripts dentro da distro. Rode o ATUALIZAR-SCRIPTS e veja a mensagem de erro.' }
    }
}

function Select-Projeto {
    param([string]$Pergunta, [switch]$ComRascunho)
    $listResult = Invoke-Wsl @('-d', $distro, '--cd', '~', '-e', "$AgWslKit/bin/agente-status.sh", '--lista')
    $projList = @($listResult.Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[a-z0-9][a-z0-9_-]*$' })
    $draftAdded = $false
    if ($ComRascunho -and ($projList -notcontains 'rascunho')) {
        $projList += 'rascunho'
        $draftAdded = $true
    }
    if ($projList.Count -eq 0) { throw 'Nenhum projeto ainda. Use 2-NOVO-PROJETO primeiro.' }
    Write-Host ''
    for ($idx = 0; $idx -lt $projList.Count; $idx++) {
        $label = $projList[$idx]
        if ($draftAdded -and ($label -eq 'rascunho')) { $label = 'rascunho   (pasta livre, sem plano: testes e pedidos rapidos)' }
        Write-Host ('  {0}) {1}' -f ($idx + 1), $label)
    }
    $answer = Read-Host ('{0} [Enter = 1]' -f $Pergunta)
    $pickNum = 1
    if ($answer -match '^\s*\d+\s*$') { $pickNum = [int]$answer }
    if (($pickNum -lt 1) -or ($pickNum -gt $projList.Count)) { throw "Opcao invalida: $answer" }
    return $projList[$pickNum - 1]
}

function Select-Agente {
    $defaultAgent = "$($cfg.agentePadrao)"
    if ($defaultAgent -ne 'claude') { $defaultAgent = 'opencode' }
    Write-Host ''
    Write-Host '  1) OpenCode     (open source; prompt menor, sobra mais contexto - recomendado)'
    Write-Host '  2) Claude Code  (o programa da Anthropic, falando so com o seu modelo local)'
    $defaultNum = 1
    if ($defaultAgent -eq 'claude') { $defaultNum = 2 }
    $agentAnswer = Read-Host ('Qual agente [Enter = {0}]' -f $defaultNum)
    $agentName = $defaultAgent
    if ($agentAnswer -match '^\s*1\s*$') { $agentName = 'opencode' }
    if ($agentAnswer -match '^\s*2\s*$') { $agentName = 'claude' }
    return $agentName
}

function Show-AvisoServidor([string]$Depois) {
    if (Test-AgServer $port) { return }
    Write-Host ''
    Write-Host "O servidor do modelo nao respondeu na porta $port agora." -ForegroundColor Yellow
    if (Test-Path $AgPauseFlag) {
        Write-Host 'Motivo: esta PAUSADO por voce. Use 6-PAUSAR-OU-CONTINUAR para religar.' -ForegroundColor Yellow
    } elseif (Test-AgPregao $cfg (Get-Date)) {
        Write-Host ('Motivo: pausa do pregao ({0} as {1}). Ele religa sozinho no fim da pausa.' -f $cfg.pausaPregao.inicio, $cfg.pausaPregao.fim) -ForegroundColor Yellow
    } else {
        Write-Host 'Se ainda nao abriu, abra o 1-LIGAR-SERVIDOR (ou espere ele terminar de carregar o modelo).' -ForegroundColor Yellow
    }
    if ($Depois) { Write-Host $Depois -ForegroundColor Yellow }
}

switch ($Acao) {
    'novo' {
        Assert-Instalado
        Write-Host ''
        Write-Host '=== Novo projeto do agente ===' -ForegroundColor Cyan
        $rawName = Read-Host 'Nome do projeto (letras minusculas, numeros e hifen; ex.: meu-app)'
        $projName = (("$rawName".Trim().ToLower()) -replace '[^a-z0-9_-]+', '-').Trim('-')
        if (-not $projName) { throw 'Nome vazio.' }
        $useExample = Read-Host 'Criar com o EXEMPLO pronto (calculadora de risco/retorno em Python, bom para o 1o teste)? [s/N]'
        $novoArgs = @('-d', $distro, '--cd', '~', '-e', "$AgWslKit/bin/agente-novo.sh", $projName)
        if ($useExample -match '^\s*[sSyY]') { $novoArgs += '--exemplo' }
        $ErrorActionPreference = 'Continue'
        & wsl.exe @novoArgs
        $novoExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($novoExit -eq 0) {
            $projUnc = Join-Path (Get-AgUncProjetos $distro) $projName
            Write-Host ''
            Write-Host "Pasta do projeto no Windows: $projUnc" -ForegroundColor Green
            Write-Host 'Abrindo a pasta. Edite SPEC.md e PLAN.md (Bloco de Notas ou VS Code) e depois use 3-RODAR-AGENTE.'
            Write-Host 'Dica: o 4-CONVERSAR-COM-O-AGENTE ajuda a escrever o SPEC.md e o PLAN.md - e so pedir no chat.'
            try { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$projUnc`"" } catch { }
        }
    }
    'rodar' {
        Assert-Instalado
        Write-Host ''
        Write-Host '=== Rodar o agente (sozinho, ate terminar) ===' -ForegroundColor Cyan
        $projName = Select-Projeto 'Numero do projeto'
        $agentName = Select-Agente
        Show-AvisoServidor 'O agente fica esperando e comeca sozinho quando o servidor responder.'
        $host.UI.RawUI.WindowTitle = "Agente HX - $projName ($agentName)"
        Write-Host ''
        Write-Host 'Deixe esta janela aberta (pode minimizar). Fechar a janela interrompe o agente.' -ForegroundColor Yellow
        Write-Host 'Para parar no fim da rodada, com relatorio: 7-PARAR-PROJETO.' -ForegroundColor Yellow
        Write-Host ''
        $loopArgs = @('-d', $distro, '--cd', '~', '-e', "$AgWslKit/bin/agente-loop.sh", $projName,
                      '--agente', $agentName,
                      '--tentativas', "$($cfg.tentativasPorTarefa)",
                      '--minutos', "$($cfg.minutosPorRodada)",
                      '--rodadas', "$($cfg.rodadasMaximas)",
                      '--porta', "$port")
        $ErrorActionPreference = 'Continue'
        & wsl.exe @loopArgs
        $loopExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        Write-Host ''
        switch ($loopExit) {
            0 { Write-Host 'Terminou: todas as tarefas foram processadas. Leia o RELATORIO.md na pasta do projeto (8-ABRIR-PROJETOS).' -ForegroundColor Green }
            3 { Write-Host 'Parado a pedido. O RELATORIO.md mostra onde parou; rode de novo para continuar.' -ForegroundColor Green }
            4 { Write-Host 'Parou no limite de rodadas (config.json, rodadasMaximas). Rode de novo para continuar.' -ForegroundColor Yellow }
            default { Write-Host "O agente saiu com codigo $loopExit. Veja as mensagens acima." -ForegroundColor Yellow }
        }
    }
    'conversar' {
        Assert-Instalado
        Write-Host ''
        Write-Host '=== Conversar com o agente (modo chat) ===' -ForegroundColor Cyan
        Write-Host 'Voce digita os pedidos e acompanha cada passo: ele le, cria e altera os arquivos do projeto'
        Write-Host 'e roda comandos dentro da distro isolada, sempre com o seu modelo local.'
        $projName = Select-Projeto 'Conversar em qual projeto' -ComRascunho
        $agentName = Select-Agente
        Show-AvisoServidor 'A conversa abre sozinha assim que o servidor responder.'
        $host.UI.RawUI.WindowTitle = "Agente HX - conversa - $projName ($agentName)"
        $chatArgs = @('-d', $distro, '--cd', '~', '-e', "$AgWslKit/bin/agente-conversar.sh", $projName,
                      '--agente', $agentName, '--porta', "$port")
        $ErrorActionPreference = 'Continue'
        & wsl.exe @chatArgs
        $chatExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        Write-Host ''
        if ($chatExit -eq 0) {
            Write-Host 'Conversa encerrada. O que ele fez ficou na pasta do projeto (8-ABRIR-PROJETOS).' -ForegroundColor Green
        } else {
            Write-Host "A conversa terminou com codigo $chatExit. Veja as mensagens acima." -ForegroundColor Yellow
        }
    }
    'andamento' {
        Assert-Instalado
        $ErrorActionPreference = 'Continue'
        & wsl.exe -d $distro --cd '~' -e "$AgWslKit/bin/agente-status.sh"
        $ErrorActionPreference = 'Stop'
        $projName = $null
        try { $projName = Select-Projeto 'Ver detalhes de qual projeto' } catch { $projName = $null }
        if ($projName) {
            $ErrorActionPreference = 'Continue'
            & wsl.exe -d $distro --cd '~' -e "$AgWslKit/bin/agente-status.sh" $projName
            $ErrorActionPreference = 'Stop'
        }
        Write-Host ''
        if (Test-Path $AgPauseFlag) { Write-Host 'Servidor: PAUSADO por voce (6-PAUSAR-OU-CONTINUAR para religar).' -ForegroundColor Yellow }
        elseif (Test-AgServer $port) { Write-Host "Servidor: ligado e respondendo na porta $port." -ForegroundColor Green }
        else { Write-Host 'Servidor: desligado agora (janela 1-LIGAR-SERVIDOR fechada ou pausa do pregao).' -ForegroundColor Yellow }
    }
    'pausa' {
        if (Test-Path $AgPauseFlag) {
            Remove-Item $AgPauseFlag -Force
            Write-Host 'CONTINUANDO: o servidor religa em ate 20 segundos (se a janela 1-LIGAR-SERVIDOR estiver aberta)' -ForegroundColor Green
            Write-Host 'e o agente segue de onde parou.' -ForegroundColor Green
        } else {
            Set-Content -Path $AgPauseFlag -Value ("pausado em {0:dd/MM/yyyy HH:mm}" -f (Get-Date)) -Encoding ASCII
            Write-Host 'PAUSADO: o servidor desliga em ate 20 segundos e libera a placa de video e a RAM.' -ForegroundColor Yellow
            Write-Host 'O agente espera parado. Rode este atalho de novo para continuar.' -ForegroundColor Yellow
        }
    }
    'parar' {
        Assert-Instalado
        Write-Host ''
        Write-Host '=== Parar um projeto (no fim da rodada atual) ===' -ForegroundColor Cyan
        $projName = Select-Projeto 'Numero do projeto'
        $ErrorActionPreference = 'Continue'
        & wsl.exe -d $distro --cd '~' -e "$AgWslKit/bin/agente-status.sh" --parar $projName
        $ErrorActionPreference = 'Stop'
    }
    'abrir' {
        Assert-Instalado
        [void](Invoke-Wsl @('-d', $distro, '--cd', '~', '-e', 'true'))   # liga a distro para o Explorer enxergar
        $projRoot = Get-AgUncProjetos $distro
        Write-Host "Abrindo $projRoot"
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$projRoot`""
    }
}
