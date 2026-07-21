#!/bin/sh
# MLX CUDA build. Runs inside an nvidia/cuda:*-devel container (the CI job's
# container). No GPU needed to compile: the libcuda driver stub is symlinked to
# a standard path; the real driver resolves at runtime on the user's machine.
set -eux

MLX_VERSION=$1
MLX_DEBUG=$2
ARCH=$3                 # e.g. x86_64
CUDA_ID=$4              # e.g. 13
CUDNN_ID=$5             # e.g. 9
CUDNN_URL=$6            # cuDNN redist tarball (.tar.xz)
ROOTDIR=$7
CUDA_ARCHS=${8:-"80-real;90-real;100-real;120-real;120-virtual"}
JOBS=${JOBS:-$(nproc)}
CMAKE_VERSION=3.31.5

TRIPLET="${ARCH}-linux-gnu"
SUFFIX="cuda${CUDA_ID}-cudnn${CUDNN_ID}"
export DESTDIR="${ROOTDIR}/artifact/mlx"
mkdir -p "${DESTDIR}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y build-essential curl git tar xz-utils patchelf ca-certificates \
  libopenblas-dev liblapack-dev liblapacke-dev

cd "${ROOTDIR}"
CMF="cmake-${CMAKE_VERSION}-linux-${ARCH}"
if [ ! -d "${CMF}" ]; then
  curl -fSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/${CMF}.tar.gz" -o "${CMF}.tar.gz"
  tar -xf "${CMF}.tar.gz"
fi
export PATH="${ROOTDIR}/${CMF}/bin:${PATH}"

# cuDNN redist -> into the CUDA toolkit
curl -fSL --retry 3 --retry-delay 5 "${CUDNN_URL}" -o cudnn.tar.xz
rm -rf cudnn && mkdir -p cudnn
tar -xf cudnn.tar.xz -C cudnn --strip-components=1
rm -f cudnn.tar.xz
cp -a cudnn/include/* /usr/local/cuda/include/
[ -d cudnn/lib ] && cp -a cudnn/lib/* /usr/local/cuda/lib64/ || true
[ -d cudnn/lib64 ] && cp -a cudnn/lib64/* /usr/local/cuda/lib64/ || true
rm -rf cudnn

# libcuda driver stub -> standard path (build-time link without a GPU)
stub="$(find /usr/local/cuda* -name libcuda.so -path '*stubs*' 2>/dev/null | head -1)"
ln -sf "${stub}" "/usr/lib/${ARCH}-linux-gnu/libcuda.so"
ln -sf "${stub}" "/usr/lib/${ARCH}-linux-gnu/libcuda.so.1"
ldconfig
nvcc --version | grep release

if [ ! -f "mlx-v${MLX_VERSION}.tar.gz" ]; then
  curl -fSL "https://github.com/ml-explore/mlx/archive/refs/tags/v${MLX_VERSION}.tar.gz" -o "mlx-v${MLX_VERSION}.tar.gz"
fi
rm -rf "mlx-${MLX_VERSION}"; tar -xf "mlx-v${MLX_VERSION}.tar.gz"; cd "mlx-${MLX_VERSION}"

if [ "${MLX_DEBUG}" = "ON" ]; then
  export CMAKE_BUILD_TYPE=Debug
  export ARCHIVE_FILENAME="mlx-${TRIPLET}-${SUFFIX}-debug.tar.gz"
else
  export CMAKE_BUILD_TYPE=Release
  export ARCHIVE_FILENAME="mlx-${TRIPLET}-${SUFFIX}.tar.gz"
fi

cmake -B build \
  -D CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
  -D MLX_BUILD_CUDA=ON \
  -D MLX_BUILD_CPU=ON \
  -D MLX_BUILD_TESTS=OFF \
  -D MLX_BUILD_EXAMPLES=OFF \
  -D MLX_BUILD_BENCHMARKS=OFF \
  -D MLX_BUILD_PYTHON_BINDINGS=OFF \
  -D MLX_BUILD_GGUF=ON \
  -D MLX_BUILD_SAFETENSORS=ON \
  -D BUILD_SHARED_LIBS=ON \
  -D MLX_CUDA_ARCHITECTURES="${CUDA_ARCHS}" \
  .
cmake --build build --config "${CMAKE_BUILD_TYPE}" -j"${JOBS}"
cd build
make DESTDIR="${DESTDIR}" install
cd "${DESTDIR}/usr/local/lib"
patchelf --force-rpath --set-rpath '$ORIGIN' libmlx.so
ls -lah "${DESTDIR}/usr/local/lib"
tar -C "${DESTDIR}/usr/local" -czf "${ROOTDIR}/artifact/${ARCHIVE_FILENAME}" .

cd "${ROOTDIR}/artifact"
sha256sum "${ARCHIVE_FILENAME}" | tee "${ARCHIVE_FILENAME}.sha256"
