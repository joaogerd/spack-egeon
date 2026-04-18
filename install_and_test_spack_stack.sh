#!/usr/bin/env bash

###############################################################################
# install_and_test_spack_stack.sh
# -----------------------------------------------------------------------------
# Provisiona um ambiente Spack-Stack a partir das configurações deste
# repositório, com foco em fluxo reprodutível e parametrizável por máquina.
#
# Uso:
#   ./install_and_test_spack_stack.sh [opções]
#
# Opções:
#   --version <ver>           Versão do spack-stack (default: 1.7.0)
#   --env <name>              Nome do ambiente Spack (default: mpas-bundle)
#   --site <name>             Site a usar em configs/sites/<name> (default: egeon)
#   --template <name>         Template a usar (default: mpas-bundle)
#   --workdir <path>          Diretório base de trabalho (default: /mnt/beegfs/$USER)
#   --config-repo <path>      Caminho local do repositório spack-stack-inpe
#   --config-repo-url <url>   URL Git do repositório de configuração
#   --compiler-module <mod>   Módulo base a carregar antes do setup (default: gnu9)
#   --clean                   Remove caches e recria ambiente de forma limpa
#   --skip-tests              Pula os testes funcionais ao final
###############################################################################

set -Eeuo pipefail
trap 'echo "[ERROR] Falha em ${BASH_SOURCE[0]} na linha $LINENO" >&2' ERR

log() { echo "[INFO] $*"; }
warn() { echo "[WARNING] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

SPACK_VERSION="1.7.0"
ENV_NAME="mpas-bundle"
SITE_NAME="egeon"
TEMPLATE_NAME="mpas-bundle"
WORKDIR_ROOT="/mnt/beegfs/$USER"
COMPILER_MODULE="gnu9"
SKIP_TESTS=0
DO_CLEAN=0
CONFIG_REPO_URL="https://github.com/GAD-DIMNT-CPTEC/spack-stack-inpe.git"
CONFIG_REPO_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) SPACK_VERSION="$2"; shift 2 ;;
        --env) ENV_NAME="$2"; shift 2 ;;
        --site) SITE_NAME="$2"; shift 2 ;;
        --template) TEMPLATE_NAME="$2"; shift 2 ;;
        --workdir) WORKDIR_ROOT="$2"; shift 2 ;;
        --config-repo) CONFIG_REPO_PATH="$2"; shift 2 ;;
        --config-repo-url) CONFIG_REPO_URL="$2"; shift 2 ;;
        --compiler-module) COMPILER_MODULE="$2"; shift 2 ;;
        --skip-tests) SKIP_TESTS=1; shift ;;
        --clean) DO_CLEAN=1; shift ;;
        *) die "Opção desconhecida: $1" ;;
    esac
done

START_TIME=$(date +%s)
SPACK_DIR="$WORKDIR_ROOT/spack-stack_$SPACK_VERSION"
MODULE_CORE_PATH="$SPACK_DIR/envs/$ENV_NAME/install/modulefiles/Core"
SPACK_ENV_DIR="$HOME/.spack/$ENV_NAME"
TEST_DIR="$HOME/spack_tests/$ENV_NAME"

if [[ -z "$CONFIG_REPO_PATH" ]]; then
    CONFIG_REPO_PATH="$WORKDIR_ROOT/spack-stack-inpe"
fi

export SPACK_USER_CACHE_PATH="$WORKDIR_ROOT/.spack-user-cache"
export XDG_CACHE_HOME="$WORKDIR_ROOT/.xdg-cache"
mkdir -p "$SPACK_USER_CACHE_PATH" "$XDG_CACHE_HOME"
mkdir -p "$WORKDIR_ROOT"

if [[ $DO_CLEAN -eq 1 ]]; then
    log "Limpando caches e ambiente anterior..."
    rm -rf ~/.cache/spack ~/.spack "$TEST_DIR"
    rm -rf "$SPACK_DIR/envs/$ENV_NAME"
fi

unset SPACK_ENV SPACK_ROOT SPACK_STACK_DIR || true

