#!/usr/bin/env bash
###############################################################################
# start_spack_bundle.sh
# -----------------------------------------------------------------------------
# Generic activation helper for a Spack-Stack environment created from this
# repository.
#
# This script is meant to be sourced:
#   source start_spack_bundle.sh [options]
#
# Options:
#   --version <ver>        Spack-Stack version
#   --env <name>           Environment name
#   --root-prefix <path>   Prefix that contains spack-stack_<version>
#   --compiler-module <m>  Meta-module to load after activation
#   --mpi-module <m>       MPI meta-module to load after activation
#
# The installer script rewrites the defaults below when generating a private
# copy in ~/.spack/<env>/start_spack_bundle.sh.
###############################################################################

DEFAULT_SPACK_VERSION="1.7.0"
DEFAULT_ENV_NAME="mpas-bundle"
DEFAULT_ROOT_PREFIX="/mnt/beegfs/$USER"
DEFAULT_COMPILER_MODULE="stack-gcc/9.4.0"
DEFAULT_MPI_MODULE="stack-openmpi/4.1.1"

_disable_conda() {
    if [[ -n "${CONDA_PREFIX:-}" ]]; then
        echo "[INFO] Conda ativo detectado em: $CONDA_PREFIX"
        while [[ -n "${CONDA_PREFIX:-}" ]]; do
            if command -v conda >/dev/null 2>&1; then
                conda deactivate >/dev/null 2>&1 || break
            elif [[ -n "$(type -t deactivate 2>/dev/null || true)" ]]; then
                deactivate >/dev/null 2>&1 || break
            else
                break
            fi
        done
        unset CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_PROMPT_MODIFIER CONDA_SHLVL _CONDA_ROOT || true
        echo "[INFO] Ambientes Conda foram desativados."
    fi
}

_activate_spack_bundle() {
    local _old_set
    _old_set=$(set +o)
    set -Eeuo pipefail
    trap 'printf "[ERROR] %s – linha %d\n" "${BASH_SOURCE[0]}" "$LINENO" >&2; return 2 2>/dev/null || exit 2' ERR

    local spack_version="$DEFAULT_SPACK_VERSION"
    local env_name="$DEFAULT_ENV_NAME"
    local root_prefix="$DEFAULT_ROOT_PREFIX"
    local compiler_module="$DEFAULT_COMPILER_MODULE"
    local mpi_module="$DEFAULT_MPI_MODULE"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) spack_version="$2"; shift 2 ;;
            --env) env_name="$2"; shift 2 ;;
            --root-prefix|--spack-root) root_prefix="$2"; shift 2 ;;
            --compiler-module) compiler_module="$2"; shift 2 ;;
            --mpi-module) mpi_module="$2"; shift 2 ;;
            *) echo "[ERROR] Opção desconhecida: $1" >&2; return 1 2>/dev/null || exit 1 ;;
        esac
    done

    local spack_root="$root_prefix/spack-stack_$spack_version"
    local spack_env_path="$spack_root/envs/$env_name"
    local module_core_path="$spack_env_path/install/modulefiles/Core"
    local env_flag
    env_flag="$(tr '[:lower:]-' '[:upper:]_' <<< "$env_name")_ENV_ACTIVE"

    [[ -d "$spack_root" ]] || { echo "[ERROR] Spack root não encontrado: $spack_root" >&2; return 1 2>/dev/null || exit 1; }
    [[ -d "$spack_env_path" ]] || { echo "[ERROR] Ambiente Spack não encontrado: $spack_env_path" >&2; return 1 2>/dev/null || exit 1; }

    if [[ ${!env_flag:-0} -eq 1 ]]; then
        echo "[INFO] Ambiente '$env_name' já está ativo."
        trap - ERR
        eval "$_old_set"
        return 0 2>/dev/null || exit 0
    fi

    _disable_conda

    export PATH="$spack_root/bin:$PATH"
    export SPACK_DISABLE_LOCAL_CONFIG=true
    export SPACK_USER_CACHE_PATH="/mnt/beegfs/$USER/.spack-user-cache"
    export XDG_CACHE_HOME="/mnt/beegfs/$USER/.xdg-cache"
    mkdir -p "$SPACK_USER_CACHE_PATH" "$XDG_CACHE_HOME"

    local oldpwd_spack="$PWD"
    cd "$spack_root"
    source ./setup.sh
    cd "$oldpwd_spack"

    command -v spack >/dev/null 2>&1 || { echo "[ERROR] spack não ficou disponível após setup.sh" >&2; return 1 2>/dev/null || exit 1; }

    echo "[INFO] Ativando ambiente $env_name em $spack_env_path"
    spack env activate "$spack_env_path"

    if [[ -d "$module_core_path" ]]; then
        module use "$module_core_path"
    fi

    if [[ -n "$compiler_module" ]]; then
        module load "$compiler_module" >/dev/null 2>&1 || echo "[WARNING] Módulo não encontrado: $compiler_module"
    fi

    if [[ -n "$mpi_module" ]]; then
        module load "$mpi_module" >/dev/null 2>&1 || echo "[WARNING] Módulo não encontrado: $mpi_module"
    fi

    local netcdf_dir netcdf_cxx_dir hdf5_dir libdir
    netcdf_dir="$(spack location -i netcdf-c 2>/dev/null || true)"
    netcdf_cxx_dir="$(spack location -i netcdf-cxx4 2>/dev/null || true)"
    hdf5_dir="$(spack location -i hdf5 2>/dev/null || true)"

    [[ -n "$netcdf_dir" ]] && export NETCDF_DIR="$netcdf_dir"
    [[ -n "$netcdf_cxx_dir" ]] && export NETCDF_CXX_DIR="$netcdf_cxx_dir"
    [[ -n "$hdf5_dir" ]] && export HDF5_DIR="$hdf5_dir"

    for libdir in "${NETCDF_DIR:-}/lib" "${NETCDF_CXX_DIR:-}/lib" "${HDF5_DIR:-}/lib"; do
        [[ -d "$libdir" ]] && export LD_LIBRARY_PATH="$libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    done

    export "$env_flag"=1
    echo "[INFO] Ambiente '$env_name' ativado com sucesso."

    trap - ERR
    eval "$_old_set"
}

_activate_spack_bundle "$@"
