#!/bin/bash

# ===============================
# Instalação e Testes do Spack-Stack na Egeon
# ===============================
set -e

start=$(date +%s)

# CONFIGURAÇÕES
export SPACK_VERSION="${1:-1.7.0}"
export SPACK_DIR="/mnt/beegfs/$USER/spack-stack_$SPACK_VERSION"
export EGEON_CONFIG_REPO="/mnt/beegfs/$USER/spack-egeon"
export ENV_NAME="mpas-bundle"
export MODULE_CORE_PATH="$SPACK_DIR/envs/$ENV_NAME/install/modulefiles/Core"

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

NETCDF_LIB=$(spack location -i netcdf-c)/lib
HDF5_LIB=$(spack location -i hdf5)/lib

if [ -d "$NETCDF_LIB" ]; then
    export LD_LIBRARY_PATH="$NETCDF_LIB:$LD_LIBRARY_PATH"
fi

if [ -d "$HDF5_LIB" ]; then
    export LD_LIBRARY_PATH="$HDF5_LIB:$LD_LIBRARY_PATH"
fi

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

gcc test_netcdf.c -o test_netcdf -I$NETCDF_LIB/../include -L$NETCDF_LIB -lnetcdf
./test_netcdf

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

gcc test_hdf5.c -o test_hdf5 -I$HDF5_LIB/../include -L$HDF5_LIB -lhdf5
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
echo "[INFO] Gerando script de ativação do ambiente: activate_spack_env.sh"

cat <<EOF > ~/activate_spack_env.sh
#!/bin/bash
# Script gerado automaticamente para ativar o ambiente Spack-Stack $SPACK_VERSION na máquina Egeon

export SPACK_ENV_PATH="/mnt/beegfs/$USER/spack-stack_$SPACK_VERSION/envs/mpas-bundle"
export MODULE_CORE_PATH="\$SPACK_ENV_PATH/install/modulefiles/Core"

# Ativa o ambiente Spack
spack env activate "\$SPACK_ENV_PATH"

# Usa e carrega os meta-módulos
module use "\$MODULE_CORE_PATH"
module load stack-gcc/9.4.0
module load stack-openmpi/4.1.1
module load stack-python/3.10.13

# Garante que bibliotecas sejam encontradas
export LD_LIBRARY_PATH=\$(spack location -i netcdf-c)/lib:\$(spack location -i hdf5)/lib:\$LD_LIBRARY_PATH

echo "[INFO] Ambiente Spack ativado com sucesso!"
EOF

chmod +x ~/activate_spack_env.sh

echo "[INFO] Para ativar o ambiente, execute:"
echo "       source ~/activate_spack_env.sh"

end=$(date +%s)
echo "[INFO] Todos os testes foram concluídos com sucesso."
echo "[INFO] Tempo total de execução: $((end - start)) segundos"

