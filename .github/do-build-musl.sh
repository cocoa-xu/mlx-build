#!/bin/sh

set -eux

MLX_VERSION=$1
MLX_DEBUG=$2
ARCH=$3
TRIPLET=$4
ROOTDIR=$5
JOBS=${6:-$(nproc)}
MLX_SRC_FILENAME="mlx-v${MLX_VERSION}.tar.gz"
MLX_SRC_DIR="${ROOTDIR}/mlx-${MLX_VERSION}"
export DESTDIR="${ROOTDIR}/artifact/mlx"
mkdir -p "${DESTDIR}"

# MLX 0.32 links OpenBLAS (BLA_VENDOR=OpenBLAS) and needs the CBLAS/LAPACKE
# headers; openblas-dev + lapack-dev provide both on Alpine.
apk update
apk add --no-cache \
  build-base cmake curl git tar linux-headers patchelf bash \
  openblas-dev lapack-dev

cd "${ROOTDIR}"

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
  -D BUILD_SHARED_LIBS=ON \
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
