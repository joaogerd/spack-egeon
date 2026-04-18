# Instalação manual e validação do ambiente

Este documento descreve o fluxo manual para criar um ambiente do `spack-stack` a partir dos arquivos de `site` e `template` deste repositório.

Ele é útil para:

- depuração;
- validação de um novo site;
- revisão de concretização;
- análise mais fina de erros de módulos, wrappers e externals.

---

## Pré-requisitos

Antes de iniciar, confirme:

- acesso a um diretório de trabalho estável, como `/mnt/beegfs/$USER`;
- `git` disponível;
- sistema de módulos funcional;
- módulo base do compilador disponível na máquina;
- acesso ao GitHub;
- permissões para instalação no espaço de trabalho escolhido.

---

## Passo 0 — limpeza recomendada

Se houver tentativas anteriores de instalação, recomenda-se limpar caches e configurações do usuário:

```bash
rm -rf ~/.cache/spack
rm -rf ~/.spack
```

Essa limpeza é especialmente útil quando houve mudanças em:

- `compilers.yaml`
- `packages.yaml`
- `modules.yaml`
- `config.yaml`
- `spack.yaml` do template

---

## Passo 1 — preparar diretório de trabalho

```bash
cd /mnt/beegfs/$USER
```

---

## Passo 2 — clonar o spack-stack

Exemplo com a release 1.7.0:

```bash
git clone https://github.com/JCSDA/spack-stack -b release/1.7.0 spack-stack_1.7.0 --recurse-submodules
```

Depois, carregue o módulo base do compilador esperado na máquina.

Exemplo na EGEON:

```bash
module load gnu9
```

Entre no diretório clonado e inicialize o Spack:

```bash
cd spack-stack_1.7.0
source setup.sh
```

---

## Passo 3 — clonar este repositório

```bash
git clone https://github.com/GAD-DIMNT-CPTEC/spack-stack-inpe.git
```

---

## Passo 4 — copiar site e template

Exemplo para `site=egeon` e `template=mpas-bundle`:

```bash
cp -r ../spack-stack-inpe/configs/sites/egeon configs/sites/
cp -r ../spack-stack-inpe/configs/templates/mpas-bundle configs/templates/
```

---

## Passo 5 — revisar arquivos do site

Revise especialmente:

- `configs/sites/egeon/compilers.yaml`
- `configs/sites/egeon/packages.yaml`
- `configs/sites/egeon/modules.yaml`
- `configs/sites/egeon/config.yaml`

### Observação importante sobre `compilers.yaml`

Garanta que a chave `flags` exista no bloco do compilador.

Exemplo esperado:

```yaml
compilers:
  - compiler:
      spec: gcc@9.4.0
      paths:
        cc: /path/to/gcc
        cxx: /path/to/g++
        f77: /path/to/gfortran
        fc: /path/to/gfortran
      flags: {}
```

A ausência de `flags: {}`` pode causar problemas no `spack concretize`.

---

## Passo 6 — criar o ambiente

```bash
spack stack create env --name=mpas-bundle --template=mpas-bundle --site=egeon
cd envs/mpas-bundle
```

Ative o ambiente:

```bash
spack env activate .
```

---

## Passo 7 — concretizar e instalar

```bash
spack concretize 2>&1 | tee log.concretize
spack install --source 2>&1 | tee log.install
spack module lmod refresh -y 2>&1 | tee log.modules
spack stack setup-meta-modules 2>&1 | tee log.metamodules
```

---

## Uso dos módulos após a instalação

Depois da instalação, o caminho de módulos do ambiente pode ser incluído com:

```bash
module use /mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/modulefiles/Core
```

Em seguida, carregue os meta-módulos principais conforme disponibilidade.

Exemplo comum:

```bash
module load stack-gcc/9.4.0
module load stack-openmpi/4.1.1
```

---

## Verificações básicas

### Verificar o ambiente

```bash
spack env activate .
spack find
```

### Verificar logs principais

```bash
ls -1 log.concretize log.install log.modules log.metamodules
```

### Verificar diretório de módulos

```bash
ls -R install/modulefiles | head
```

---

## Testes funcionais sugeridos

Antes dos testes, exporte os diretórios das bibliotecas principais:

```bash
export NETCDF_DIR=$(spack location -i netcdf-c)
export NETCDF_CXX_DIR=$(spack location -i netcdf-cxx4)
export HDF5_DIR=$(spack location -i hdf5)

if [ -d "$NETCDF_DIR" ]; then
    export LD_LIBRARY_PATH="$NETCDF_DIR/lib:$LD_LIBRARY_PATH"
fi

if [ -d "$NETCDF_CXX_DIR" ]; then
    export LD_LIBRARY_PATH="$NETCDF_CXX_DIR/lib:$LD_LIBRARY_PATH"
fi

if [ -d "$HDF5_DIR" ]; then
    export LD_LIBRARY_PATH="$HDF5_DIR/lib:$LD_LIBRARY_PATH"
fi
```

### Teste NetCDF

```bash
cat <<EOF > test_netcdf.c
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

gcc test_netcdf.c -o test_netcdf -I$NETCDF_DIR/include -L$NETCDF_DIR/lib -lnetcdf
./test_netcdf
```

### Teste NetCDF-C++

```bash
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
```

### Teste HDF5

```bash
cat <<EOF > test_hdf5.c
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

mpicc test_hdf5.c -o test_hdf5 -I$HDF5_DIR/include -L$HDF5_DIR/lib -lhdf5
./test_hdf5
```

### Teste MPI

```bash
cat <<EOF > test_mpi.c
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
```

### Validar arquivos gerados

```bash
ncdump test.nc | head -n 5
h5dump test.h5 | head -n 5
```

---

## Problemas comuns

### `flags` ausente no `compilers.yaml`
Pode causar falhas no `spack concretize`.

### Falhas no `setup-meta-modules`
Revisar ativação do ambiente e coerência do site.

### Bibliotecas dinâmicas não encontradas
Complemente `LD_LIBRARY_PATH` com os caminhos de `netcdf-c`, `netcdf-cxx4` e `hdf5`.

### Problemas com MPI ou wrappers
Validar o módulo base carregado, meta-módulos e a consistência do `packages.yaml` do site.

---

## Quando voltar ao fluxo automatizado

Se o fluxo manual funcionou, o caminho normal para uso recorrente deve ser o automatizado:

- `install_and_test_spack_stack.sh`
- `start_spack_bundle.sh`

Para isso, veja:

- [`automation.md`](automation.md)
