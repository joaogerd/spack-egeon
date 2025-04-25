#!/bin/bash

# ===============================
# Instalação e Testes do Spack-Stack na Egeon
# ===============================
set -e

start=$(date +%s)

# CONFIGURAÇÕES
export SPACK_VERSION="${1:-1.7.0}"
export ENV_NAME="mpas-bundle"
export SPACK_DIR="/mnt/beegfs/$USER/spack-stack_$SPACK_VERSION"
export EGEON_CONFIG_REPO="/mnt/beegfs/$USER/spack-egeon"
export MODULE_CORE_PATH="$SPACK_DIR/envs/$ENV_NAME/install/modulefiles/Core"
export SPACK_ENV_DIR="$HOME/.spack/$ENV_NAME"

# CONFIGURAÇÕES DE CACHE
export SPACK_USER_CACHE_PATH="/mnt/beegfs/$USER/.spack-user-cache"
export XDG_CACHE_HOME="/mnt/beegfs/$USER/.xdg-cache"
mkdir -p "$SPACK_USER_CACHE_PATH" "$XDG_CACHE_HOME"

# LIMPEZA DE AMBIENTE
echo "[INFO] Removendo cache local do Spack..."
rm -rf ~/.cache/spack
rm -rf ~/.spack

echo "[INFO] Limpando variáveis de ambiente de versões anteriores do Spack..."
unset SPACK_ENV
unset SPACK_ROOT
unset SPACK_STACK_DIR

# PREPARAÇÃO
echo "[INFO] Usando Spack-Stack versão: $SPACK_VERSION"
echo "[INFO] Preparando diretório de trabalho em /mnt/beegfs/$USER"
cd /mnt/beegfs/$USER

if [ ! -d "$EGEON_CONFIG_REPO" ]; then
    echo "[INFO] Clonando repositório de configuração spack-egeon..."
    git clone https://github.com/joaogerd/spack-egeon.git
fi

if [ ! -d "$SPACK_DIR" ]; then
    echo "[INFO] Clonando Spack-Stack versão $SPACK_VERSION..."
    git clone https://github.com/JCSDA/spack-stack -b release/$SPACK_VERSION $SPACK_DIR --recurse-submodules
else
    echo "[INFO] Diretório $SPACK_DIR já existe. Atualizando submódulos..."
    cd "$SPACK_DIR"
    git submodule update --init --recursive
fi

# Garantindo submódulos atualizados
cd "$SPACK_DIR"
git submodule update --init --recursive

# Inicializando ambiente
echo "[INFO] Carregando módulo do compilador GCC..."
module load gnu9

echo "[INFO] Inicializando Spack-Stack..."
source setup.sh

# CONFIGURAÇÃO DO SITE
echo "[INFO] Copiando arquivos de configuração do site e template..."
cp -r "$EGEON_CONFIG_REPO/configs/sites/egeon" configs/sites/
cp -r "$EGEON_CONFIG_REPO/configs/templates/mpas-bundle" configs/templates/

# CRIAÇÃO DO AMBIENTE
if [ ! -d "$SPACK_DIR/envs/$ENV_NAME" ]; then
    echo "[INFO] Criando ambiente '$ENV_NAME'..."
    spack stack create env --name=$ENV_NAME --template=mpas-bundle --site=egeon
else
    echo "[INFO] Ambiente '$ENV_NAME' já existe. Pulando criação."
fi

if [ -f "$SPACK_DIR/envs/$ENV_NAME/spack.yaml" ]; then
    cd "$SPACK_DIR/envs/$ENV_NAME"
    echo "[INFO] Ativando ambiente..."
    spack env activate .
else
    echo "[ERROR] Arquivo spack.yaml não encontrado no ambiente '$ENV_NAME'."
    exit 1
fi

echo "[INFO] Concretizando ambiente..."
spack concretize 2>&1 | tee log.concretize

echo "[INFO] Instalando pacotes do ambiente..."
spack install 2>&1 | tee log.install

# Verificação de sucesso da instalação
if [ ! -d "$SPACK_DIR/envs/$ENV_NAME/install/modulefiles" ]; then
    echo "[ERROR] Instalação falhou. Diretório de módulos não foi criado."
    exit 1
fi

echo "[INFO] Configurando meta-módulos..."
spack stack setup-meta-modules 2>&1 | tee log.metamodules

