# mlx-build
**Unofficial** precompiled binaries of the Apple MLX library, [ml-explore/mlx](https://github.com/ml-explore/mlx). 

> [!CAUTION]
> This repo hosts **unofficial** precompiled binaries of [ml-explore/mlx](https://github.com/ml-explore/mlx).
> 
> This repo is **not endorsed by or has any association** with the original source code. The precompiled binaries are produced on the GitHub platform and is mainly used by the Elixir library [emlx](https://github.com/samrat/emlx).
> 
> **Please evaluate and use at your own risk.**

## Artifacts

Precompiled binaries are published on every release; the variants and file names differ by platform.

### macOS

Each release from `v0.31.0` onward ships **8 macOS variants** — the cross product of three axes:

| axis | values | effect |
|------|--------|--------|
| build type | release / `debug` | `debug` = `Debug` CMake build + `-D MLX_METAL_DEBUG=ON` |
| Metal kernels | AOT / `jit` | `jit` = `-D MLX_METAL_JIT=ON` (kernels compiled at runtime) |
| deployment target | `14.0` / `26.2` | minimum macOS the binary runs on (see below) |

All are `arm64-apple-darwin`, built on `macos-26` (Xcode 26).

```
mlx-arm64-apple-darwin-<deployment-target>[-debug][-jit].tar.gz
```

e.g. `mlx-arm64-apple-darwin-14.0.tar.gz`, `mlx-arm64-apple-darwin-26.2-debug-jit.tar.gz`.

> **Naming changed at `v0.31.0`.** The deployment-target segment is new. Releases from `v0.31.0` onward use the 8-variant scheme above; earlier releases (`v0.30.x` and below) use the old `mlx-arm64-apple-darwin[-debug][-jit].tar.gz` names (4 variants, no deployment target).

The filename is keyed on the **deployment target**, not `MLX_METAL_VERSION`, because the deployment target is the **decisive factor**: it is the one knob we set, and everything else derives from it. MLX probes the Metal language version with `-mmacosx-version-min=<deployment-target>`, so the deployment target alone determines the Metal version, the minimum OS, and whether the NAX kernels are compiled in:

| deployment target | `MLX_METAL_VERSION` | runs on | ahead-of-time NAX kernels |
|-------------------|---------------------|---------|----------------------------|
| `14.0` | `310` (Metal 3.1) | macOS 14+ | ❌ gated out — portable |
| `26.2` | `400` (Metal 4.0) | macOS 26.2+ | ✅ baked into `mlx.metallib` |

NAX kernels are MLX's GEMM/attention paths built on Apple's `MetalPerformancePrimitives` (Metal 4 tensor ops); they need the macOS 26 SDK and only run on macOS 26.2+. MLX gates them behind `MLX_METAL_VERSION >= 400 AND MACOS_SDK_VERSION >= 26.2 AND CMAKE_OSX_DEPLOYMENT_TARGET >= 26.2` ([`kernels/CMakeLists.txt`](https://github.com/ml-explore/mlx/blob/v0.32.0/mlx/backend/metal/kernels/CMakeLists.txt#L158)). On our `macos-26` build host the SDK is always ≥ 26.2, so the deployment target alone flips NAX on or off.

Use the `14.0` builds for broad compatibility; use `26.2` only if you target macOS 26.2+ and want NAX acceleration compiled in. (The `jit` variants additionally JIT-compile NAX at runtime on 26.2+ hardware, regardless of deployment target.)

### Linux

Two C libraries are built, each in release and `debug`:

```
mlx-<arch>-linux-<gnu|musl>[-debug].tar.gz
```

| libc | arches |
|------|--------|
| **glibc** (`-linux-gnu`) | `x86_64`, `aarch64`, `riscv64`, `armv7l` (`armv7l-linux-gnueabihf`), `ppc64le`, `s390x` |
| **musl** (`-linux-musl`) | `x86_64`, `aarch64`, `riscv64`, `armv7l` (`armv7l-linux-musleabihf`) |

e.g. `mlx-x86_64-linux-gnu.tar.gz`, `mlx-aarch64-linux-musl-debug.tar.gz`, `mlx-s390x-linux-gnu.tar.gz`.

All are CPU builds with the full feature set — BLAS/LAPACK via OpenBLAS, GGUF + safetensors, distributed (ring + MPI). glibc `x86_64`/`aarch64` target a ~2.14 floor (Ubuntu 20.04 + gcc-13); the rest build on Ubuntu 24.04 / Alpine. Each binary dynamically links OpenBLAS + libgfortran + libstdc++, so the target must provide them (`apt install libopenblas0 libgfortran5` or `apk add openblas libgfortran libstdc++`).

### Linux (CUDA)

For NVIDIA GPUs there is a separate CUDA variant (glibc, `x86_64` + `aarch64`):

```
mlx-<arch>-linux-gnu-cuda13-cudnn9[-debug].tar.gz
```

Built against **CUDA 13.0 + cuDNN 9** (`MLX_BUILD_CUDA=ON` — adds cuBLAS/cuFFT/cuDNN/NCCL) for compute capabilities 8.0 / 9.0 / 10.0 / 12.0 (+ PTX for forward compatibility). It needs an NVIDIA GPU with the CUDA 13 runtime + cuDNN 9 + driver at runtime, so it is a separate, non-portable variant — not a drop-in replacement for the CPU builds.

## Usage

Install a release in a workflow with the bundled action — it auto-detects the target triplet:

```yaml
- uses: cocoa-xu/mlx-build@main
  with:
    mlx-version: "~> 0.32"        # exact ("0.32.0") or requirement (">= 0.31.0")
    # debug: true                # debug variant
    # deployment-target: "26.2"  # macOS: NAX-enabled build (default 14.0)
    # jit: true                  # macOS: JIT Metal variant
    # cuda: "13"                 # Linux: NVIDIA CUDA 13 + cuDNN 9 variant
```

It exports `MLX_DIR` / `CMAKE_PREFIX_PATH` (for `find_package(MLX)`) and `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH`, and sets `install-dir`, `lib-dir`, `include-dir`, and the resolved `mlx-version` / `triplet` as step outputs.
