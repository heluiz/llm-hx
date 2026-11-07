# LLM-HX setup - instala llama.cpp (CUDA) e baixa os modelos Abliterated
# Destino: C:\LLM (fora do OneDrive/Desktop para nao sincronizar ~65 GB)
# Pode rodar de novo a qualquer momento: atualiza o llama.cpp e retoma downloads interrompidos.
# Compativel com Windows PowerShell 5.1. Mantenha este arquivo so com ASCII (5.1 le .ps1 sem BOM como ANSI).
# Obs.: variaveis do PowerShell NAO diferenciam maiusculas/minusculas - use nomes distintos.

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Root = 'C:\LLM'
if ($env:LLMHX_ROOT) { $Root = $env:LLMHX_ROOT }   # apenas para testes
$LlamaDir  = Join-Path $Root 'llama.cpp'
$ModelsDir = Join-Path $Root 'models'
$TempDir   = [IO.Path]::GetTempPath()
$ServerExe = Join-Path $LlamaDir 'llama-server.exe'
New-Item -ItemType Directory -Force -Path $Root, $LlamaDir, $ModelsDir | Out-Null

function Say([string]$Msg, [string]$Color = 'Cyan') {
    Write-Host ''
    Write-Host ">>> $Msg" -ForegroundColor $Color
}

# Baixa com curl.exe (nativo no Windows 10/11) para "<arquivo>.part", com retomada.
# So renomeia para o nome final quando o tamanho bate - arquivo incompleto nunca e usado.
# Retorna $true se o arquivo final esta completo.
function Save-Download([string]$Url, [string]$OutFile, [long]$Size, [string]$Label) {
    if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -eq $Size)) {
        Write-Host "   ja baixado: $Label" -ForegroundColor Green
        return $true
    }
    $part = "$OutFile.part"
    if ((Test-Path $part) -and ((Get-Item $part).Length -gt $Size)) { Remove-Item $part -Force }
    Write-Host ("   baixando {0} ({1:N2} GB)..." -f $Label, ($Size / 1GB))
    & curl.exe -L --fail --retry 10 --retry-delay 5 -C - -o $part $Url
    $curlExit = $LASTEXITCODE
    if ((Test-Path $part) -and ((Get-Item $part).Length -eq $Size)) {
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
        Move-Item -Path $part -Destination $OutFile
        Write-Host "   ok: $Label" -ForegroundColor Green
        return $true
    }
    Write-Warning "Download incompleto: $Label (curl saiu com codigo $curlExit). Rode o instalador de novo para retomar."
    return $false
}

# ---------- 1. llama.cpp (build CUDA mais recente para Windows x64) ----------
Say 'Procurando o build mais recente do llama.cpp (CUDA, Windows x64)...'
$releaseList = Invoke-RestMethod -Uri 'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=30' -UserAgent 'LLM-HX'

# O release marcado "Latest" (ex.: v0.6.0) pode vir sem binarios; os builds bNNNN trazem os .zip.
# Prefere CUDA 12.x (compatibilidade maxima); usa CUDA 13.x se nao houver 12.
$pickedRelease = $null
$zipLlama  = $null
$zipCudart = $null
foreach ($rel in $releaseList) {
    foreach ($cudaMajor in @('12', '13')) {
        $candLlama  = $rel.assets | Where-Object { $_.name -match "^llama-.+-bin-win-cuda-$cudaMajor(\.\d+)*-x64\.zip$" } | Select-Object -First 1
        $candCudart = $rel.assets | Where-Object { $_.name -match "^cudart-llama-bin-win-cuda-$cudaMajor(\.\d+)*-x64\.zip$" } | Select-Object -First 1
        if ($candLlama -and $candCudart) {
            $pickedRelease = $rel
            $zipLlama  = $candLlama
            $zipCudart = $candCudart
            break
        }
    }
    if ($pickedRelease) { break }
}
if (-not $pickedRelease) { throw 'Nao encontrei build CUDA para Windows nos ultimos 30 releases do llama.cpp.' }

$tag = $pickedRelease.tag_name
$versionFile = Join-Path $LlamaDir 'VERSION.txt'
$installedTag = ''
if (Test-Path $versionFile) { $installedTag = (Get-Content $versionFile -Raw).Trim() }

