#!/usr/bin/env bash
###############################################################################
# start_spack_bundle.sh
# -----------------------------------------------------------------------------
# Activate the **shared Spack‑Stack environment** (mpas‑bundle) on Egeon.
# -----------------------------------------------------------------------------
# Maintainer : João Gerd Zell de Mattos <joao.gerd@gmail.com>
# Created    : 2025‑04‑?? (original version)
# Last update: 2025‑04‑25
#
# PURPOSE
# =======
# Initialise a **read‑only, centrally installed** Spack‑Stack tree so that all
# compilers, libraries and tools needed by MPAS‑JEDI are visible to the shell.
# It performs four main steps:
#   1. source Spack itself (adds `spack` to PATH).
#   2. activate the requested *environment* (spack env activate …).
#   3. extend `module` search path and load curated module sets (essentials,
#      MPI‑dependent libs, etc.).
#   4. export key variables (NETCDF_DIR, HDF5_DIR, …) **and** patch
#      `LD_LIBRARY_PATH` for NetCDF/HDF5, because Lmod packages sometimes omit
#      shared libs from MODULEPATH.
#
# USAGE
# -----
#   source start_spack_bundle.sh [--version <ver>] [--env <name>]
#                                [--spack-root <path>]
#
#   All options are *optional* and can be combined:
#     --version      Spack‑Stack version   (default: 1.7.0)
#     --env          Environment name      (default: mpas-bundle)
#     --spack-root   Override root path    (default: /mnt/beegfs/das.group)
#
# The script is meant to be *sourced*, not executed, so that exported variables
# persist in the caller shell (e.g. `source start_spack_bundle.sh`).
#
# EXIT CODES
#   0 success | 1 user error | 2 runtime failure (trap protected)
###############################################################################
set -Eeuo pipefail
trap 'printf "[ERROR] %s – line %d.\n" "${BASH_SOURCE[0]}" $LINENO >&2; return 2 2>/dev/null || exit 2' ERR

# -------- helpers ------------------------------------------------------------
log() { printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" ; }
die() { log "[ERROR] $*" ; return 1 2>/dev/null || exit 1; }
load_module() { module load "$1" 2>/dev/null || log "[WARN] module not found: $1" ; }

# -------- argument parsing ---------------------------------------------------
SPACK_VERSION=1.7.0
ENV_NAME=mpas-bundle
ROOT_PREFIX="/mnt/beegfs/das.group"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   SPACK_VERSION="$2" ; shift 2 ;;
    --env)       ENV_NAME="$2"     ; shift 2 ;;
    --spack-root) ROOT_PREFIX="$2" ; shift 2 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# -------- paths --------------------------------------------------------------
SPACK_ROOT="$ROOT_PREFIX/spack-stack_$SPACK_VERSION"
SPACK_ENV_PATH="$SPACK_ROOT/envs/$ENV_NAME"
MODULE_CORE_PATH="$SPACK_ENV_PATH/install/modulefiles/Core"

[[ -d "$SPACK_ROOT" ]]      || die "Spack root not found: $SPACK_ROOT"
[[ -d "$SPACK_ENV_PATH" ]]  || die "Spack env not found:  $SPACK_ENV_PATH"

# Avoid repeated activation
ENV_FLAG="$(tr '[:lower:]-' '[:upper:]_' <<< "$ENV_NAME")_ENV_ACTIVE"
if [[ ${!ENV_FLAG:-0} -eq 1 ]]; then
  log "[INFO] Environment '$ENV_NAME' already active – skipping re‑activation."
  return 0 2>/dev/null || exit 0
fi

START_TIME=$(date +%s)

# -------- step 1: source Spack ----------------------------------------------
log "[INFO] Activating Spack ($SPACK_VERSION) at $SPACK_ROOT …"
export PATH="$SPACK_ROOT/bin:$PATH"
# enter Spack root to avoid relative‑path issues inside setup.sh
OLDPWD_SPACK="$PWD"
cd "$SPACK_ROOT"
source "./setup.sh"
cd "$OLDPWD_SPACK"

