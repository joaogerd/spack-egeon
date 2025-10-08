#!/usr/bin/env bash
###############################################################################
# start_spack_bundle.sh
# -----------------------------------------------------------------------------
# Activate a **shared Spack-Stack environment** on Egeon
# (e.g., mpas-bundle, obsproc-bundle).
# -----------------------------------------------------------------------------
# Maintainer : João Gerd Zell de Mattos <joao.gerd@gmail.com>
# Created    : 2025‑04‑?? (original version)
#      update: 2025‑06‑05  (added disable_conda helper)
# Last update: 2025-08-20  (multi-bundle docs; optional per-env module lists)
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
# EXAMPLES
# --------
#   source start_spack_bundle.sh
#   source start_spack_bundle.sh --env mpas-bundle
#   source start_spack_bundle.sh --env obsproc-bundle
#   source start_spack_bundle.sh --version 1.7.0 --spack-root /mnt/beegfs/das.group
#
# ENV-SPECIFIC MODULE LISTS (optional)
# ------------------------------------
# If present, the script will source:
#   ~/.spack/<ENV_NAME>/env.modules.sh
# providing arrays ESSENTIALS / EXTRA_PKGS / MPI_PKGS to load. 
#
# IMPORTANT
# ---------
# This script is meant to be *sourced*, not executed, so that exported variables
# persist in the caller shell (e.g. `source start_spack_bundle.sh`).
#
# EXIT CODES
#   0 success | 1 user error | 2 runtime failure (trap protected)
###############################################################################

###############################################################################
# !FUNCTION: disable_conda
# !DESCRIPTION:
#   Checks whether a Conda environment is active and completely deactivates it.
###############################################################################
disable_conda() {
    if [[ -n "$CONDA_PREFIX" ]]; then
        echo "[WARNING]  Conda environment detected: $CONDA_PREFIX"
        echo "[ACTION] Deactivating all Conda environments…"
        
        # Deactivate in a loop until no CONDA_PREFIX remains
        while [[ -n "$CONDA_PREFIX" ]]; do
            if command -v conda &>/dev/null; then
                conda deactivate &>/dev/null || break
            elif [[ -n "$(type -t deactivate)" ]]; then
                # Compatibility with very old Conda setups
                deactivate &>/dev/null || break
            else
                break
            fi
        done
        
        # Unset Conda-related variables
        unset CONDA_PREFIX \
              CONDA_DEFAULT_ENV \
              CONDA_PROMPT_MODIFIER \
              CONDA_SHLVL \
              _CONDA_ROOT
        
        echo "[ OK ] All Conda environments have been disabled."
    } else
        echo "[ OK ] No active Conda environment detected."
    fi
}

###############################################################################
# Pequenos utilitários de log/erro (mantidos como no original)
###############################################################################
_log() { printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
_die() { _log "[ERROR] $*"; return 1 2>/dev/null || exit 1; }
_load_module() { module load "$1" 2>/dev/null || _log "[WARN] module not found: $1"; }

###############################################################################
# !FUNCTION: parse_args
# !DESCRIPTION:
#   Parse CLI options into globals: SPACK_VERSION, ENV_NAME, ROOT_PREFIX.
###############################################################################
parse_args() {
  SPACK_VERSION=${SPACK_VERSION:-1.7.0}
  ENV_NAME=${ENV_NAME:-mpas-bundle}
  ROOT_PREFIX=${ROOT_PREFIX:-/mnt/beegfs/das.group}

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)     SPACK_VERSION="$2"; shift 2 ;;
      --env)         ENV_NAME="$2";      shift 2 ;;
      --spack-root)  ROOT_PREFIX="$2";   shift 2 ;;
      *) _die "Unknown option: $1" ;;
    esac
  done
}

