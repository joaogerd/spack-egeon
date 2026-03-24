# spack-stack-inpe

Repositório de configurações institucionais do INPE para uso com o **spack-stack**, com foco atual na máquina **EGEON**.

Atualmente, este repositório disponibiliza as configurações de site e o template necessários para a criação do ambiente **mpas-bundle** na **EGEON**. A configuração para a máquina **JACI** está em desenvolvimento e será incorporada futuramente à mesma estrutura.

## Sumário

- [Visão geral](#visao-geral)
- [Objetivo](#objetivo)
- [Escopo atual do repositório](#escopo-atual-do-repositorio)
- [Estrutura do repositório](#estrutura-do-repositorio)
- [Requisitos](#requisitos)
- [Fluxo rápido](#fluxo-rapido)
- [Instalação manual](#instalacao-manual)
  - [0. Pré-requisitos](#0-pre-requisitos)
  - [1. Preparação do diretório de trabalho](#1-preparacao-do-diretorio-de-trabalho)
  - [2. Limpeza de cache e configuração local](#2-limpeza-de-cache-e-configuracao-local)
  - [3. Clone do spack-stack](#3-clone-do-spack-stack)
  - [4. Clone deste repositório e cópia das configurações](#4-clone-deste-repositorio-e-copia-das-configuracoes)
  - [5. Verificação do `compilers.yaml`](#5-verificacao-do-compilersyaml)
  - [6. Criação e ativação do ambiente](#6-criacao-e-ativacao-do-ambiente)
  - [7. Concretização, instalação e meta-módulos](#7-concretizacao-instalacao-e-meta-modulos)
- [Uso dos módulos após a instalação](#uso-dos-modulos-apos-a-instalacao)
- [Indicadores de sucesso](#indicadores-de-sucesso)
- [Verificação pós-instalação](#verificacao-pos-instalacao)
- [Testes funcionais](#testes-funcionais)
  - [Teste NetCDF](#teste-netcdf)
  - [Teste NetCDF-C++](#teste-netcdf-c)
  - [Teste HDF5](#teste-hdf5)
  - [Teste OpenMPI](#teste-openmpi)
- [Script automatizado](#script-automatizado)
- [Ativação do ambiente após a instalação](#ativacao-do-ambiente-apos-a-instalacao)
- [Ambiente compartilhado para o grupo](#ambiente-compartilhado-para-o-grupo)
- [Boas práticas de execução](#boas-praticas-de-execucao)
- [Problemas comuns e soluções](#problemas-comuns-e-solucoes)
- [Informações que ainda precisam ser complementadas](#informacoes-que-ainda-precisam-ser-complementadas)
- [Licença](#licenca)

<a name="visao-geral"></a>
## Visão geral

O **spack-stack-inpe** concentra arquivos de configuração institucionais do INPE para uso com o **spack-stack**, permitindo adaptar a instalação padrão ao ambiente computacional local.

No estado atual do projeto, o repositório contém a configuração da **EGEON** e o template de ambiente **mpas-bundle**. A configuração da **JACI** está em preparação e será integrada futuramente.

<a name="objetivo"></a>
## Objetivo

Este repositório tem como objetivo:

- padronizar a configuração do **spack-stack** no ambiente institucional do INPE;
- reduzir erros recorrentes de instalação e concretização;
- facilitar a criação e reutilização do ambiente **mpas-bundle**;
- registrar um procedimento reprodutível de instalação, validação e ativação do ambiente;
- servir de base para projetos científicos e técnicos que dependam desse ecossistema, como o **MPAS-JEDI**.



<a name="escopo-atual-do-repositorio"></a>
## Escopo atual do repositório

No momento, o repositório contém:

- configurações de site para a **EGEON**;
- template de ambiente **mpas-bundle**;
- documentação do processo manual de instalação;
- referência ao fluxo automatizado de instalação e testes.

### Observação importante

- A documentação manual abaixo usa como referência o **spack-stack 1.7.0**.
- O fluxo automatizado permite parametrizar a versão do **spack-stack** por meio da variável de ambiente `SPACK_VERSION`.
- A configuração da **JACI** ainda não está incluída nesta versão do repositório.

<a name="estrutura-do-repositorio"></a>
## Estrutura do repositório

A estrutura esperada deste repositório é:

```text
configs/
├── sites/
│   └── egeon/
└── templates/
    └── mpas-bundle/
````

### Descrição dos diretórios

* `configs/sites/egeon/`: arquivos de configuração específicos da máquina EGEON;
* `configs/templates/mpas-bundle/`: template do ambiente `mpas-bundle`.

Quando a configuração da JACI estiver pronta, a estrutura do diretório `configs/sites/` deverá ser expandida de forma consistente.

<a name="requisitos"></a>
## Requisitos

Antes de iniciar a instalação, confirme os seguintes requisitos:

* acesso ao sistema de arquivos em `/mnt/beegfs/$USER`;
* `git` disponível no ambiente;
* sistema de módulos em funcionamento;
* módulo `gnu9` disponível na EGEON;
* acesso ao GitHub para clonagem dos repositórios;
* permissões adequadas para criar diretórios e instalar pacotes no espaço de trabalho do usuário.

<a name="fluxo-rapido"></a>
## Fluxo rápido

Para usuários experientes, o fluxo mínimo de instalação manual na **EGEON**, usando o **spack-stack 1.7.0**, é o seguinte:

```bash
cd /mnt/beegfs/$USER

rm -rf ~/.cache/spack ~/.spack

git clone https://github.com/JCSDA/spack-stack -b release/1.7.0 spack-stack_1.7.0 --recurse-submodules
git clone https://github.com/GAD-DIMNT-CPTEC/spack-stack-inpe.git

module load gnu9

cd spack-stack_1.7.0
source setup.sh

cp -r ../spack-stack-inpe/configs/sites/egeon configs/sites/
cp -r ../spack-stack-inpe/configs/templates/mpas-bundle configs/templates/

spack stack create env --name=mpas-bundle --template=mpas-bundle --site=egeon

cd envs/mpas-bundle
spack env activate .

spack concretize 2>&1 | tee log.concretize
spack install --source 2>&1 | tee log.install
spack module lmod refresh -y 2>&1 | tee log.modules
spack stack setup-meta-modules 2>&1 | tee log.metamodules
```

Após a instalação, para utilizar os módulos gerados:

```bash
module use /mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/modulefiles/Core
module load stack-gcc/9.4.0
```

> **Importante:** este fluxo rápido refere-se ao procedimento manual atual com foco na **EGEON**. Para a instalação automatizada e para a seleção parametrizada da versão do Spack-Stack, utilize o script apropriado.

<a name="instalacao-manual"></a>
## Instalação manual

O procedimento abaixo descreve a instalação manual do ambiente com base no **spack-stack 1.7.0**.

<a name="0-pre-requisitos"></a>
### 0. Pré-requisitos

Antes de iniciar, certifique-se de que:

- o comando `module` está disponível no sistema;
- o compilador/base esperada para o site `egeon` pode ser carregada com `module load gnu9`;
- o `git` está disponível;
- há acesso ao filesystem compartilhado em `/mnt/beegfs/$USER`;
- o repositório institucional `spack-stack-inpe` está acessível.
- 
<a name="1-preparacao-do-diretorio-de-trabalho"></a>
### 1. Preparação do diretório de trabalho

Recomenda-se executar todo o procedimento em `beegfs`:

```bash
cd /mnt/beegfs/$USER
```



<a name="2-limpeza-de-cache-e-configuracao-local"></a>
### 2. Limpeza de cache e configuração local

Antes de iniciar, recomenda-se limpar caches e configurações locais anteriores do Spack:

```bash
rm -rf ~/.cache/spack
rm -rf ~/.spack
```

> **Atenção:** esse procedimento remove caches e configurações locais do Spack do usuário atual. Recomenda-se especialmente quando houve tentativas anteriores de instalação ou alterações nos arquivos de configuração.

<a name="3-clone-do-spack-stack"></a>
### 3. Clone do spack-stack

Clone a versão de referência do **spack-stack** com submódulos:

```bash
git clone https://github.com/JCSDA/spack-stack -b release/1.7.0 spack-stack_1.7.0 --recurse-submodules
```

Carregue o compilador disponível na EGEON:

```bash
module load gnu9
```

Entre no diretório clonado e inicialize o ambiente:

```bash
cd spack-stack_1.7.0
source setup.sh
```

<a name="4-clone-deste-repositorio-e-copia-das-configuracoes"></a>
### 4. Clone deste repositório e cópia das configurações

Clone este repositório:

```bash
git clone https://github.com/GAD-DIMNT-CPTEC/spack-stack-inpe.git
```

Em seguida, copie os arquivos de configuração de site e o template para dentro da árvore do `spack-stack`:

```bash
cp -r spack-stack-inpe/configs/sites/egeon spack-stack_1.7.0/configs/sites/
cp -r spack-stack-inpe/configs/templates/mpas-bundle spack-stack_1.7.0/configs/templates/
```

> **Importante:** atualmente este repositório disponibiliza apenas a configuração da **EGEON**.



<a name="5-verificacao-do-compilersyaml"></a>
### 5. Verificação do `compilers.yaml`

Abra o arquivo:

```text
spack-stack_1.7.0/configs/sites/egeon/compilers.yaml
```

Verifique se a chave `flags` está presente dentro da definição do compilador.

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

A ausência de `flags: {}` pode causar falhas no comando `spack concretize`.



<a name="6-criacao-e-ativacao-do-ambiente"></a>
### 6. Criação e ativação do ambiente

Crie o ambiente `mpas-bundle` com o template e o site configurados:

```bash
spack stack create env --name=mpas-bundle --template=mpas-bundle --site=egeon
cd envs/mpas-bundle
```

Ative o ambiente criado:

```bash
spack env activate .
```

<a name="7-concretizacao-instalacao-e-meta-modulos"></a>
### 7. Concretização, instalação e meta-módulos

Concretize o ambiente e registre a saída em log:

```bash
spack concretize 2>&1 | tee log.concretize
```

Instale os pacotes:

```bash
spack install  --source 2>&1 | tee log.install
```
> A opção `--source` também preserva os códigos-fonte instalados, o que pode ser útil para rastreabilidade e depuração.

Gere ou atualize os módulos Lmod do ambiente:

```bash
spack module lmod refresh -y 2>&1 | tee log.modules
```
> Esse passo atualiza os módulos Lmod correspondentes aos pacotes instalados no ambiente.

Gere os meta-módulos:

```bash
spack stack setup-meta-modules 2>&1 | tee log.metamodules
```
> Os meta-módulos facilitam o carregamento posterior do ambiente, organizando de forma mais simples o uso dos módulos gerados.


<a name="uso-dos-modulos-apos-a-instalacao"></a>
## Uso dos módulos após a instalação

Para utilizar os módulos compilados:

```bash
module use /mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/modulefiles/Core
module load stack-gcc/9.4.0
```

Para listar os módulos disponíveis:

```bash
module avail
```

Alguns módulos adicionais ficam disponíveis apenas após carregar o OpenMPI:

```bash
module load openmpi/4.1.1
```



<a name="indicadores-de-sucesso"></a>
## Indicadores de sucesso

Os principais sinais de que a instalação ocorreu corretamente são:

1. Mensagens de sucesso nos logs, por exemplo:

   ```text
   Successfully installed <package-name>
   ```

2. Criação do diretório de módulos no ambiente instalado.

3. Geração dos arquivos de log:

   * `log.concretize`
   * `log.install`
   * `log.metamodules`

4. Reconhecimento adequado de dependências externas e módulos carregados.



<a name="verificacao-pos-instalacao"></a>
## Verificação pós-instalação

Após a instalação, recomenda-se executar:

```bash
spack env activate .
spack find
ls -1 log.concretize log.install log.metamodules
```

Se necessário, consulte logs adicionais do Spack em:

```text
<spack-stack-dir>/cache/log/
```



<a name="testes-funcionais"></a>
## Testes funcionais

Os testes abaixo ajudam a validar bibliotecas críticas do ambiente.

Antes dos testes, exporte os caminhos das bibliotecas principais:

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



<a name="teste-netcdf"></a>
### Teste NetCDF

Crie o arquivo de teste:

```bash
cat <<EOF > test_netcdf.c
#include <netcdf.h>
#include <stdio.h>

int main() {
    int ncid, retval;
    const char *filename = "test.nc";

    if ((retval = nc_create(filename, NC_CLOBBER, &ncid)))
        return retval;

    if ((retval = nc_close(ncid)))
        return retval;

    if ((retval = nc_open(filename, NC_NOWRITE, &ncid)))
        return retval;

    printf("NetCDF test passed. File '%s' created and opened successfully.\n", filename);
    return 0;
}
EOF
```

Compile e execute:

```bash
gcc test_netcdf.c -o test_netcdf -I$NETCDF_DIR/include -L$NETCDF_DIR/lib -lnetcdf
./test_netcdf
```

Saída esperada:

```text
NetCDF test passed. File 'test.nc' created and opened successfully.
```



<a name="teste-netcdf-c"></a>
### Teste NetCDF-C++

Crie o arquivo de teste:

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
```

Compile e execute:

```bash
g++ test_netcdf_cxx.cpp -o test_netcdf_cxx \
    -I$NETCDF_CXX_DIR/include -L$NETCDF_CXX_DIR/lib \
    -I$NETCDF_DIR/include -L$NETCDF_DIR/lib \
    -lnetcdf_c++4
./test_netcdf_cxx
```

Saída esperada:

```text
NetCDF-C++ test passed. File 'test_cxx.nc' created successfully.
```



<a name="teste-hdf5"></a>
### Teste HDF5

Crie o arquivo de teste:

```bash
cat <<EOF > test_hdf5.c
#include "hdf5.h"
#include <stdio.h>

int main() {
    hid_t file_id;
    herr_t status;

    file_id = H5Fcreate("test.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    if (file_id < 0) {
        printf("Error creating HDF5 file.\n");
        return 1;
    }

    status = H5Fclose(file_id);
    if (status < 0) {
        printf("Error closing HDF5 file.\n");
        return 1;
    }

    printf("HDF5 test passed. File 'test.h5' created successfully.\n");
    return 0;
}
EOF
```

Compile e execute:

```bash
gcc test_hdf5.c -o test_hdf5 -I$HDF5_DIR/include -L$HDF5_DIR/lib -lhdf5
./test_hdf5
```

Saída esperada:

```text
HDF5 test passed. File 'test.h5' created successfully.
```



<a name="teste-openmpi"></a>
### Teste OpenMPI

Crie o arquivo de teste:

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
```

Compile e execute:

```bash
mpicc test_mpi.c -o test_mpi
mpirun -np 4 ./test_mpi
```

Saída esperada:

```text
Hello from rank 0 of 4.
Hello from rank 1 of 4.
Hello from rank 2 of 4.
Hello from rank 3 of 4.
```



<a name="script-automatizado"></a>
## Script automatizado

O fluxo automatizado executa, de forma encadeada, as etapas de:

* limpeza de cache e variáveis de ambiente;
* clone do `spack-stack`;
* cópia das configurações de site e template;
* criação e ativação do ambiente;
* concretização e instalação;
* geração de meta-módulos;
* configuração do ambiente para testes;
* testes de NetCDF, NetCDF-C++, HDF5 e OpenMPI;
* geração de um script auxiliar de ativação.

### Observações importantes sobre a automação

1. O passo a passo manual deste README usa como exemplo o **spack-stack 1.7.0**.
2. No fluxo automatizado, a versão do Spack-Stack pode ser parametrizada por `SPACK_VERSION`.
3. O script atual ainda contém referências legadas ao nome `spack-egeon`; essa nomenclatura deverá ser atualizada para refletir o nome oficial **spack-stack-inpe**.

### Exemplo conceitual de uso

Quando o script estiver ajustado para o nome definitivo do repositório, a ideia é permitir algo como:

```bash
export SPACK_VERSION=1.7.0
./install_and_test_spack_stack.sh
```

ou equivalente ao mecanismo de parametrização adotado na versão final do script.



<a name="ativacao-do-ambiente-apos-a-instalacao"></a>
## Ativação do ambiente após a instalação

Ao final da automação, pode ser gerado um script auxiliar chamado `start_spack_bundle.sh`, utilizado para ativar corretamente o ambiente instalado.

Exemplo de ativação:

```bash
source $HOME/.spack/mpas-bundle/start_spack_bundle.sh
```

Esse script deve ser usado para:

* ativar o ambiente `mpas-bundle`;
* adicionar o caminho correto de módulos;
* carregar módulos essenciais;
* complementar variáveis de ambiente necessárias, como `LD_LIBRARY_PATH`.

> **Importante:** esse passo deve ser executado sempre que o ambiente instalado for utilizado em uma nova sessão.



<a name="ambiente-compartilhado-para-o-grupo"></a>
## Ambiente compartilhado para o grupo

Para evitar instalações duplicadas por usuário, recomenda-se utilizar um ambiente compartilhado já instalado em diretório comum, por exemplo:

```bash
/mnt/beegfs/das.group/spack-stack_1.7.0/envs/mpas-bundle/
```

Se houver um script de ativação compartilhado, o uso esperado é:

```bash
source /mnt/beegfs/das.group/spack-envs/mpas-bundle/start_spack_bundle.sh
```

Benefícios dessa abordagem:

* uniformidade entre usuários;
* redução de consumo de disco;
* menor risco de divergência entre ambientes;
* maior facilidade para uso colaborativo.



<a name="boas-praticas-de-execucao"></a>
## Boas práticas de execução

* execute a instalação em um diretório estável no `beegfs`;
* registre a saída dos comandos principais em arquivos de log;
* revise `compilers.yaml` antes da concretização;
* valide o ambiente com testes mínimos antes de iniciar compilações maiores;
* use um ambiente compartilhado quando a equipe precisar trabalhar com a mesma pilha de software;
* mantenha documentadas a versão do `spack-stack`, o compilador utilizado e o conjunto de módulos carregados.



<a name="problemas-comuns-e-solucoes"></a>
## Problemas comuns e soluções

### 1. Erro relacionado a `flags` ausente no `compilers.yaml`

**Descrição:** o `spack concretize` pode falhar se a chave `flags` estiver ausente.

**Solução:** adicione:

```yaml
flags: {}
```



### 2. Falha no `spack stack setup-meta-modules`

**Descrição:** pode ocorrer por ativação incorreta do ambiente ou configuração inconsistente do sistema de módulos.

**Solução:** confirme:

* se o ambiente foi ativado corretamente;
* se os arquivos do site foram copiados para os diretórios esperados;
* se o `MODULEPATH` está coerente com a instalação realizada.



### 3. Bibliotecas dinâmicas não encontradas em tempo de execução

**Descrição:** binários de teste podem falhar com mensagens relacionadas a `libnetcdf.so` ou `libhdf5.so`.

**Solução:** complemente `LD_LIBRARY_PATH` com os caminhos retornados por:

```bash
spack location -i netcdf-c
spack location -i netcdf-cxx4
spack location -i hdf5
```



### 4. Problemas com OpenMPI e ambiente local

**Descrição:** algumas combinações entre MPI, módulos locais e ambiente do usuário podem causar comportamento inconsistente.

**Solução:** priorize os módulos previstos no ambiente instalado e valide o teste MPI antes de seguir para compilações maiores.



<a name="informacoes-que-ainda-precisam-ser-complementadas"></a>
## Informações que ainda precisam ser complementadas

Os itens abaixo ainda devem ser confirmados ou ajustados no repositório:

1. caminho e versão final do script automatizado após a renomeação definitiva para `spack-stack-inpe`;
2. inclusão futura da configuração da **JACI**;
3. definição formal da licença do projeto;
4. confirmação do local definitivo do ambiente compartilhado e do script de ativação compartilhado;
5. sincronização completa entre o README e a versão final do script automatizado.



<a name="licenca"></a>
## Licença

**Informação ainda não definida neste README.**


