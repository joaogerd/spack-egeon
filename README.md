# 🧭 Receita para Configurar o Spack-Stack na Máquina Egeon

Esta receita descreve todas as etapas necessárias para instalar e configurar o **Spack-Stack 1.7.0** na máquina **Egeon**, levando em conta o ambiente de módulos e possíveis erros comuns.

---

# 🗂️ Índice

- [⚠️ Atenção](#atencao)
- [🧹 Passo 0: Limpando o Cache](#passo0)
- [📦 Passo 1: Clonando o Repositório do Spack-Stack](#passo1)
- [⚙️ Passo 2: Configurando os Arquivos do Site](#passo2)
- [🚀 Passo 3: Criando e Ativando o Ambiente](#passo3)
- [📦 Passo 4: Concretizando e Instalando](#passo4)
- [🧰 Utilização dos Módulos](#modulos)
- [🧰 Possíveis Erros e Soluções](#erros)
- [✅ Indicadores de Sucesso](#indicadores)
- [🔎 Pontos de Observação](#observacao)
- [🧪 Verificação Pós-Instalação](#verificacao)
- [🧪 Testes](#testes)
- [📜 Script Automatizado](#script)
- [⚙️ Ativando o Ambiente](#ativando)


---
<a name="atencao"></a>
## ⚠️ Atenção

Certifique-se de estar no disco **beegfs**:

```bash
cd /mnt/beegfs/$USER
```
---
<a name="passo0"></a>
## 🧹 Passo 0: Limpando o Cache (Altamente Recomendado)

Antes de iniciar qualquer etapa de instalação, **recomenda-se limpar o cache do Spack para evitar conflitos ou erros de configuração anteriores.**

```bash
rm -rf ~/.cache/spack
rm -rf ~/.spack
```

> ⚠️ **Atenção:** Essa limpeza remove caches e configurações locais do Spack. Faça isso especialmente se:
> - Você já tentou instalar o ambiente antes;
> - Houve mudanças nos arquivos de configuração (`compilers.yaml`, `packages.yaml`);
> - Está enfrentando erros inesperados durante `spack concretize` ou `spack install`.

---

<a name="passo1"></a>
## 📦 Passo 1: Clonando o Repositório do Spack-Stack

Comece clonando a versão correta do Spack-Stack com os submódulos:

```bash
git clone https://github.com/JCSDA/spack-stack -b release/1.7.0 spack-stack_1.7.0 --recurse-submodules
```

Após o clone, carregue o módulo do GCC já existente na Egeon:

```bash
module load gnu9
```

Em seguida, entre no diretório do Spack-Stack e execute o script de configuração inicial:

```bash
cd spack-stack_1.7.0
source setup.sh
```
---
<a name="passo2"></a>
<a name="passo2"></a>
## ⚙️ Passo 2: Configurando os Arquivos do Site

As configurações do site **Egeon** e o template `mpas-bundle` estão agora disponíveis diretamente no repositório:

📁 [https://github.com/joaogerd/spack-egeon](https://github.com/joaogerd/spack-egeon)

Clone o repositório:

```bash
git clone https://github.com/joaogerd/spack-egeon.git
```

Depois de clonado, os arquivos de configuração estarão no diretório `spack-egeon/configs`. Copie-os para a pasta correta do Spack-Stack que você clonou:

```bash
cp -r spack-egeon/configs/sites/egeon spack-stack_1.7.0/configs/sites/
cp -r spack-egeon/configs/templates/mpas-bundle spack-stack_1.7.0/configs/templates/
```

### 🔧 Verificação do `compilers.yaml`

Abra o arquivo `configs/sites/egeon/compilers.yaml` e certifique-se de que o campo `flags` esteja presente dentro da definição do compilador, como no exemplo abaixo:

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

> ⚠️ A ausência da chave `flags` pode causar falhas no comando `spack concretize`.

Adicione o elemento `flags` no arquivo `compilers.yaml` localizado em `configs/sites/egeon`, caso ele não exista. Este passo é essencial para evitar erros na concretização do ambiente. Um exemplo de configuração seria:

```yaml
compilers:
  - compiler:
      flags: {}
```
---
<a name="passo3"></a>
## 🚀 Passo 3: Criando e Ativando o Ambiente

Com as configurações ajustadas, crie o ambiente do Spack-Stack para o MPAS-Bundle:

```bash
spack stack create env --name=mpas-bundle --template=mpas-bundle --site=egeon
cd envs/mpas-bundle
```

Ative o ambiente criado:

```bash
spack env activate .
```
---
<a name="passo4"></a>
## 📦 Passo 4: Concretizando e Instalando

Concretize o ambiente para resolver todas as dependências e registre as saídas em um log:

```bash
spack concretize 2>&1 | tee log.concretize
```

Em seguida, inicie a instalação e registre as saídas:

```bash
spack install 2>&1 | tee log.install
```

Por fim, atualize a lista de módulos instalados:

```bash
spack stack setup-meta-modules 2>&1 | tee log.metamodules
```
---
<a name="modulos"></a>
## 🧰 Utilização dos Módulos

Para utilizar os módulos compilados com o spack-stack na Egeon, execute os seguintes comandos:

```bash
module use /mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/modulefiles/Core
module load stack-gcc/9.4.0
```

Para listar novos módulos recém compilados, utilize o comando:

```bash
module avail
```

Procure pelos módulos que estiverem listados na seção:

```bash
/mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/modulefiles/gcc/9.4.0
boost/1.84.0                       (D)    jedi-cmake/1.4.0             python/3.10.13
c-blosc/1.21.5                            libbsd/0.11.7                qhull/2020.2
ca-certificates-mozilla/2023-05-30        libmd/1.0.4                  snappy/1.1.10
cmake/3.23.1                       (D)    libxcrypt/4.4.35             sqlite/3.43.2
curl/8.4.0                                nghttp2/1.57.0               stack-openmpi/4.1.1
ecbuild/3.7.2                             openblas/0.3.24       (D)    stack-python/3.10.13
eigen/3.4.0                               openmpi/4.1.1                tar/1.34
gcc-runtime/9.4.0                         py-pip/23.1.2                udunits/2.2.28
gettext/0.21.1                            py-pycodestyle/2.11.0        util-linux-uuid/2.38.1
gmake/4.3                                 py-setuptools/63.4.3         zlib-ng/2.1.5
gsl-lite/0.37.0                           py-wheel/0.41.2              zstd/1.5.2
```

Outros módulos ficarão disponíveis apenas quando o módulo `openmpi/4.1.1` for carregado:

```bash
module load openmpi/4.1.1
```

Procure pelos novos módulos na seção:

```bash
/mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/modulefiles/openmpi/4.1.1-kvlvrl3/gcc/9.4.0
atlas/0.36.0     fftw/3.3.10 (D)    nccmp/1.9.0.1                 parallelio/2.6.2
eckit/1.24.5     fiat/1.2.0         netcdf-c/4.9.2
ectrans/1.2.0    gptl/8.1.1         netcdf-fortran/4.6.1   (D)
fckit/0.11.0     hdf5/1.14.3 (D)    parallel-netcdf/1.12.3
```
---
<a name="erros"></a>
## 🧰 Possíveis Erros e Soluções

<details>
<summary>Erro: "flags" ausente no `compilers.yaml` </summary>
  
🔎 **Descrição:** Durante a execução do comando `spack concretize`, pode surgir um erro relacionado ao elemento `flags`.

✅ **Solução:** Adicione `flags: {}` no bloco do compilador.

</details>

<details>
<summary>Problemas com OpenMPI e SLURM</summary>

🔎 **Descrição:** A integração entre o OpenMPI e o SLURM da Egeon pode causar falhas se você não usar os compiladores e MPI nativos.

✅ **Solução:** Use os módulos nativos carregados com `module load`.

</details>

<details>
<summary>Erro no `setup-meta-modules`</summary>
  
🔎 **Descrição:** Mesmo após a instalação, este comando pode falhar devido a uma configuração incorreta dos módulos Lmod.

✅ **Solução:** Revise os arquivos de configuração do site e certifique-se de que o ambiente foi ativado corretamente antes de rodar o comando.

</details>

<details>
<summary>Instalação de GCC e Lmod pelo Spack</summary>

🔎 **Descrição:** Dependendo do ambiente, pode ser necessário instalar ferramentas específicas, como GCC e Lmod.

✅ **Comandos sugeridos:**
```bash
spack add gcc@8.5.0
spack install gcc@8.5.0
spack load gcc@8.5.0
spack compiler add
spack add lmod@8.7.24
spack install lmod@8.7.24
```

</details>

---


## 🧰 Conferência Final

Depois de completar todos os passos, use o ambiente configurado para compilar os módulos necessários para o MPAS-JEDI ou outros pacotes. Caso surjam dúvidas adicionais, considere entrar em contato para revisar as configurações.

É possível verificar a partir dos logs se o processo de instalação do ambiente **Spack-Stack 1.7.0** ocorreu conforme esperado. Aqui estão alguns pontos importantes para verificar:

---
<a name="indicadores"></a>
## ✅ Indicadores de Sucesso

1. **Pacotes instalados com sucesso**:
   - Cada pacote está finalizando com a mensagem:
     ```
     Successfully installed <package-name>
     ```
   - O tempo total de instalação de cada pacote está registrado, o que indica que os processos foram concluídos.

2. **Diretórios de instalação**:
   - Os pacotes estão sendo instalados no diretório esperado:
     ```
     <spack-stack-dir>/envs/mpas-bundle/install/gcc/9.4.0/<package-name>
     ```
   - Isso confirma que o prefixo do ambiente está configurado corretamente.

3. **Dependências Externas Reconhecidas**:
   - Dependências como `gmake`, `pkgconf`, e `openmpi` são reconhecidas como módulos externos, reduzindo a necessidade de compilar novamente.
---
<a name="observacao"></a>
## 🔎 Pontos de Observação

1. **Ausência de binários**:
   - Muitos pacotes foram compilados a partir do código-fonte devido à ausência de binários pré-compilados:
     ```
     No binary for <package-name> found: installing from source
     ```
   - Isso não é um problema, mas pode aumentar o tempo de instalação.

2. **Pacotes com etapas complexas**:
   - Alguns pacotes como `boost`, `cmake` e `python` levaram mais tempo para construir. Certifique-se de que esses pacotes funcionem corretamente ao executar comandos básicos relacionados (por exemplo, `python --version`, `cmake --version`).

3. **Instalação do Atlas ECMWF**:
   - O último pacote no log, `ecmwf-atlas`, também foi instalado com sucesso:
     ```
     Successfully installed ecmwf-atlas-0.36.0
     ```
---
<a name="verificacao"></a>
## 🧪 Verificação Pós-Instalação

Para garantir que tudo está correto:

1. **Verifique o ambiente do Spack**:
   - Ative o ambiente:
     ```bash
     spack env activate <env-name>
     ```
   - Certifique-se de que os pacotes instalados aparecem no ambiente:
     ```bash
     spack find
     ```

2. **Teste pacotes críticos**:
   - Execute testes simples com bibliotecas essenciais, como `netcdf`, `hdf5` e `openmpi`.

3. **Log de erros**:
   - Não há evidência de falhas nos logs. Contudo, você pode verificar mensagens de erro completas em:
     ```
     <spack-stack-dir>/cache/log/
     ```
---
<a name="testes"></a>
## 🧪 Testes

Aqui estão sugestões de testes simples para verificar o funcionamento básico das bibliotecas **NetCDF**, **HDF5** e **OpenMPI** após a instalação.

Para garantir que os executáveis consigam localizar corretamente as bibliotecas **NetCDF** e **HDF5** durante os testes, é necessário atualizar a variável `LD_LIBRARY_PATH` com os caminhos instalados pelo Spack.

Execute os comandos abaixo **após ativar o ambiente `mpas-bundle`**:

```bash
export NETCDF_LIB=$(spack location -i netcdf-c)/lib
export HDF5_LIB=$(spack location -i hdf5)/lib

if [ -d "$NETCDF_LIB" ]; then
    export LD_LIBRARY_PATH="$NETCDF_LIB:$LD_LIBRARY_PATH"
fi

if [ -d "$HDF5_LIB" ]; then
    export LD_LIBRARY_PATH="$HDF5_LIB:$LD_LIBRARY_PATH"
fi
```

Esses comandos garantem que os binários consigam encontrar as bibliotecas dinâmicas `libnetcdf.so` e `libhdf5.so`, evitando erros como:

```text
error while loading shared libraries: libhdf5.so.310: cannot open shared object file: No such file or directory
```
<details>
  
<summary>🔬 Teste NetCDF</summary>

1. **Crie um arquivo NetCDF e leia-o**:

   ```bash
   cat <<EOF > test_netcdf.c
   #include <netcdf.h>
   #include <stdio.h>

   int main() {
       int ncid, retval;
       const char *filename = "test.nc";

       // Cria um arquivo NetCDF
       if ((retval = nc_create(filename, NC_CLOBBER, &ncid)))
           return retval;

       // Fecha o arquivo
       if ((retval = nc_close(ncid)))
           return retval;

       // Abre o arquivo
       if ((retval = nc_open(filename, NC_NOWRITE, &ncid)))
           return retval;

       printf("NetCDF test passed. File '%s' created and opened successfully.\n", filename);
       return 0;
   }
   EOF
   ```

2. **Carregue o módulo stack-openmpi**:

  ```bash
  module load stack-openmpiu/4.1.1
  ```

3. **Compile o código**:

   ```bash
   gcc test_netcdf.c -o test_netcdf -I/mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/gcc/9.4.0/netcdf-c-4.9.2-upku6yf/include -L/mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/gcc/9.4.0/netcdf-c-4.9.2-upku6yf/lib -lnetcdf
   ```

4. **Execute o programa**:

   ```bash
   ./test_netcdf
   ```

5. **Saída esperada**:
   ```plaintext
   NetCDF test passed. File 'test.nc' created and opened successfully.
   ```
</details>

<details>
<summary>🧪 Teste HDF5</summary>

1. **Crie um programa para escrever e ler um arquivo HDF5**:

   ```bash
   cat <<EOF > test_hdf5.c
   #include "hdf5.h"
   #include <stdio.h>

   int main() {
       hid_t file_id;
       herr_t status;

       // Cria um arquivo HDF5
       file_id = H5Fcreate("test.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
       if (file_id < 0) {
           printf("Error creating HDF5 file.\n");
           return 1;
       }

       // Fecha o arquivo
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

2. **Carregue o módulo hdf**:

  ```bash
  module load hdf5/1.14.3
  ```

3. **Compile o código**:

   ```bash
   gcc test_hdf5.c -o test_hdf5 -I/mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/gcc/9.4.0/hdf5-1.14.3-mvutux7/include -L/mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/gcc/9.4.0/hdf5-1.14.3-mvutux7/lib -lhdf5
   ```

4. **Execute o programa**:

   ```bash
   ./test_hdf5
   ```

5. **Saída esperada**:
   ```plaintext
   HDF5 test passed. File 'test.h5' created successfully.
   ```
</details>

<details>
<summary>🧪 Teste OpenMPI</summary>

1. **Crie um programa MPI simples**:

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

2. **Compile o código**:

   ```bash
   mpicc test_mpi.c -o test_mpi
   ```

3. **Execute o programa em 4 processos**:

   ```bash
   mpirun -np 4 ./test_mpi
   ```

4. **Saída esperada**:
   ```plaintext
   Hello from rank 0 of 4.
   Hello from rank 1 of 4.
   Hello from rank 2 of 4.
   Hello from rank 3 of 4.
   ```
</details>

---

## 📦 Validando Arquivos Gerados

- Verifique se os arquivos `test.nc` e `test.h5` foram criados.
- Use ferramentas como `ncdump` para NetCDF e `h5dump` para HDF5:

  ```bash
  ncdump test.nc
  h5dump test.h5
  ```

Se todos os testes passarem, as bibliotecas estão instaladas e funcionando corretamente. Caso encontre erros, compartilhe as mensagens para ajudarmos na depuração!

---

<a name="script"></a>
## 📜 Uso do Script Automatizado

Para facilitar todo o processo de **instalação e verificação do Spack-Stack 1.7.0 na Egeon**, você pode utilizar um **script shell completo**, que realiza todas as etapas descritas nesta wiki, incluindo testes de verificação com as bibliotecas **NetCDF**, **HDF5** e **OpenMPI**.

### 📥 1. Baixe o script

Clone o repositório com o script já pronto:

```bash
git clone https://github.com/joaogerd/spack-egeon.git
cd spack-egeon
```

O script estará disponível no arquivo:

```bash
install_and_test_spack_stack.sh
```

### 🔐 2. Dê permissão de execução

```bash
chmod +x install_and_test_spack_stack.sh
```

### 🚀 3. Execute o script

```bash
./install_and_test_spack_stack.sh
```

### 📌 O que o script faz?

- Clona o repositório do Spack-Stack 1.7.0 com submódulos.
- Carrega o módulo `gnu9` disponível na Egeon.
- Inicializa o ambiente do Spack.
- Copia os arquivos de configuração do site `egeon`.
- Cria e ativa o ambiente `mpas-bundle`.
- Concretiza e instala todos os pacotes.
- Gera os meta-módulos.
- Carrega os módulos essenciais.
- Realiza testes automatizados com:
  - **NetCDF**: criação e leitura de um arquivo `.nc`.
  - **HDF5**: criação e leitura de um arquivo `.h5`.
  - **OpenMPI**: execução paralela com 4 processos MPI.
- Exibe mensagens de sucesso e validação de arquivos com `ncdump` e `h5dump`.
- Gera um script auxiliar para **ativar corretamente o ambiente Spack-Stack e os módulos compilados**.

### ✅ Resultado Esperado

Ao final do script, você verá mensagens como:

```plaintext
NetCDF test passed. File 'test.nc' created and opened successfully.
HDF5 test passed. File 'test.h5' created successfully.
Hello from rank 0 of 4.
Hello from rank 1 of 4.
Hello from rank 2 of 4.
Hello from rank 3 of 4.
```

Se todos os testes forem bem-sucedidos, o ambiente está pronto para uso com **MPAS-JEDI** ou outros projetos científicos.

<a name="ativando"></a>
## ⚙️ Ativando o Ambiente após a Instalação

Após a execução bem-sucedida do script `install_and_test_spack_stack.sh`, um script auxiliar chamado `start_spack_bundle.sh` será gerado automaticamente no diretório pessoal do usuário.

Este script serve para **ativar corretamente o ambiente Spack-Stack e os módulos compilados**, garantindo que bibliotecas como **NetCDF**, **HDF5** e **OpenMPI** estejam disponíveis no sistema.

### 📌 Para ativar o ambiente, execute:

```bash
source $HOME/.spack/$ENV_NAME/start_spack_bundle.sh
```

Este comando irá:

- Ativar o ambiente `mpas-bundle`
- Inclusão do diretório correto de módulos
- Carregar os módulos necessários (`stack-gcc`, `stack-openmpi`, `stack-python`, etc.)
- Exportar corretamente o `LD_LIBRARY_PATH` com as bibliotecas necessárias

> ⚠️ **Importante**: Este passo deve ser feito **sempre que for utilizar** o ambiente instalado. Sem isso, bibliotecas compartilhadas como `libnetcdf.so` podem não ser encontradas.