# CARREGAMENTO DE MÓDULOS
echo "[INFO] Carregando módulos compilados..."
module use "$MODULE_CORE_PATH"
module load stack-gcc/9.4.0
module load openmpi/4.1.1 || true

# CONFIGURAÇÃO DE LD_LIBRARY_PATH PARA TESTES
echo "[INFO] Configurando LD_LIBRARY_PATH para testes..."

NETCDF_DIR=$(spack location -i netcdf-c)
NETCDF_CXX_DIR=$(spack location -i netcdf-cxx4)
HDF5_DIR=$(spack location -i hdf5)

if [ -d "$NETCDF_DIR" ]; then
    export LD_LIBRARY_PATH="$NETCDF_DIR/lib:$LD_LIBRARY_PATH"
fi

if [ -d "$NETCDF_CXX_DIR" ]; then
    export LD_LIBRARY_PATH="$NETCDF_CXX_DIR/lib:$LD_LIBRARY_PATH"
fi

if [ -d "$HDF5_DIR" ]; then
    export LD_LIBRARY_PATH="$HDF5_DIR/lib:$LD_LIBRARY_PATH"
fi
echo $LD_LIBRARY_PATH
# TESTES
echo "[INFO] Iniciando testes de bibliotecas..."
mkdir -p ~/spack_tests && cd ~/spack_tests

## Teste NetCDF
echo "[TEST] Compilando e executando teste com NetCDF..."
cat <<EOF > test_netcdf.c
#include <netcdf.h>
#include <stdio.h>
int main() {
    int ncid, retval;
    const char *filename = "test.nc";
    if ((retval = nc_create(filename, NC_CLOBBER, &ncid))) return retval;
    if ((retval = nc_close(ncid))) return retval;
    if ((retval = nc_open(filename, NC_NOWRITE, &ncid))) return retval;
    printf("NetCDF test passed. File '%s' created and opened successfully.\\n", filename);
    return 0;
}
EOF

gcc test_netcdf.c -o test_netcdf -I$NETCDF_DIR/include -L$NETCDF_DIR/lib -lnetcdf
./test_netcdf

## Teste NetCDF-cxx4
cat <<EOF > test_netcdf_cxx.cpp
#include <netcdf>
#include <iostream>