log "Versão do spack-stack: $SPACK_VERSION"
log "Site: $SITE_NAME | Template: $TEMPLATE_NAME | Ambiente: $ENV_NAME"
log "Diretório de trabalho: $WORKDIR_ROOT"
cd "$WORKDIR_ROOT"

if [[ ! -d "$CONFIG_REPO_PATH/.git" ]]; then
    log "Clonando repositório de configuração em $CONFIG_REPO_PATH"
    git clone "$CONFIG_REPO_URL" "$CONFIG_REPO_PATH"
else
    log "Repositório de configuração já existe em $CONFIG_REPO_PATH"
fi

[[ -d "$CONFIG_REPO_PATH/configs/sites/$SITE_NAME" ]] || die "Site não encontrado: $CONFIG_REPO_PATH/configs/sites/$SITE_NAME"
[[ -d "$CONFIG_REPO_PATH/configs/templates/$TEMPLATE_NAME" ]] || die "Template não encontrado: $CONFIG_REPO_PATH/configs/templates/$TEMPLATE_NAME"

if [[ ! -d "$SPACK_DIR/.git" ]]; then
    log "Clonando spack-stack release/$SPACK_VERSION em $SPACK_DIR"
    git clone https://github.com/JCSDA/spack-stack -b "release/$SPACK_VERSION" "$SPACK_DIR" --recurse-submodules
else
    log "spack-stack já existe em $SPACK_DIR; atualizando submódulos"
    cd "$SPACK_DIR"
    git submodule update --init --recursive
fi

cd "$SPACK_DIR"
git submodule update --init --recursive

if [[ -n "$COMPILER_MODULE" ]]; then
    log "Carregando módulo base do compilador: $COMPILER_MODULE"
    module load "$COMPILER_MODULE"
fi

log "Inicializando Spack-Stack"
source setup.sh

log "Copiando configurações de site e template"
rm -rf "configs/sites/$SITE_NAME" "configs/templates/$TEMPLATE_NAME"
cp -r "$CONFIG_REPO_PATH/configs/sites/$SITE_NAME" "configs/sites/"
cp -r "$CONFIG_REPO_PATH/configs/templates/$TEMPLATE_NAME" "configs/templates/"

if [[ ! -d "$SPACK_DIR/envs/$ENV_NAME" ]]; then
    log "Criando ambiente $ENV_NAME"
    spack stack create env --name="$ENV_NAME" --template="$TEMPLATE_NAME" --site="$SITE_NAME"
else
    log "Ambiente $ENV_NAME já existe; reutilizando"
fi

cd "$SPACK_DIR/envs/$ENV_NAME"
[[ -f spack.yaml ]] || die "spack.yaml não encontrado em $SPACK_DIR/envs/$ENV_NAME"

log "Ativando ambiente"
spack env activate .

log "Concretizando ambiente"
spack concretize 2>&1 | tee log.concretize

log "Instalando pacotes"
spack install --source 2>&1 | tee log.install

[[ -d "$SPACK_DIR/envs/$ENV_NAME/install/modulefiles" ]] || die "Instalação falhou: diretório de módulos não foi criado"

log "Atualizando módulos Lmod"
spack module lmod refresh -y 2>&1 | tee log.modules

log "Configurando meta-módulos"
spack stack setup-meta-modules 2>&1 | tee log.metamodules

if [[ -d "$MODULE_CORE_PATH" ]]; then
    module use "$MODULE_CORE_PATH"
fi
module load stack-gcc/9.4.0 >/dev/null 2>&1 || warn "Módulo stack-gcc/9.4.0 não encontrado"
module load stack-openmpi/4.1.1 >/dev/null 2>&1 || warn "Módulo stack-openmpi/4.1.1 não encontrado"

NETCDF_DIR="$(spack location -i netcdf-c 2>/dev/null || true)"
NETCDF_CXX_DIR="$(spack location -i netcdf-cxx4 2>/dev/null || true)"
HDF5_DIR="$(spack location -i hdf5 2>/dev/null || true)"

