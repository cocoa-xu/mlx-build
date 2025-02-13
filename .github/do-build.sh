#!/bin/sh

set -eux

MLX_VERSION=$1
MLX_DEBUG=$2
ARCH=$3
TRIPLET=$4
MLX_SRC_FILENAME="mlx-v${MLX_VERSION}.tar.gz"
ROOTDIR="/work"
MLX_SRC_DIR="${ROOTDIR}/mlx-${MLX_VERSION}"
DESTDIR="${ROOTDIR}/artifact/mlx"
mkdir -p "${DESTDIR}"

case $TRIPLET in
  riscv64-linux-gnu )
    apt-get update && \
    apt-get install -y gcc g++ curl make cmake automake autoconf pkg-config liblapacke-dev libopenblas64-openmp-dev 
    ;;
  armv7l-linux-gnueabihf )
    apt-get update && \
    apt-get install -y gcc g++ curl make cmake automake autoconf pkg-config liblapacke-dev libopenblas64-openmp-dev
    ;;
  *-linux-gnu )
    yum install -y curl make cmake automake autoconf pkg-config lapack-devel openblas-devel
    ;;
  * )
    echo "Unknown triplet: ${TRIPLET}"
    exit 1
    ;;
esac

cd "${ROOTDIR}"
if [ ! -f "${MLX_SRC_FILENAME}" ]; then
  curl -fSL "https://github.com/ml-explore/mlx/archive/refs/tags/v${MLX_VERSION}.tar.gz" -o "${MLX_SRC_FILENAME}"
fi

tar -xf "${MLX_SRC_FILENAME}"
cd "${MLX_SRC_DIR}"

if [ "${MLX_DEBUG}" = "ON" ]; then
  export CMAKE_BUILD_TYPE=Debug
else
  export CMAKE_BUILD_TYPE=Release
fi

cmake -B build \
  -D CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
  -D MLX_BUILD_TESTS=OFF \
  -D MLX_BUILD_EXAMPLES=OFF \
  -D MLX_BUILD_BENCHMARKS=OFF \
  -D MLX_BUILD_PYTHON_BINDINGS=OFF \
  -D MLX_BUILD_BLAS_FROM_SOURCE="ON" \
  -D BUILD_SHARED_LIBS=ON \
  .
cmake --build build --config "${CMAKE_BUILD_TYPE}" -j"$(nproc)"
cmake --install build --config "${CMAKE_BUILD_TYPE}"

if [ "${MLX_DEBUG}" = "ON" ]; then
  export ARCHIVE_FILENAME="mlx-${{ matrix.job.target }}.tar.gz"
else
  export ARCHIVE_FILENAME="mlx-${{ matrix.job.target }}-debug.tar.gz"
fi
tar -C "${DESTDIR}/usr/local" -czf "${ROOTDIR}/artifact/${ARCHIVE_FILENAME}" .

cd "${ROOTDIR}/artifact"
shasum -a 256 "${ARCHIVE_FILENAME}" | tee "${ARCHIVE_FILENAME}.sha256"
