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
echo ">>>>>> $SPACK_ENV_DIR/start_spack_bundle.sh"
cat<<EOF>$SPACK_ENV_DIR/start_spack_bundle.sh
#!/bin/bash
export LC_ALL="en_US.UTF-8"

# Salva o diretório original para restaurar depois
ORIGINAL_DIR="\$(pwd)"

# ============================================
# Inicialização do Ambiente Compartilhado mpas-bundle (Spack-Stack)
# ============================================
# Este script ativa um ambiente Spack previamente instalado e configurado
# no diretório compartilhado do grupo "das" na máquina Egeon.
# Ele carrega os módulos necessários e configura variáveis de ambiente
# para garantir que bibliotecas e ferramentas estejam acessíveis corretamente.

start=\$(date +%s)

# Versão do Spack-Stack e nome do ambiente
SPACK_VERSION=$SPACK_VERSION
ENV_NAME=$ENV_NAME

# Confirma os caminhos absolutos
SPACK_ENV_PATH="/mnt/beegfs/\$USER/spack-stack_\$SPACK_VERSION/envs/\$ENV_NAME"
MODULE_CORE_PATH="\$SPACK_ENV_PATH/install/modulefiles/Core"

echo "[INFO] Ativando ambiente Spack '\$ENV_NAME'..."
if [ ! -d "\$SPACK_ENV_PATH" ]; then
    echo "[ERROR] Caminho do ambiente Spack não encontrado: \$SPACK_ENV_PATH"
    return 1
fi

spack env activate "\$SPACK_ENV_PATH"

echo "[INFO] Incluindo diretório de módulos: \$MODULE_CORE_PATH"
module use "\$MODULE_CORE_PATH"

# -----------------------
# Função auxiliar
# -----------------------
load_module_if_available() {
    local module_name="\$1"
    module load "\$module_name" 2>/dev/null || echo "[WARNING] Módulo não encontrado: \$module_name"
}

# -----------------------
# Módulos essenciais
# -----------------------
ESSENTIALS=(
  stack-gcc/9.4.0
  stack-openmpi/4.1.1
  stack-python/3.10.13
)
echo "[INFO] Carregando módulos essenciais ..."
for mod in "\${ESSENTIALS[@]}"; do
    load_module_if_available "\$mod" --v
done

# -----------------------
# Módulos adicionais
# -----------------------
PACKAGES=(
  boost/1.84.0 jedi-cmake/1.4.0 python/3.10.13 c-blosc/1.21.5 libbsd/0.11.7
  qhull/2020.2 ca-certificates-mozilla/2023-05-30 libmd/1.0.4 snappy/1.1.10
  cmake/3.23.1 libxcrypt/4.4.35 sqlite/3.43.2 curl/8.4.0 nghttp2/1.57.0
  ecbuild/3.7.2 openblas/0.3.24 eigen/3.4.0 tar/1.34 gcc-runtime/9.4.0
  py-pip/23.1.2 udunits/2.2.28 gettext/0.21.1 py-pycodestyle/2.11.0
  util-linux-uuid/2.38.1 gmake/4.3 py-setuptools/63.4.3 zlib-ng/2.1.5
  gsl-lite/0.37.0 py-wheel/0.41.2 zstd/1.5.2
)

echo "[INFO] Carregando módulos padrão..."
for pkg in "\${PACKAGES[@]}"; do
    load_module_if_available "\$pkg"
done

MPI_DEPENDENTS=(
  atlas/0.36.0 fftw/3.3.10 nccmp/1.9.0.1 parallelio/2.6.2
  eckit/1.24.5 fiat/1.2.0 netcdf-c/4.9.2 ectrans/1.2.0 netcdf-cxx/4.3.1
  gptl/8.1.1 netcdf-fortran/4.6.1 fckit/0.11.0 hdf5/1.14.3 parallel-netcdf/1.12.3
)

echo "[INFO] Carregando módulos MPI dependentes..."
for mpi_mod in "\${MPI_DEPENDENTS[@]}"; do
    load_module_if_available "\$mpi_mod"
done

# -----------------------
# LD_LIBRARY_PATH
# -----------------------
echo "[INFO] Atualizando LD_LIBRARY_PATH..."
export NETCDF_DIR=\$(spack location -i netcdf-c)
export NETCDF_CXX_DIR=\$(spack location -i netcdf-cxx4)
export HDF5_DIR=\$(spack location -i hdf5)

if [ -d "\$NETCDF_DIR" ]; then
    export LD_LIBRARY_PATH="\$NETCDF_DIR/lib:\$LD_LIBRARY_PATH"
fi

if [ -d "\$NETCDF_CXX_DIR" ]; then
    export LD_LIBRARY_PATH="\$NETCDF_CXX_DIR/lib:\$LD_LIBRARY_PATH"
fi

if [ -d "\$HDF5_DIR" ]; then
    export LD_LIBRARY_PATH="\$HDF5_DIR/lib:\$LD_LIBRARY_PATH"
fi

echo "[INFO] Ambiente '\$ENV_NAME' ativado e configurado com sucesso!"
end=\$(date +%s)
echo "[INFO] Tempo total de inicialização: \$((end - start)) segundos"

# Restaura o diretório anterior
cd "\$ORIGINAL_DIR"

EOF
ls -l $SPACK_ENV_DIR/start_spack_bundle.sh
chmod +x $SPACK_ENV_DIR/start_spack_bundle.sh

echo "[INFO] Para ativar o ambiente, execute:"
echo "       source $SPACK_ENV_DIR/start_spack_bundle.sh"

end=$(date +%s)
echo "[INFO] Todos os testes foram concluídos com sucesso."
echo "[INFO] Tempo total de execução: $((end - start)) segundos"

