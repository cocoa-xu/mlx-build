#!/bin/sh
# Download and set up a precompiled MLX release from cocoa-xu/mlx-build.
# Driven by env vars (see action.yml). Prints GitHub Action outputs/env when
# GITHUB_OUTPUT / GITHUB_ENV are set; otherwise just installs.
set -eu

REPO="${MLX_REPOSITORY:-cocoa-xu/mlx-build}"
INSTALL_DIR="${MLX_INSTALL_DIR:-.mlx}"
ADD_TO_PATH="${MLX_ADD_TO_PATH:-true}"
DOWNLOAD_ONLY="${MLX_DOWNLOAD_ONLY:-false}"
DEBUG="${MLX_DEBUG:-false}"
JIT="${MLX_JIT:-false}"
DEPLOYMENT_TARGET="${MLX_DEPLOYMENT_TARGET:-14.0}"
CUDA="${MLX_CUDA:-}"
CUDNN="${MLX_CUDNN:-9}"
TOKEN="${MLX_TOKEN:-}"

log() { echo "[setup-mlx] $*" >&2; }
die() { echo "[setup-mlx] error: $*" >&2; exit 1; }

api() {
  if [ -n "${TOKEN}" ]; then
    curl -fsSL -H "Authorization: Bearer ${TOKEN}" "$@"
  else
    curl -fsSL "$@"
  fi
}

detect_triplet() {
  os="$(uname -s)"
  arch="$(uname -m)"
  case "${os}" in
    Linux)
      case "${arch}" in
        x86_64 | amd64) a=x86_64 ;;
        aarch64 | arm64) a=aarch64 ;;
        armv7l | armv7*) a=armv7l ;;
        riscv64) a=riscv64 ;;
        ppc64le) a=ppc64le ;;
        s390x) a=s390x ;;
        *) a="${arch}" ;;
      esac
      if [ -f /etc/alpine-release ] || ldd --version 2>&1 | grep -qi musl; then
        libc=musl
      else
        libc=gnu
      fi
      if [ "${a}" = armv7l ]; then
        echo "armv7l-linux-${libc}eabihf"
      else
        echo "${a}-linux-${libc}"
      fi
      ;;
    Darwin)
      case "${arch}" in
        arm64) echo "arm64-apple-darwin" ;;
        x86_64) echo "x86_64-apple-darwin" ;;
        *) die "unsupported macOS arch ${arch}" ;;
      esac
      ;;
    *) die "unsupported OS ${os}" ;;
  esac
}

# mlx-<triplet>[-<deployment-target> (macOS)][-debug][-jit (macOS)]
archive_name() {
  triplet="$1"
  name="mlx-${triplet}"
  case "${triplet}" in
    *-apple-darwin) name="${name}-${DEPLOYMENT_TARGET}" ;;
  esac
  [ -n "${CUDA}" ] && name="${name}-cuda${CUDA}-cudnn${CUDNN}"
  [ "${DEBUG}" = true ] && name="${name}-debug"
  case "${triplet}" in
    *-apple-darwin) [ "${JIT}" = true ] && name="${name}-jit" ;;
  esac
  echo "${name}.tar.gz"
}

# All published MLX versions (numeric X.Y.Z tags), highest first.
list_versions() {
  page=1
  while :; do
    body="$(api "https://api.github.com/repos/${REPO}/releases?per_page=100&page=${page}")" || break
    echo "${body}" | grep '"tag_name"' | sed -E 's/.*"v?([0-9]+\.[0-9]+\.[0-9]+)".*/\1/' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true
    echo "${body}" | grep -q '"tag_name"' || break
    page=$((page + 1))
    [ "${page}" -gt 10 ] && break
  done | sort -rV | uniq
}

# ge A B -> true if A >= B (dotted versions)
ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }
gt() { [ "$1" != "$2" ] && ge "$1" "$2"; }

# ~> upper bound: bump the second-to-last component, zero the rest.
tilde_upper() {
  echo "$1" | awk -F. '{ if (NF>=2) { $(NF-1)=$(NF-1)+1; for(i=NF;i<=NF;i++)$i=0 } print }' OFS=.
}