if (($installedTag -eq $tag) -and (Test-Path $ServerExe)) {
    Say "llama.cpp $tag ja instalado." 'Green'
} else {
    if (Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue) {
        throw 'Ha um modelo aberto (llama-server). Feche a janela do modelo e rode o instalador de novo.'
    }
    Write-Host "   build escolhido: $tag  ($($zipLlama.name) + $($zipCudart.name))"
    foreach ($asset in @($zipLlama, $zipCudart)) {
        $zipPath = Join-Path $TempDir $asset.name
        $ok = Save-Download -Url $asset.browser_download_url -OutFile $zipPath -Size $asset.size -Label $asset.name
        if (-not $ok) { throw "Falha ao baixar $($asset.name). Rode o instalador de novo." }
        Write-Host "   extraindo $($asset.name)..."
        & tar.exe -xf $zipPath -C $LlamaDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host '   tar.exe falhou; usando Expand-Archive (mais lento)...' -ForegroundColor Yellow
            Expand-Archive -Path $zipPath -DestinationPath $LlamaDir -Force
        }
        Remove-Item $zipPath -Force
    }
    if (-not (Test-Path $ServerExe)) { throw "llama-server.exe nao apareceu em $LlamaDir depois de extrair." }
    Set-Content -Path $versionFile -Value $tag -Encoding ASCII
    Say "llama.cpp $tag instalado em $LlamaDir" 'Green'
}

# ---------- 2. Modelos (Hugging Face) ----------
# Cada item: repo, pasta local, regex dos arquivos (conferidos contra a lista real de cada repo)
$plan = @(
    @{ Repo = 'Youssofal/Qwen3.6-35B-A3B-Abliterated-Heretic-GGUF'; Dir = 'qwen36-35b-a3b-heretic';
       Want = @('Q4_K_M\.gguf$', 'mmproj.*\.gguf$') },
    @{ Repo = 'culturerevolt/gemma-4-12b-heretic-abliterated-GGUF'; Dir = 'gemma4-12b-heretic';
       Want = @('IQ4_XS\.gguf$', 'mmproj.*\.gguf$') },
    @{ Repo = 'IsValorum/Qwen3.8-35B-A3B-Distill-MTP-APEX-I-MiniPlus-V2.1-Abliterated-GGUF'; Dir = 'qwen38-35b-a3b-apex';
       Want = @('Abliterated\.gguf$', 'mmproj.*\.gguf$') },
    # Especialista em codigo (modelo original da Qwen, sem alteracao). Usado pelo agente de tarefas longas.
    @{ Repo = 'unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF'; Dir = 'qwen3-coder-30b-a3b';
       Want = @('Instruct-Q4_K_M\.gguf$') }
)

$problems = 0
foreach ($item in $plan) {
    Say "Modelo: $($item.Repo)"
    $destDir = Join-Path $ModelsDir $item.Dir
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $treeList = Invoke-RestMethod -Uri "https://huggingface.co/api/models/$($item.Repo)/tree/main?recursive=true"
    $ggufList = @($treeList | Where-Object { $_.type -eq 'file' -and $_.path -like '*.gguf' })
    foreach ($pattern in $item.Want) {
        $hits = @($ggufList | Where-Object { $_.path -match $pattern })
        if ($hits.Count -eq 0) {
            Write-Warning "Nenhum arquivo casou com '$pattern' em $($item.Repo)"
            $problems++
            continue
        }
        $remote   = $hits[0]
        $fileName = Split-Path $remote.path -Leaf
        $fileUrl  = "https://huggingface.co/$($item.Repo)/resolve/main/$($remote.path)?download=true"
        $ok = Save-Download -Url $fileUrl -OutFile (Join-Path $destDir $fileName) -Size $remote.size -Label $fileName
        if (-not $ok) { $problems++ }
    }
}

# ---------- 3. Conferencia ----------
Say 'GPUs que o llama.cpp enxerga (deve aparecer CUDA0: NVIDIA GeForce RTX 4070 Laptop GPU):'
$ErrorActionPreference = 'Continue'
try { & $ServerExe --list-devices } catch { Write-Warning "Nao consegui executar llama-server.exe: $($_.Exception.Message)" }

if ($problems -gt 0) {
    Say "Terminou com $problems pendencia(s). Rode 0-INSTALAR.bat de novo: ele retoma de onde parou." 'Yellow'
} else {
    Say 'Tudo pronto. Use os atalhos 1- a 4- de "1 - Texto (LLMs)" para iniciar um modelo (um por vez).' 'Green'
    Write-Host 'O chat abre sozinho no navegador em http://127.0.0.1:8080 quando o modelo terminar de carregar.'
}