###############################################################################
# !FUNCTION: resolve_paths
# !DESCRIPTION:
#   Compute paths for Spack root, env path and Core modules path. Validate all.
###############################################################################
resolve_paths() {
  SPACK_ROOT="$ROOT_PREFIX/spack-stack_$SPACK_VERSION"
  SPACK_ENV_PATH="$SPACK_ROOT/envs/$ENV_NAME"
  MODULE_CORE_PATH="$SPACK_ENV_PATH/install/modulefiles/Core"

  [[ -d "$SPACK_ROOT"      ]] || _die "Spack-Stack root not found: $SPACK_ROOT"
  [[ -f "$SPACK_ROOT/setup.sh" ]] || _die "setup.sh not found at: $SPACK_ROOT/setup.sh"
  [[ -d "$SPACK_ENV_PATH"  ]] || _die "Spack environment not found: $SPACK_ENV_PATH"
  [[ -d "$MODULE_CORE_PATH" ]] || _die "Core module path not found: $MODULE_CORE_PATH"
}

###############################################################################
# !FUNCTION: spack_bootstrap
# !DESCRIPTION:
#   Put Spack on PATH, disable local scopes, source setup.sh and set caches.
###############################################################################
spack_bootstrap() {
  _log "[INFO] Activating Spack ($SPACK_VERSION) at $SPACK_ROOT …"
  export PATH="$SPACK_ROOT/bin:$PATH"
  export SPACK_DISABLE_LOCAL_CONFIG=true

  local _oldpwd="$PWD"
  cd "$SPACK_ROOT"
  # shellcheck disable=SC1091
  source "./setup.sh"
  cd "$_oldpwd"

  # offload caches to BeeGFS
  export SPACK_USER_CACHE_PATH="/mnt/beegfs/$USER/.spack-user-cache"
  export XDG_CACHE_HOME="/mnt/beegfs/$USER/.xdg-cache"
  mkdir -p "$SPACK_USER_CACHE_PATH" "$XDG_CACHE_HOME"

  command -v spack >/dev/null || _die "spack not in PATH after activation."
}

###############################################################################
# !FUNCTION: spack_activate_env
# !DESCRIPTION:
#   Activate the requested Spack environment.
###############################################################################
spack_activate_env() {
  _log "[INFO] Activating Spack environment '$ENV_NAME' …"
  spack env activate "$SPACK_ENV_PATH"
}

###############################################################################
# !FUNCTION: ensure_lmod
# !DESCRIPTION:
#   Ensure the 'module' command is available and add Core module path.
###############################################################################
ensure_lmod() {
  type module &>/dev/null || {
    [[ -f /etc/profile.d/modules.sh ]] && . /etc/profile.d/modules.sh || true
    [[ -f /usr/share/lmod/lmod/init/bash ]] && . /usr/share/lmod/lmod/init/bash || true
  }
  type module &>/dev/null || _die "'module' command not found; please init Lmod"
  module use "$MODULE_CORE_PATH"
}

###############################################################################
# !FUNCTION: load_env_module_lists
# !DESCRIPTION:
#   Source ~/.spack/<ENV_NAME>/env.modules.sh if present to get arrays:
#   ESSENTIALS, EXTRA_PKGS, MPI_PKGS.
###############################################################################
load_env_module_lists() {
  ENV_MODULES_FILE="${HOME}/.spack/${ENV_NAME}/env.modules.sh"
  if [[ -f "$ENV_MODULES_FILE" ]]; then
    _log "[INFO] Using environment module list: $ENV_MODULES_FILE"
    # shellcheck disable=SC1090
    . "$ENV_MODULES_FILE"
  else
    _die "No env.modules.sh found for '${ENV_NAME}' ."
  fi
}

###############################################################################
# !FUNCTION: load_module_sets
# !DESCRIPTION:
#   Load ESSENTIALS, EXTRA_PKGS and MPI_PKGS arrays (if defined).
###############################################################################
load_module_sets() {
  _log "[INFO] Loading essential modules ..."
  for m in "${ESSENTIALS[@]:-}"; do _load_module "$m"; done

  _log "[INFO] Loading standard modules ..."
  for m in "${EXTRA_PKGS[@]:-}"; do _load_module "$m"; done

  _log "[INFO] Loading MPI deps modules ..."
  for m in "${MPI_PKGS[@]:-}"; do _load_module "$m"; done
}

