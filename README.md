# qwen-dflash

Run **Qwen3.8-27B** locally with one command.

Two paths, pick your hardware:

| | Mac (Apple Silicon) | Windows (NVIDIA 12 GB+) |
|---|---|---|
| Engine | llama.cpp fork with **DFlash 2** speculative decoding | official llama.cpp CUDA release |
| Quant | Q4_K_M (19 GB) + 1.1 GB draft | Unsloth UD-IQ2_XXS (7.3 GB) |
| Needs | 36 GB+ unified RAM, macOS 14+ | 12 GB VRAM (RTX 3060 class) |
| Speed | 16-18 tok/s on M1 Max (1.5x plain decode) | ~20-30 tok/s on RTX 3060 |

## Mac

```bash
curl -fsSL https://raw.githubusercontent.com/delneg/qwen-dflash/main/setup.sh | bash
~/qwen-dflash/start.sh
```

Open http://127.0.0.1:8080 and chat. Ctrl+C stops the server.
First launch downloads ~20 GB of model weights (cached in
`~/.cache/huggingface/hub/`, reused afterwards).

Prefer to read before piping to bash? Same script, two steps:

```bash
curl -fsSLO https://raw.githubusercontent.com/delneg/qwen-dflash/main/setup.sh
less setup.sh && bash setup.sh
```

### What is DFlash 2?

A block-diffusion draft model from [Inco AI](https://inco.ai/blog/dflash2/):
a 1.1 GB companion model proposes blocks of tokens, the 27B target verifies
them in one pass. Output is byte-identical to plain decoding (it is lossless);
it is only faster. Measured on an M1 Max: 11.8 tok/s plain, 16-18 tok/s with
DFlash at `--spec-draft-n-max 3` (84% draft acceptance).

DFlash support is [not merged into llama.cpp yet](https://github.com/ggml-org/llama.cpp/pull/27342).
This repo ships a prebuilt binary from the
[z-lab fork](https://github.com/z-lab/llama.cpp-fork) (PR #1 head, which adds
vision fixes on top of the dflash2 branch), pinned by SHA in
[the build workflow](.github/workflows/build.yml). When the upstream PR merges,
plain `brew install llama.cpp` will do and this repo becomes a convenience
wrapper.

No macOS update needed: this runs fine on macOS 14 (Sonoma) and 15 (Sequoia). That matters
because the MLX route (oMLX) requires Metal 4, which means macOS 26.

## Windows

```powershell
irm https://raw.githubusercontent.com/delneg/qwen-dflash/main/windows/setup.ps1 | iex
~\qwen-dflash\start.bat
```

Same UI at http://127.0.0.1:8080. First launch downloads ~7.5 GB of weights.

Why no DFlash here: it is unmerged upstream, and draft loading has an
[open bug report on Windows/MSVC](https://github.com/ggml-org/llama.cpp/pull/27342)
(`invalid vector subscript`). Plain decode with Unsloth's 2-bit dynamic quant
is what reliably fits and runs on a 12 GB card today. When both fix themselves
upstream, DFlash lands here too.

Note on quality: UD-IQ2_XXS is a heavy quant. Good enough to chat and demo;
for serious work use a bigger quant on a bigger card (or the Mac path).

## Tuning

- `--spec-draft-n-max 3` (Mac) was measured optimal on M1 Max; the sweep is
  monotonic on both sides there. Newer chips have more compute per byte of
  bandwidth, so try 5-7.
- Pass extra llama-server flags straight through: `start.sh -c 32768`.
- RAM/VRAM guide: Mac path needs ~22 GB resident at 8k context (+~2 GB per
  extra 32k). Windows path fits 12 GB VRAM at 8k context.
- Speculative decoding does not change outputs. If you see different text with
  and without it at temperature 0, that is a bug; file an issue.

## Verify a downloaded binary

Each release ships a `.sha256` next to the tarball:

```bash
shasum -a 256 -c llama-server-macos-arm64.tar.gz.sha256
```

## License

MIT for the scripts in this repo. The prebuilt binary is built from
[llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT) plus the z-lab
DFlash patches; model weights come under their own licenses from their
Hugging Face pages.
