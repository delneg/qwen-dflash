# Qwen3.8-27B on a 12 GB NVIDIA card (RTX 3060 class), one command:
#
#   irm https://raw.githubusercontent.com/delneg/qwen-dflash/main/windows/setup.ps1 | iex
#
# Uses the OFFICIAL llama.cpp Windows CUDA release (no fork): DFlash 2 is not
# merged upstream yet and its draft loading has an open bug report on
# Windows/MSVC, so this path runs plain decode with Unsloth's UD-IQ2_XXS
# quant (7.3 GB weights, fits 12 GB VRAM with room for context).
$ErrorActionPreference = "Stop"

$Dir = if ($env:QWEN_DFLASH_DIR) { $env:QWEN_DFLASH_DIR } else { "$HOME\qwen-dflash" }
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Push-Location $Dir

Write-Host "==> Finding latest official llama.cpp Windows CUDA build"
$rel = Invoke-RestMethod "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"
$bin = $rel.assets | Where-Object { $_.name -match "bin-win-cuda.*x64\.zip$" } |
    Sort-Object name -Descending | Select-Object -First 1
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

@'
@echo off
cd /d "%~dp0"
rem First launch downloads ~7.5 GB of model weights to
rem %USERPROFILE%\.cache\huggingface\hub\ and reuses them afterwards.
rem UD-IQ2_XXS fits a 12 GB card; on 16 GB+ try UD-Q2_K_XL or larger.
llama-server.exe ^
  -hf unsloth/Qwen3.8-27B-GGUF:UD-IQ2_XXS ^
  -c 8192 -ngl 99 --host 127.0.0.1 --port 8080 %*
'@ | Set-Content -Path start.bat -Encoding ascii

Write-Host ""
Write-Host "Done. Start the server with:"
Write-Host ""
Write-Host "    $Dir\start.bat"
Write-Host ""
Write-Host "then open http://127.0.0.1:8080 for the chat UI"
Write-Host "(OpenAI-compatible API on http://127.0.0.1:8080/v1)."
Write-Host "Ctrl+C stops it. First launch downloads ~7.5 GB of weights."

Pop-Location