###############################################################################
# !FUNCTION: export_core_vars_and_patch_ld
# !DESCRIPTION:
#   Export NETCDF/HDF5 dirs (if found) and patch LD_LIBRARY_PATH.
###############################################################################
export_core_vars_and_patch_ld() {
  _log "[INFO] Updating LD_LIBRARY_PATH..."
  NETCDF_DIR="$(spack location -i netcdf-c    2>/dev/null || true)"
  NETCDF_CXX_DIR="$(spack location -i netcdf-cxx4 2>/dev/null || true)"
  HDF5_DIR="$(spack location -i hdf5         2>/dev/null || true)"

  [[ -n "$NETCDF_DIR"     ]] && export NETCDF_DIR
  [[ -n "$NETCDF_CXX_DIR" ]] && export NETCDF_CXX_DIR
  [[ -n "$HDF5_DIR"       ]] && export HDF5_DIR

  for libdir in "$NETCDF_DIR/lib" "$NETCDF_CXX_DIR/lib" "$HDF5_DIR/lib"; do
    [[ -d "$libdir" ]] && export LD_LIBRARY_PATH="$libdir:$LD_LIBRARY_PATH"
  done
}

###############################################################################
# !FUNCTION: mark_env_active
# !DESCRIPTION:
#   Set an upper-case guard variable to avoid re-activation.
###############################################################################
mark_env_active() {
  ENV_FLAG="$(tr '[:lower:]-' '[:upper:]_' <<< "$ENV_NAME")_ENV_ACTIVE"
  export "$ENV_FLAG"=1
}

###############################################################################
# !FUNCTION: is_env_already_active
# !DESCRIPTION:
#   Return 0 if guard variable indicates env is already active.
###############################################################################
is_env_already_active() {
  local flag
  flag="$(tr '[:lower:]-' '[:upper:]_' <<< "$ENV_NAME")_ENV_ACTIVE"
  [[ ${!flag:-0} -eq 1 ]]
}

###############################################################################
# !FUNCTION: activate_spack
# !DESCRIPTION:
#   Orquestra a ativação: parse, valida, Spack, env, Lmod, módulos e exports.
###############################################################################
activate_spack () {
  ###########################################################################
  # Save the current shell flags so we can restore them later.              #
  ###########################################################################
  local _old_set
  _old_set=$(set +o)   # e.g. "set +o errexit +o nounset …"

  ###########################################################################
  # Strict mode apenas dentro desta função                                  #
  ###########################################################################
  set -Eeuo pipefail

  ###########################################################################
  # Trap de erro com retorno 2 (mantido no mesmo formato semântico)         #
  ###########################################################################
  trap '{
      printf "[ERROR] %s – line %d\n" "${BASH_SOURCE[0]}" $LINENO >&2
      return 2 2>/dev/null || exit 2
  }' ERR

  local START_TIME END_TIME

  # -------- argumentos e paths ----------------------------------------------
  parse_args "$@"
  resolve_paths

  # -------- evitar reativação ------------------------------------------------
  if is_env_already_active; then
    _log "[INFO] Environment '$ENV_NAME' already active – skipping re‑activation."
    trap - ERR; eval "$_old_set"
    return 0 2>/dev/null || exit 0
  fi

  START_TIME=$(date +%s)

  # -------- step 1: Spack ----------------------------------------------------
  spack_bootstrap

  # -------- step 2: ativar env ----------------------------------------------
  spack_activate_env

  # -------- step 3: Lmod + módulos ------------------------------------------
  ensure_lmod
  load_env_module_lists
  load_module_sets

  # -------- step 4: export + LD_LIBRARY_PATH --------------------------------
  export_core_vars_and_patch_ld

  END_TIME=$(date +%s)
  _log "[INFO] Environment '$ENV_NAME' is ready (Δt=$((END_TIME-START_TIME)) s)"
  mark_env_active

  ###########################################################################
  # Restore flags e remover trap                                             #
  ###########################################################################
  trap - ERR
  eval "$_old_set"
}

# Disable Conda (if necessary) before activating Spack
disable_conda

# Execute the function, forwarding any CLI arguments the user provides.
activate_spack "$@"

