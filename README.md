# mlx-build
**Unofficial** precompiled binaries of the Apple MLX library, [ml-explore/mlx](https://github.com/ml-explore/mlx). 

> [!CAUTION]
> This repo hosts **unofficial** precompiled binaries of [ml-explore/mlx](https://github.com/ml-explore/mlx).
> 
> This repo is **not endorsed by or has any association** with the original source code. The precompiled binaries are produced on the GitHub platform and is mainly used by the Elixir library [emlx](https://github.com/samrat/emlx).
> 
> **Please evaluate and use at your own risk.**

## macOS artifacts

Every upstream MLX release from `v0.31.0` onward is built into **8 macOS variants** — the cross product of three axes:

| axis | values | effect |
|------|--------|--------|
| build type | release / `debug` | `debug` = `Debug` CMake build + `-D MLX_METAL_DEBUG=ON` |
| Metal kernels | AOT / `jit` | `jit` = `-D MLX_METAL_JIT=ON` (kernels compiled at runtime) |
| deployment target | `14.0` / `26.2` | minimum macOS the binary runs on (see below) |

All are `arm64-apple-darwin`, built on `macos-26` (Xcode 26).

### Naming

```
mlx-arm64-apple-darwin-<deployment-target>[-debug][-jit].tar.gz
```

e.g. `mlx-arm64-apple-darwin-14.0.tar.gz`, `mlx-arm64-apple-darwin-26.2-debug-jit.tar.gz`.

The filename is keyed on the **deployment target**, not `MLX_METAL_VERSION`, because the deployment target is the **decisive factor**: it is the one knob we set, and everything else derives from it. MLX probes the Metal language version with `-mmacosx-version-min=<deployment-target>`, so the deployment target alone determines the Metal version, the minimum OS, and whether the NAX kernels are compiled in:

| deployment target | `MLX_METAL_VERSION` | runs on | ahead-of-time NAX kernels |
|-------------------|---------------------|---------|----------------------------|
| `14.0` | `310` (Metal 3.1) | macOS 14+ | ❌ gated out — portable |
| `26.2` | `400` (Metal 4.0) | macOS 26.2+ | ✅ baked into `mlx.metallib` |

NAX kernels are MLX's GEMM/attention paths built on Apple's `MetalPerformancePrimitives` (Metal 4 tensor ops); they need the macOS 26 SDK and only run on macOS 26.2+. MLX gates them behind `MLX_METAL_VERSION >= 400 AND MACOS_SDK_VERSION >= 26.2 AND CMAKE_OSX_DEPLOYMENT_TARGET >= 26.2` ([`kernels/CMakeLists.txt`](https://github.com/ml-explore/mlx/blob/v0.32.0/mlx/backend/metal/kernels/CMakeLists.txt#L158)). On our `macos-26` build host the SDK is always ≥ 26.2, so the deployment target alone flips NAX on or off.

Use the `14.0` builds for broad compatibility; use `26.2` only if you target macOS 26.2+ and want NAX acceleration compiled in. (The `jit` variants additionally JIT-compile NAX at runtime on 26.2+ hardware, regardless of deployment target.)
