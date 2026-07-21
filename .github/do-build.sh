#!/bin/sh

set -eux

MLX_VERSION=$1
MLX_DEBUG=$2
ARCH=$3
TRIPLET=$4
ROOTDIR=$5
CMAKE_VERSION=${6:-"3.31.5"}
MLX_SRC_FILENAME="mlx-v${MLX_VERSION}.tar.gz"
MLX_SRC_DIR="${ROOTDIR}/mlx-${MLX_VERSION}"
export DESTDIR="${ROOTDIR}/artifact/mlx"
mkdir -p "${DESTDIR}"

export DEBIAN_FRONTEND=noninteractive

export SUDO="$(which sudo)"
${SUDO} apt-get update
# gcc-13: MLX 0.32's CPU JIT uses __builtin_cpu_supports("f16c"), which gcc-10
# rejects on x86_64. On Ubuntu 20.04 gcc-13 comes from the toolchain PPA (so we
# keep the low glibc floor); on 24.04 it's already in the default repos.
. /etc/os-release
if [ "${VERSION_ID}" = "20.04" ]; then
  ${SUDO} apt-get install -y software-properties-common
  ${SUDO} add-apt-repository -y ppa:ubuntu-toolchain-r/test
  ${SUDO} apt-get update
fi
${SUDO} apt-get install -y gcc-13 g++-13 gfortran-13 curl make cmake automake autoconf pkg-config git patchelf libopenblas-dev liblapack-dev liblapacke-dev
export CC=gcc-13 CXX=g++-13 FC=gfortran-13

cd "${ROOTDIR}"

case "${ARCH}" in
  x86_64 | aarch64)
    CMAKE_FILENAME="cmake-${CMAKE_VERSION}-linux-${ARCH}"
    curl -fSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/${CMAKE_FILENAME}.tar.gz" -o "${CMAKE_FILENAME}.tar.gz"
    tar -xf "${CMAKE_FILENAME}.tar.gz"
    export PATH="${ROOTDIR}/${CMAKE_FILENAME}/bin:${PATH}"
    ;;
  *)
    ;;
esac

if [ ! -f "${MLX_SRC_FILENAME}" ]; then
  curl -fSL "https://github.com/ml-explore/mlx/archive/refs/tags/v${MLX_VERSION}.tar.gz" -o "${MLX_SRC_FILENAME}"
fi

tar -xf "${MLX_SRC_FILENAME}"
cd "${MLX_SRC_DIR}"

if [ "${MLX_DEBUG}" = "ON" ]; then
  export CMAKE_BUILD_TYPE=Debug
  export ARCHIVE_FILENAME="mlx-${TRIPLET}-debug.tar.gz"
else
  export CMAKE_BUILD_TYPE=Release
  export ARCHIVE_FILENAME="mlx-${TRIPLET}.tar.gz"
fi

cmake -B build \
  -D CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
  -D MLX_BUILD_TESTS=OFF \
  -D MLX_BUILD_EXAMPLES=OFF \
  -D MLX_BUILD_BENCHMARKS=OFF \
  -D MLX_BUILD_PYTHON_BINDINGS=OFF \
  -D MLX_BUILD_CPU=ON \
  -D MLX_BUILD_GGUF=ON \
  -D MLX_BUILD_SAFETENSORS=ON \
  -D BUILD_SHARED_LIBS=ON \
  .
cmake --build build --config "${CMAKE_BUILD_TYPE}" -j"$(nproc)"
cd build
make DESTDIR="${DESTDIR}" install
cd "${DESTDIR}/usr/local/lib"
patchelf --force-rpath --set-rpath '$ORIGIN' libmlx.so
ls -lah "${DESTDIR}/usr/local/lib"
tar -C "${DESTDIR}/usr/local" -czf "${ROOTDIR}/artifact/${ARCHIVE_FILENAME}" .

cd "${ROOTDIR}/artifact"
shasum -a 256 "${ARCHIVE_FILENAME}" | tee "${ARCHIVE_FILENAME}.sha256"
