# Qwen3.8-27B on an NVIDIA card, one command:
#
#   irm https://raw.githubusercontent.com/delneg/qwen-dflash/master/windows/setup.ps1 | iex
#
# Uses the OFFICIAL llama.cpp Windows CUDA release (no fork): DFlash 2 is not
# merged upstream yet and its draft loading has an open bug report on
# Windows/MSVC, so this path runs plain decode. The quant is picked to fit
# your VRAM (detected via nvidia-smi); see the table in the README.
# Not sure what your hardware can run in general? Try the calculator:
#   https://dubir.net/tools/local-llm-hardware-calculator
$ErrorActionPreference = "Stop"

$Dir = if ($env:QWEN_DFLASH_DIR) { $env:QWEN_DFLASH_DIR } else { "$HOME\qwen-dflash" }
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Push-Location $Dir

# ---- pick a quant that fits this GPU ---------------------------------------
# Budget: weights need ~3 GB of headroom for KV cache (8k ctx), CUDA buffers
# and whatever the Windows desktop already holds on the same card.
$vramMiB = 0
try {
    $vramMiB = [int]((nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits |
        Select-Object -First 1).Trim())
} catch {}

if ($vramMiB -ge 23000)     { $quant = "UD-Q4_K_XL"; $gb = "17.6" }   # 24 GB+ (3090/4090)
elseif ($vramMiB -ge 15500) { $quant = "UD-Q3_K_XL"; $gb = "13.2" }   # 16 GB (4060Ti-16/4080)
elseif ($vramMiB -ge 11500) { $quant = "UD-IQ2_XXS"; $gb = "7.3"  }   # 12 GB (3060/4070)
elseif ($vramMiB -ge 7500)  { $quant = "UD-IQ1_S";   $gb = "6.2"  }   # 8 GB, tight + rough quality
elseif ($vramMiB -gt 0) {
    throw "Only $([math]::Round($vramMiB/1024,1)) GB VRAM detected; Qwen3.8-27B needs 8 GB+. See https://dubir.net/tools/local-llm-hardware-calculator for what your hardware can run."
} else {
    Write-Warning "nvidia-smi not found; assuming a 12 GB card. Set the quant manually in start.bat if that is wrong."
    $quant = "UD-IQ2_XXS"; $gb = "7.3"
}
if ($vramMiB -gt 0) {
    Write-Host ("==> {0:N1} GB VRAM detected -> {1} ({2} GB weights)" -f ($vramMiB/1024), $quant, $gb)
}
if ($quant -eq "UD-IQ1_S") {
    Write-Warning "1-bit quant: it runs, but output quality is noticeably degraded. Fine for a demo, not for real work."
}

# ---- download the official llama.cpp CUDA build ----------------------------
Write-Host "==> Finding latest official llama.cpp Windows CUDA build"
# "releases/latest" points at a versioned meta-release with no binaries;
# the prebuilt binaries live in the frequent b-number tag releases.
$rels = Invoke-RestMethod "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=10"
# "^llama-" so the cudart-llama-bin-win-cuda-*.zip runtime bundles don't match.
$rel = $rels | Where-Object { ($_.assets | Where-Object { $_.name -match "^llama-.*bin-win-cuda.*x64\.zip$" }).Count -gt 0 } |
    Select-Object -First 1
if (-not $rel) { throw "No release with win-cuda x64 assets in the last 10; check https://github.com/ggml-org/llama.cpp/releases" }
# Ascending sort picks the lowest CUDA version (12.4 over 13.x): it runs on
# far older NVIDIA drivers, and the speed difference is nil for this use.
$bin = $rel.assets | Where-Object { $_.name -match "^llama-.*bin-win-cuda.*x64\.zip$" } |
    Sort-Object name | Select-Object -First 1
if (-not $bin) { throw "No win-cuda x64 asset in latest release; check https://github.com/ggml-org/llama.cpp/releases" }
# cudart zip must match the binary's CUDA version (releases can carry several).
$cudaVer = if ($bin.name -match "cu(da)?-?[\d.]+\d") { $Matches[0] } else { "" }
$cudart = $rel.assets | Where-Object { $_.name -match "^cudart-" -and $_.name -like "*$cudaVer*" } |
    Select-Object -First 1

Write-Host "==> Downloading $($bin.name)"
Invoke-WebRequest $bin.browser_download_url -OutFile llama.zip
Expand-Archive llama.zip -DestinationPath . -Force
Remove-Item llama.zip

if ($cudart) {
    Write-Host "==> Downloading CUDA runtime ($($cudart.name))"
    Invoke-WebRequest $cudart.browser_download_url -OutFile cudart.zip
    Expand-Archive cudart.zip -DestinationPath . -Force
    Remove-Item cudart.zip
}

# ---- write the launcher ----------------------------------------------------
@"
@echo off
cd /d "%~dp0"
rem Quant auto-picked for your VRAM at install time; edit freely.
rem Other sizes: https://huggingface.co/unsloth/Qwen3.8-27B-GGUF
rem What fits what: https://dubir.net/tools/local-llm-hardware-calculator
rem First launch downloads ~$gb GB of weights to
rem %USERPROFILE%\.cache\huggingface\hub\ and reuses them afterwards.
llama-server.exe ^
  -hf unsloth/Qwen3.8-27B-GGUF:$quant ^
  -c 8192 -ngl 99 --host 127.0.0.1 --port 8080 %*
"@ | Set-Content -Path start.bat -Encoding ascii

Write-Host ""
Write-Host "Done. Start the server with:"
Write-Host ""
Write-Host "    $Dir\start.bat"
Write-Host ""
Write-Host "then open http://127.0.0.1:8080 for the chat UI"
Write-Host "(OpenAI-compatible API on http://127.0.0.1:8080/v1)."
Write-Host "Ctrl+C stops it. First launch downloads ~$gb GB of weights."

Pop-Location
