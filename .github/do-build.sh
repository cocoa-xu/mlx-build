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
${SUDO} apt-get install -y gcc g++ curl make cmake automake autoconf pkg-config git patchelf

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
  -D MLX_BUILD_BLAS_FROM_SOURCE=ON \
  -D BUILD_SHARED_LIBS=ON \
  .
cmake --build build --config "${CMAKE_BUILD_TYPE}" -j"$(nproc)"
cd build
make DESTDIR="${DESTDIR}" install
cd _deps/openblas-build
make DESTDIR="${DESTDIR}" install
cd "${DESTDIR}/usr/local/lib"
patchelf --force-rpath --set-rpath '$ORIGIN' libmlx.so
ls -lah "${DESTDIR}/usr/local/lib"
tar -C "${DESTDIR}/usr/local" -czf "${ROOTDIR}/artifact/${ARCHIVE_FILENAME}" .

cd "${ROOTDIR}/artifact"
shasum -a 256 "${ARCHIVE_FILENAME}" | tee "${ARCHIVE_FILENAME}.sha256"
