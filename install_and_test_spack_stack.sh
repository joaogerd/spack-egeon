#!/bin/bash

# ===============================
# 🧭 Instalação e Testes do Spack-Stack 1.7.0 na Egeon
# ===============================
set -e

# ⚙️ CONFIGURAÇÕES
export SPACK_DIR="/mnt/beegfs/$USER/spack-stack_1.7.0"
export EGEON_CONFIG_REPO="/mnt/beegfs/$USER/spack-egeon"
export ENV_NAME="mpas-bundle"
export MODULE_CORE_PATH="$SPACK_DIR/envs/$ENV_NAME/install/modulefiles/Core"

echo "📁 Preparando diretório de trabalho em /mnt/beegfs/$USER"
cd /mnt/beegfs/$USER

# Clona o repositório de configuração, se ainda não existir
if [ ! -d "$EGEON_CONFIG_REPO" ]; then
    echo "📥 Clonando repositório de configuração spack-egeon..."
    git clone https://github.com/joaogerd/spack-egeon.git
fi

echo "📦 Clonando Spack-Stack 1.7.0..."
git clone https://github.com/JCSDA/spack-stack -b release/1.7.0 spack-stack_1.7.0 --recurse-submodules

echo "📥 Carregando módulo GCC..."
module load gnu9

echo "🔧 Inicializando Spack-Stack..."
cd "$SPACK_DIR"
source setup.sh

echo "📁 Copiando arquivos de configuração do site e template..."
cp -r "$EGEON_CONFIG_REPO/configs/sites/egeon" configs/sites/
cp -r "$EGEON_CONFIG_REPO/configs/templates/mpas-bundle" configs/templates/

echo "🛠️ Verificando compilers.yaml..."
COMPILERS_YAML="configs/sites/egeon/compilers.yaml"
grep -q "flags:" "$COMPILERS_YAML" || echo "      flags: {}" >> "$COMPILERS_YAML"

echo "🌱 Criando ambiente '$ENV_NAME'..."
spack stack create env --name=$ENV_NAME --template=mpas-bundle --site=egeon
cd envs/$ENV_NAME

echo "⚡ Ativando ambiente..."
spack env activate .

echo "🔍 Concretizando ambiente..."
spack concretize 2>&1 | tee log.concretize

echo "🚀 Instalando pacotes..."
spack install 2>&1 | tee log.install

echo "🔗 Configurando meta-módulos..."
spack stack setup-meta-modules 2>&1 | tee log.metamodules

echo "🧰 Carregando módulos..."
module use "$MODULE_CORE_PATH"
module load stack-gcc/9.4.0
module load openmpi/4.1.1 || true

echo "✅ Ambiente instalado. Iniciando testes..."

# Diretório temporário para testes
mkdir -p ~/spack_tests && cd ~/spack_tests

#######################
# 🔬 Teste NetCDF
#######################
echo "🔬 Testando NetCDF..."
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

NETCDF_INC=$(spack location -i netcdf-c)/include
NETCDF_LIB=$(spack location -i netcdf-c)/lib

gcc test_netcdf.c -o test_netcdf -I$NETCDF_INC -L$NETCDF_LIB -lnetcdf
./test_netcdf

#######################
# 🧪 Teste HDF5
#######################
echo "🧪 Testando HDF5..."
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

HDF5_INC=$(spack location -i hdf5)/include
HDF5_LIB=$(spack location -i hdf5)/lib

gcc test_hdf5.c -o test_hdf5 -I$HDF5_INC -L$HDF5_LIB -lhdf5
./test_hdf5

#######################
# 🚀 Teste MPI
#######################
echo "🚀 Testando OpenMPI..."
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

#######################
# 🧹 Verificação final
#######################
echo "📦 Verificando arquivos gerados..."
ncdump test.nc | head -n 5 || echo "Erro ao usar ncdump"
h5dump test.h5 | head -n 5 || echo "Erro ao usar h5dump"

echo "🎉 Todos os testes foram concluídos!"