int main() {
    try {
        std::string filename = "test_cxx.nc";
        netCDF::NcFile dataFile(filename, netCDF::NcFile::replace);
        std::cout << "NetCDF-C++ test passed. File '" << filename << "' created successfully." << std::endl;
    } catch (netCDF::exceptions::NcException& e) {
        std::cerr << "NetCDF-C++ test failed: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}
EOF

g++ test_netcdf_cxx.cpp -o test_netcdf_cxx -I$NETCDF_CXX_DIR/include -L$NETCDF_CXX_DIR/lib -I$NETCDF_DIR/include -L$NETCDF_DIR/lib -lnetcdf_c++4
./test_netcdf_cxx

## Teste HDF5
echo "[TEST] Compilando e executando teste com HDF5..."
cat <<EOF > test_hdf5.c
#include "hdf5.h"
#include <stdio.h>
int main() {
    hid_t file_id;
    herr_t status;
    file_id = H5Fcreate("test.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    if (file_id < 0) {
        printf("Error creating HDF5 file.\\n");
        return 1;
    }
    status = H5Fclose(file_id);
    if (status < 0) {
        printf("Error closing HDF5 file.\\n");
        return 1;
    }
    printf("HDF5 test passed. File 'test.h5' created successfully.\\n");
    return 0;
}
EOF

gcc test_hdf5.c -o test_hdf5 -I$HDF5_DIR/include -L$HDF5_DIR/lib -lhdf5
./test_hdf5

## Teste OpenMPI
echo "[TEST] Compilando e executando teste com OpenMPI..."
cat <<EOF > test_mpi.c
#include <mpi.h>
#include <stdio.h>
int main(int argc, char *argv[]) {
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    printf("Hello from rank %d of %d.\\n", rank, size);
    MPI_Finalize();
    return 0;
}
EOF

mpicc test_mpi.c -o test_mpi
mpirun -np 4 ./test_mpi

chmod +x test_*

# VERIFICAÇÃO FINAL
echo "[INFO] Verificando arquivos gerados..."
ncdump test.nc | head -n 5 || echo "[WARNING] Erro ao usar ncdump"
h5dump test.h5 | head -n 5 || echo "[WARNING] Erro ao usar h5dump"

# GERANDO SCRIPT DE ATIVAÇÃO
mkdir -p $SPACK_ENV_DIR || echo "[WARNING] Erro ao criar $SPACK_ENV_DIR"
OUTPUT="$SPACK_ENV_DIR/start_spack_bundle.sh"
{
	printf '%s\n' '#!/usr/bin/env bash'
	printf '%s\n' '###############################################################################'
	printf '%s\n' '# start_spack_bundle.sh'
	printf '%s\n' '# -----------------------------------------------------------------------------'
	printf '%s\n' '# Activate the **shared Spack‑Stack environment** (mpas‑bundle) on Egeon.'
	printf '%s\n' '# -----------------------------------------------------------------------------'
	printf '%s\n' '# Maintainer : João Gerd Zell de Mattos <joao.gerd@gmail.com>'
	printf '%s\n' '# Created    : 2025‑04‑?? (original version)'
	printf '%s\n' '# Last update: 2025‑04‑25'
	printf '%s\n' ''
	printf '%s\n' '# PURPOSE'
	printf '%s\n' '# ======='
	printf '%s\n' '# Initialise a **read‑only, centrally installed** Spack‑Stack tree so that all'
	printf '%s\n' '# compilers, libraries and tools needed by MPAS‑JEDI are visible to the shell.'
	printf '%s\n' '# It performs four main steps:'
	printf '%s\n' '#   1. source Spack itself (adds `spack` to PATH).'
	printf '%s\n' '#   2. activate the requested *environment* (spack env activate …).'
	printf '%s\n' '#   3. extend `module` search path and load curated module sets (essentials,'
	printf '%s\n' '#      MPI‑dependent libs, etc.).'
	printf '%s\n' '#   4. export key variables (NETCDF_DIR, HDF5_DIR, …) **and** patch'
	printf '%s\n' '#      `LD_LIBRARY_PATH` for NetCDF/HDF5, because Lmod packages sometimes omit'
	printf '%s\n' '#      shared libs from MODULEPATH.'
	printf '%s\n' ''
	printf '%s\n' '# USAGE'
	printf '%s\n' '# -----'
	printf '%s\n' '#   source start_spack_bundle.sh [--version <ver>] [--env <name>]'
	printf '%s\n' '#                                [--spack-root <path>]'
	printf '%s\n' '#'
	printf '%s\n' '#   All options are *optional* and can be combined:'
	printf '%s\n' '#     --version      Spack‑Stack version   (default: 1.7.0)'
	printf '%s\n' '#     --env          Environment name      (default: mpas-bundle)'
	printf '%s\n' "#     --spack-root   Override root path    (default: $SPACK_ENV_DIR)"
	printf '%s\n' '#'
	printf '%s\n' '# The script is meant to be *sourced*, not executed, so that exported variables'
	printf '%s\n' '# persist in the caller shell (e.g. `source start_spack_bundle.sh`).'
	printf '%s\n' ''
	printf '%s\n' '# EXIT CODES'
	printf '%s\n' '#   0 success | 1 user error | 2 runtime failure (trap protected)'
	printf '%s\n' '###############################################################################'
	printf '%s\n' 'set -Eeuo pipefail'
	printf '%s\n' "trap 'printf \"[ERROR] %s – line %d.\\n\" \"\${BASH_SOURCE[0]}\" \$LINENO >&2; return 2 2>/dev/null || exit 2' ERR"
	printf '%s\n' ''
	printf '%s\n' '# -------- helpers ------------------------------------------------------------'
	printf '%s\n' 'log() { printf '\''[%s] %s\n'\'' "$(date +'\''%Y-%m-%d %H:%M:%S'\'')" "$*"; }'
	printf '%s\n' 'die() { log "[ERROR] $*"; return 1 2>/dev/null || exit 1; }'
	printf '%s\n' 'load_module() { module load "$1" 2>/dev/null || log "[WARN] module not found: $1"; }'
	printf '%s\n' ''
	printf '%s\n' '# -------- argument parsing ---------------------------------------------------'
	printf '%s\n' 'SPACK_VERSION=1.7.0'
	printf '%s\n' 'ENV_NAME=mpas-bundle'
	printf '%s\n' "ROOT_PREFIX="$SPACK_ENV_DIR""
	printf '%s\n' ''
	printf '%s\n' 'while [[ $# -gt 0 ]]; do'
	printf '%s\n' '  case "$1" in'
	printf '%s\n' '    --version)   SPACK_VERSION="$2" ; shift 2 ;;'
	printf '%s\n' '    --env)       ENV_NAME="$2"     ; shift 2 ;;'
	printf '%s\n' '    --spack-root) ROOT_PREFIX="$2" ; shift 2 ;;'
	printf '%s\n' '    *) die "Unknown option: $1" ;;'
	printf '%s\n' '  esac'
	printf '%s\n' 'done'
	printf '%s\n' ''
	printf '%s\n' '# -------- paths --------------------------------------------------------------'
	printf '%s\n' 'SPACK_ROOT="$ROOT_PREFIX/spack-stack_$SPACK_VERSION"'
	printf '%s\n' 'SPACK_ENV_PATH="$SPACK_ROOT/envs/$ENV_NAME"'
	printf '%s\n' 'MODULE_CORE_PATH="$SPACK_ENV_PATH/install/modulefiles/Core"'
	printf '%s\n' ''
	printf '%s\n' '[[ -d "$SPACK_ROOT" ]]      || die "Spack root not found: $SPACK_ROOT"'
	printf '%s\n' '[[ -d "$SPACK_ENV_PATH" ]]  || die "Spack env not found:  $SPACK_ENV_PATH"'
	printf '%s\n' ''
	printf '%s\n' '# Avoid repeated activation'
	printf '%s\n' 'ENV_FLAG="$(tr '\''[:lower:]-'\'' '\''[:upper:]_'\'' <<< "$ENV_NAME")_ENV_ACTIVE"'
	printf '%s\n' 'if [[ ${!ENV_FLAG:-0} -eq 1 ]]; then'
	printf '%s\n' '  log "[INFO] Environment '\''$ENV_NAME'\'' already active – skipping re‑activation."'
	printf '%s\n' '  return 0 2>/dev/null || exit 0'
	printf '%s\n' 'fi'
	printf '%s\n' ''
	printf '%s\n' 'START_TIME=$(date +%s)'
	printf '%s\n' ''
	printf '%s\n' '# -------- step 1: source Spack ----------------------------------------------'
	printf '%s\n' 'log "[INFO] Activating Spack ($SPACK_VERSION) at $SPACK_ROOT …"'
	printf '%s\n' 'export PATH="$SPACK_ROOT/bin:$PATH"'
	printf '%s\n' '# enter Spack root to avoid relative‑path issues inside setup.sh'
	printf '%s\n' 'OLDPWD_SPACK="$PWD"'
	printf '%s\n' 'cd "$SPACK_ROOT"'
	printf '%s\n' 'source "./setup.sh"'
	printf '%s\n' 'cd "$OLDPWD_SPACK"'
	printf '%s\n' ''
	printf '%s\n' '# user caches on BeeGFS to offload /home'
	printf '%s\n' 'export SPACK_USER_CACHE_PATH="/mnt/beegfs/$USER/.spack-user-cache"'
	printf '%s\n' 'export XDG_CACHE_HOME="/mnt/beegfs/$USER/.xdg-cache"'
	printf '%s\n' 'mkdir -p "$SPACK_USER_CACHE_PATH" "$XDG_CACHE_HOME"'
	printf '%s\n' ''
	printf '%s\n' 'command -v spack >/dev/null || die "spack not in PATH after activation."'
	printf '%s\n' ''
	printf '%s\n' '# -------- step 2: activate env ----------------------------------------------'
	printf '%s\n' 'log "[INFO] Activating Spack environment '\''$ENV_NAME'\'' …"'
	printf '%s\n' 'spack env activate "$SPACK_ENV_PATH"'
	printf '%s\n' ''
	printf '%s\n' '# -------- step 3: load modules ----------------------------------------------'
	printf '%s\n' 'module use "$MODULE_CORE_PATH"'
	printf '%s\n' ''
	printf '%s\n' 'log "[INFO] Loading essential modules ..."'
	printf '%s\n' 'ESSENTIALS=(stack-gcc/9.4.0 stack-openmpi/4.1.1 stack-python/3.10.13)'
	printf '%s\n' 'for m in "${ESSENTIALS[@]}"; do load_module "$m"; done'
	printf '%s\n' ''
	printf '%s\n' 'log "[INFO] Loading standard modules ..."'
	printf '%s\n' 'EXTRA_PKGS=('
	printf '%s\n' '  boost/1.84.0 jedi-cmake/1.4.0 python/3.10.13 c-blosc/1.21.5 libbsd/0.11.7'
	printf '%s\n' '  qhull/2020.2 ca-certificates-mozilla/2023-05-30 libmd/1.0.4 snappy/1.1.10'
	printf '%s\n' '  cmake/3.23.1 libxcrypt/4.4.35 sqlite/3.43.2 curl/8.4.0 nghttp2/1.57.0'
	printf '%s\n' '  ecbuild/3.7.2 openblas/0.3.24 eigen/3.4.0 tar/1.34 gcc-runtime/9.4.0'
	printf '%s\n' '  py-pip/23.1.2 udunits/2.2.28 gettext/0.21.1 py-pycodestyle/2.11.0'
	printf '%s\n' '  util-linux-uuid/2.38.1 gmake/4.3 py-setuptools/63.4.3 zlib-ng/2.1.5'
	printf '%s\n' '  gsl-lite/0.37.0 py-wheel/0.41.2 zstd/1.5.2'
	printf '%s\n' ')'
	printf '%s\n' 'for m in "${EXTRA_PKGS[@]}"; do load_module "$m"; done'
	printf '%s\n' ''
	printf '%s\n' 'log "[INFO] Loading MPI deps modules ..."'
	printf '%s\n' 'MPI_PKGS=('
	printf '%s\n' '  atlas/0.36.0 fftw/3.3.10 nccmp/1.9.0.1 parallelio/2.6.2'
	printf '%s\n' '  eckit/1.24.5 fiat/1.2.0 netcdf-c/4.9.2 ectrans/1.2.0 netcdf-cxx4/4.3.1'
	printf '%s\n' '  gptl/8.1.1 netcdf-fortran/4.6.1 fckit/0.11.0 hdf5/1.14.3 parallel-netcdf/1.12.3'
	printf '%s\n' ')'
	printf '%s\n' 'for m in "${MPI_PKGS[@]}"; do load_module "$m"; done'
	printf '%s\n' ''
	printf '%s\n' '# -------- step 4: export dirs + patch LD_LIBRARY_PATH ------------------------'
	printf '%s\n' ''
	printf '%s\n' 'log "[INFO] Updating LD_LIBRARY_PATH..."'
	printf '%s\n' 'NETCDF_DIR="$(spack location -i netcdf-c 2>/dev/null || true)"'
	printf '%s\n' 'NETCDF_CXX_DIR="$(spack location -i netcdf-cxx4 2>/dev/null || true)"'
	printf '%s\n' 'HDF5_DIR="$(spack location -i hdf5 2>/dev/null || true)"'
	printf '%s\n' ''
	printf '%s\n' '[[ -n "$NETCDF_DIR" ]]      && export NETCDF_DIR'
	printf '%s\n' '[[ -n "$NETCDF_CXX_DIR" ]]  && export NETCDF_CXX_DIR'
	printf '%s\n' '[[ -n "$HDF5_DIR" ]]        && export HDF5_DIR'
	printf '%s\n' ''
	printf '%s\n' 'for libdir in "$NETCDF_DIR/lib" "$NETCDF_CXX_DIR/lib" "$HDF5_DIR/lib"; do'
	printf '%s\n' '  [[ -d "$libdir" ]] && export LD_LIBRARY_PATH="$libdir:$LD_LIBRARY_PATH"'
	printf '%s\n' 'done'
	printf '%s\n' ''
	printf '%s\n' 'END_TIME=$(date +%s)'
	printf '%s\n' ''
	printf '%s\n' 'log "[INFO] Environment '\''$ENV_NAME'\'' is ready (Δt=$((END_TIME-START_TIME)) s)"'
	printf '%s\n' 'export "$ENV_FLAG"=1'
} > "$OUTPUT"

ls -l $SPACK_ENV_DIR/start_spack_bundle.sh
chmod u+x $SPACK_ENV_DIR/start_spack_bundle.sh

echo "[INFO] Para ativar o ambiente, execute:"
echo "       source $SPACK_ENV_DIR/start_spack_bundle.sh"

end=$(date +%s)
echo "[INFO] Todos os testes foram concluídos com sucesso."
echo "[INFO] Tempo total de execução: $((end - start)) segundos"