resolve_version() {
  spec="$(echo "$1" | tr -d ' ')"
  op=""; ver="${spec}"
  case "${spec}" in
    "~>"*) op="~>"; ver="${spec#\~>}" ;;
    ">="*) op=">="; ver="${spec#>=}" ;;
    "<="*) op="<="; ver="${spec#<=}" ;;
    ">"*)  op=">";  ver="${spec#>}" ;;
    "<"*)  op="<";  ver="${spec#<}" ;;
    "=="*) op="==";  ver="${spec#==}" ;;
  esac
  ver="${ver#v}"
  if [ -z "${op}" ] || [ "${op}" = "==" ]; then
    echo "${ver}"; return 0
  fi
  [ "${op}" = "~>" ] && upper="$(tilde_upper "${ver}")"
  for c in $(list_versions); do
    case "${op}" in
      "~>") ge "${c}" "${ver}" && ! ge "${c}" "${upper}" && { echo "${c}"; return 0; } ;;
      ">=") ge "${c}" "${ver}" && { echo "${c}"; return 0; } ;;
      ">")  gt "${c}" "${ver}" && { echo "${c}"; return 0; } ;;
      "<=") ! gt "${c}" "${ver}" && { echo "${c}"; return 0; } ;;
      "<")  ! ge "${c}" "${ver}" && { echo "${c}"; return 0; } ;;
    esac
  done
  die "no MLX release satisfies '$1'"
}

[ -n "${MLX_VERSION:-}" ] || die "MLX_VERSION is required"
VERSION="$(resolve_version "${MLX_VERSION}")"
TRIPLET="${MLX_TRIPLET:-$(detect_triplet)}"
ARCHIVE="$(archive_name "${TRIPLET}")"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ARCHIVE}"

log "version=${VERSION} triplet=${TRIPLET}"
log "downloading ${URL}"
tmp="$(mktemp -d)"
api -o "${tmp}/${ARCHIVE}" "${URL}" || die "asset not found: ${ARCHIVE} in v${VERSION}"

if api -o "${tmp}/${ARCHIVE}.sha256" "${URL}.sha256" 2>/dev/null; then
  want="$(awk '{print $1}' "${tmp}/${ARCHIVE}.sha256")"
  if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "${tmp}/${ARCHIVE}" | awk '{print $1}')"
  else
    got="$(shasum -a 256 "${tmp}/${ARCHIVE}" | awk '{print $1}')"
  fi
  [ "${want}" = "${got}" ] || die "sha256 mismatch (want ${want}, got ${got})"
  log "sha256 verified"
fi

emit_out() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1=$2" >> "${GITHUB_OUTPUT}" || true; }
emit_env() { [ -n "${GITHUB_ENV:-}" ] && echo "$1=$2" >> "${GITHUB_ENV}" || true; }

emit_out mlx-version "${VERSION}"
emit_out triplet "${TRIPLET}"

if [ "${DOWNLOAD_ONLY}" = true ]; then
  mkdir -p "$(dirname "${INSTALL_DIR}")"
  cp "${tmp}/${ARCHIVE}" "./${ARCHIVE}"
  emit_out archive-path "${PWD}/${ARCHIVE}"
  log "download-only: ${PWD}/${ARCHIVE}"
  exit 0
fi

mkdir -p "${INSTALL_DIR}"
tar -xzf "${tmp}/${ARCHIVE}" -C "${INSTALL_DIR}"
ABS_DIR="$(cd "${INSTALL_DIR}" && pwd)"

LIB_DIR="${ABS_DIR}/lib"
[ -d "${ABS_DIR}/lib64" ] && LIB_DIR="${ABS_DIR}/lib64"
INC_DIR="${ABS_DIR}/include"

emit_out install-dir "${ABS_DIR}"
emit_out lib-dir "${LIB_DIR}"
emit_out include-dir "${INC_DIR}"
emit_env MLX_DIR "${ABS_DIR}"
emit_env CMAKE_PREFIX_PATH "${ABS_DIR}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
if [ "$(uname -s)" = Darwin ]; then
  emit_env DYLD_LIBRARY_PATH "${LIB_DIR}${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}"
else
  emit_env LD_LIBRARY_PATH "${LIB_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi
[ "${ADD_TO_PATH}" = true ] && [ -d "${ABS_DIR}/bin" ] && [ -n "${GITHUB_PATH:-}" ] && echo "${ABS_DIR}/bin" >> "${GITHUB_PATH}"

log "installed MLX ${VERSION} (${TRIPLET}) to ${ABS_DIR}"