# user caches on BeeGFS to offload /home
export SPACK_USER_CACHE_PATH="/mnt/beegfs/$USER/.spack-user-cache"
export XDG_CACHE_HOME="/mnt/beegfs/$USER/.xdg-cache"
mkdir -p "$SPACK_USER_CACHE_PATH" "$XDG_CACHE_HOME"

command -v spack >/dev/null || die "spack not in PATH after activation."

# -------- step 2: activate env ----------------------------------------------
log "[INFO] Activating Spack environment '$ENV_NAME' …"
spack env activate "$SPACK_ENV_PATH"

# -------- step 3: load modules ----------------------------------------------
module use "$MODULE_CORE_PATH"

log "[INFO] Loading essential modules ..."
ESSENTIALS=(stack-gcc/9.4.0 stack-openmpi/4.1.1 stack-python/3.10.13)
for m in "${ESSENTIALS[@]}";   do load_module "$m"; done

log "[INFO] Loading standard modules ..."
EXTRA_PKGS=(
  boost/1.84.0 jedi-cmake/1.4.0 python/3.10.13 c-blosc/1.21.5 libbsd/0.11.7
  qhull/2020.2 ca-certificates-mozilla/2023-05-30 libmd/1.0.4 snappy/1.1.10
  cmake/3.23.1 libxcrypt/4.4.35 sqlite/3.43.2 curl/8.4.0 nghttp2/1.57.0
  ecbuild/3.7.2 openblas/0.3.24 eigen/3.4.0 tar/1.34 gcc-runtime/9.4.0
  py-pip/23.1.2 udunits/2.2.28 gettext/0.21.1 py-pycodestyle/2.11.0
  util-linux-uuid/2.38.1 gmake/4.3 py-setuptools/63.4.3 zlib-ng/2.1.5
  gsl-lite/0.37.0 py-wheel/0.41.2 zstd/1.5.2
)
for m in "${EXTRA_PKGS[@]}";    do load_module "$m"; done

log "[INFO] Loading MPI deps modules ..."
MPI_PKGS=(
  atlas/0.36.0 fftw/3.3.10 nccmp/1.9.0.1 parallelio/2.6.2
  eckit/1.24.5 fiat/1.2.0 netcdf-c/4.9.2 ectrans/1.2.0 netcdf-cxx4/4.3.1
  gptl/8.1.1 netcdf-fortran/4.6.1 fckit/0.11.0 hdf5/1.14.3 parallel-netcdf/1.12.3
)
for m in "${MPI_PKGS[@]}";      do load_module "$m"; done

# -------- step 4: export dirs + patch LD_LIBRARY_PATH ------------------------

log "[INFO] Updating LD_LIBRARY_PATH..."
NETCDF_DIR="$(spack location -i netcdf-c 2>/dev/null || true)"
NETCDF_CXX_DIR="$(spack location -i netcdf-cxx4 2>/dev/null || true)"
HDF5_DIR="$(spack location -i hdf5 2>/dev/null || true)"

[[ -n "$NETCDF_DIR" ]]      && export NETCDF_DIR
[[ -n "$NETCDF_CXX_DIR" ]]  && export NETCDF_CXX_DIR
[[ -n "$HDF5_DIR" ]]        && export HDF5_DIR

for libdir in "$NETCDF_DIR/lib" "$NETCDF_CXX_DIR/lib" "$HDF5_DIR/lib"; do
  [[ -d "$libdir" ]] && export LD_LIBRARY_PATH="$libdir:$LD_LIBRARY_PATH"
done

END_TIME=$(date +%s)

log "[INFO] Environment '$ENV_NAME' is ready (Δt=$((END_TIME-START_TIME)) s)"
export "$ENV_FLAG"=1

