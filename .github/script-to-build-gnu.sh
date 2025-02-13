#!/bin/sh

set -eux

MLX_VERSION=$1
MLX_DEBUG=$2
ARCH=$3
IMAGE_NAME=$4
DOCKER_PLATFORM=$5

TARGET="${ARCH}-linux-gnu"
if [ "${ARCH}" = "armv7l" ]; then
  TARGET="armv7l-linux-gnueabihf"
fi

if [ ! -z "${DOCKER_PLATFORM}" ]; then
  sudo docker run --privileged --network=host --rm -v $(pwd):/work --platform="${DOCKER_PLATFORM}" "${IMAGE_NAME}" \
    sh -c "chmod a+x /work/do-build.sh && /work/do-build.sh ${MLX_VERSION} ${MLX_DEBUG} ${ARCH} ${TARGET}"
else
  sudo docker run --privileged --network=host --rm -v $(pwd):/work "${IMAGE_NAME}" \
    sh -c "chmod a+x /work/do-build.sh && /work/do-build.sh ${MLX_VERSION} ${MLX_DEBUG} ${ARCH} ${TARGET}"
fi