[[ -n "$NETCDF_DIR" ]] && export NETCDF_DIR
[[ -n "$NETCDF_CXX_DIR" ]] && export NETCDF_CXX_DIR
[[ -n "$HDF5_DIR" ]] && export HDF5_DIR
for libdir in "${NETCDF_DIR:-}/lib" "${NETCDF_CXX_DIR:-}/lib" "${HDF5_DIR:-}/lib"; do
    [[ -d "$libdir" ]] && export LD_LIBRARY_PATH="$libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
done

if [[ $SKIP_TESTS -eq 0 ]]; then
    log "Executando testes funcionais em $TEST_DIR"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"

    cat > test_netcdf.c <<'EOF'
#include <netcdf.h>
#include <stdio.h>
int main() {
    int ncid, retval;
    const char *filename = "test.nc";
    if ((retval = nc_create(filename, NC_CLOBBER, &ncid))) return retval;
    if ((retval = nc_close(ncid))) return retval;
    if ((retval = nc_open(filename, NC_NOWRITE, &ncid))) return retval;
    printf("NetCDF test passed. File '%s' created and opened successfully.\n", filename);
    return 0;
}
EOF
    gcc test_netcdf.c -o test_netcdf -I"$NETCDF_DIR/include" -L"$NETCDF_DIR/lib" -lnetcdf
    ./test_netcdf

    cat > test_netcdf_cxx.cpp <<'EOF'
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
    g++ test_netcdf_cxx.cpp -o test_netcdf_cxx -I"$NETCDF_CXX_DIR/include" -L"$NETCDF_CXX_DIR/lib" -I"$NETCDF_DIR/include" -L"$NETCDF_DIR/lib" -lnetcdf_c++4
    ./test_netcdf_cxx

    cat > test_hdf5.c <<'EOF'
#include "hdf5.h"
#include <stdio.h>
int main() {
    hid_t file_id;
    herr_t status;
    file_id = H5Fcreate("test.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    if (file_id < 0) return 1;
    status = H5Fclose(file_id);
    if (status < 0) return 1;
    printf("HDF5 test passed. File 'test.h5' created successfully.\n");
    return 0;
}
EOF
    mpicc test_hdf5.c -o test_hdf5 -I"$HDF5_DIR/include" -L"$HDF5_DIR/lib" -lhdf5
    ./test_hdf5

    cat > test_mpi.c <<'EOF'
#include <mpi.h>
#include <stdio.h>
int main(int argc, char *argv[]) {
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    printf("Hello from rank %d of %d.\n", rank, size);
    MPI_Finalize();
    return 0;
}
EOF
    mpicc test_mpi.c -o test_mpi
    mpirun -np 4 ./test_mpi

    ncdump test.nc | head -n 5 || warn "Erro ao usar ncdump"
    h5dump test.h5 | head -n 5 || warn "Erro ao usar h5dump"
else
    log "Testes funcionais foram pulados (--skip-tests)"
fi

mkdir -p "$SPACK_ENV_DIR"
TARGET_START_SCRIPT="$SPACK_ENV_DIR/start_spack_bundle.sh"
cp "$CONFIG_REPO_PATH/start_spack_bundle.sh" "$TARGET_START_SCRIPT"
python3 - "$TARGET_START_SCRIPT" "$SPACK_VERSION" "$ENV_NAME" "$WORKDIR_ROOT" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
version = sys.argv[2]
env_name = sys.argv[3]
root_prefix = sys.argv[4]
text = path.read_text()
text = text.replace('DEFAULT_SPACK_VERSION="1.7.0"', f'DEFAULT_SPACK_VERSION="{version}"')
text = text.replace('DEFAULT_ENV_NAME="mpas-bundle"', f'DEFAULT_ENV_NAME="{env_name}"')
text = text.replace('DEFAULT_ROOT_PREFIX="/mnt/beegfs/$USER"', f'DEFAULT_ROOT_PREFIX="{root_prefix}"')
path.write_text(text)
PY
chmod u+x "$TARGET_START_SCRIPT"

END_TIME=$(date +%s)
log "Instalação concluída com sucesso."
log "Para ativar o ambiente, execute: source $TARGET_START_SCRIPT"
log "Tempo total de execução: $((END_TIME - START_TIME)) segundos"
