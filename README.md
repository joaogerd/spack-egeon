### **Receita para Configurar o Spack-Stack na Máquina Egeon**

Esta receita foi criada a partir de uma troca de e-mails e contém todas as etapas necessárias para instalar e configurar o Spack-Stack na máquina Egeon, considerando particularidades do ambiente e possíveis erros.

---

#### **Passo 1: Clonando o Repositório do Spack-Stack**
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

#### **Passo 2: Configurando os Arquivos do Site**
Os arquivos de configuração necessários estão temporariamente localizados em `<spack-stack-egeon>`:

```bash
/mnt/beegfs/andy.stokely/spack-stacks/spack-stack_1.7.0
```

Copie o site "egeon" e o template "mpas-bundle" para o diretório de configurações do Spack-Stack que você clonou:

```bash
cp -r <spack-stack-egeon>/configs/site/egeon configs/site/
cp -r <spack-stack-egeon>/configs/templates/mpas-bundle configs/templates/
```

Adicione o elemento `flags` no arquivo `compilers.yaml` localizado em `configs/site/egeon`, caso ele não exista. Este passo é essencial para evitar erros na concretização do ambiente. Um exemplo de configuração seria:

```yaml
compilers:
  - compiler:
      flags: {}
```

---

#### **Passo 3: Criando e Ativando o Ambiente**
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

#### **Passo 4: Concretizando e Instalando**
Concretize o ambiente para resolver todas as dependências e registre as saídas em um log:

```bash
spack concretize 2>&1 | tee log.concretize
```

Em seguida, inicie a instalação e registre as saídas:

```bash
spack install 2>&1 | tee log.install
```

---

### **Possíveis Erros e Soluções**

1. **Erro: "flags" ausente no arquivo `compilers.yaml`**
   - **Descrição:** Durante a execução do comando `spack concretize`, pode surgir um erro relacionado ao elemento `flags`.
   - **Solução:** Adicione o elemento `flags` no arquivo `compilers.yaml` conforme mostrado acima.

2. **Problemas com OpenMPI e SLURM**
   - **Descrição:** A integração entre o OpenMPI e o SLURM da Egeon pode causar falhas se você não usar os compiladores e MPI nativos.
   - **Solução:** Certifique-se de usar os módulos nativos carregados via `module load`.

3. **Erro no comando `spack stack setup-meta-modules`**
   - **Descrição:** Mesmo após a instalação, este comando pode falhar devido a uma configuração incorreta dos módulos Lmod.
   - **Solução:** Revise os arquivos de configuração do site e certifique-se de que o ambiente foi ativado corretamente antes de rodar o comando.

4. **Necessidade de instalar o GCC e Lmod com o Spack**
   - **Descrição:** Dependendo do ambiente, pode ser necessário instalar ferramentas específicas, como GCC e Lmod.
   - **Comandos sugeridos:**
     ```bash
     spack add gcc@8.5.0
     spack install gcc@8.5.0
     spack load gcc@8.5.0
     spack compiler add
     spack compiler list
     spack add lmod@8.7.24
     spack install lmod@8.7.24
     ```

---

### **Conferência Final**
Depois de completar todos os passos, use o ambiente configurado para compilar os módulos necessários para o MPAS-JEDI ou outros pacotes. Caso surjam dúvidas adicionais, considere agendar uma chamada com um especialista para revisar as configurações.

É possível verificar a partir dos logs se o processo de instalação do ambiente **Spack-Stack 1.7.0** ocorreu conforme esperado. Aqui estão alguns pontos importantes para verificar:

### Indicadores de Sucesso
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

### Pontos de Observação
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

### Verificação Pós-Instalação
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

Aqui estão sugestões de testes simples para verificar o funcionamento básico das bibliotecas **NetCDF**, **HDF5** e **OpenMPI** após a instalação.

---

### 1. **Testando NetCDF**

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

2. **Compile o código**:

   ```bash
   gcc test_netcdf.c -o test_netcdf -lnetcdf
   ```

3. **Execute o programa**:

   ```bash
   ./test_netcdf
   ```

4. **Saída esperada**:
   ```plaintext
   NetCDF test passed. File 'test.nc' created and opened successfully.
   ```

---

### 2. **Testando HDF5**

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

2. **Compile o código**:

   ```bash
   gcc test_hdf5.c -o test_hdf5 -lhdf5
   ```

3. **Execute o programa**:

   ```bash
   ./test_hdf5
   ```

4. **Saída esperada**:
   ```plaintext
   HDF5 test passed. File 'test.h5' created successfully.
   ```

---

### 3. **Testando OpenMPI**

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

---

### 4. **Validando Arquivos Gerados**
- Verifique se os arquivos `test.nc` e `test.h5` foram criados.
- Use ferramentas como `ncdump` para NetCDF e `h5dump` para HDF5:

  ```bash
  ncdump test.nc
  h5dump test.h5
  ```

Se todos os testes passarem, as bibliotecas estão instaladas e funcionando corretamente. Caso encontre erros, compartilhe as mensagens para ajudarmos na depuração!
