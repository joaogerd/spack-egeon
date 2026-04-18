# Automação de criação e ativação do ambiente

Este documento descreve o uso dos scripts do repositório para **criar**, **instalar**, **testar** e **ativar** ambientes do `spack-stack` a partir das configurações institucionais versionadas aqui.

## Scripts envolvidos

### `install_and_test_spack_stack.sh`
Script principal de provisão do ambiente.

Responsabilidades:

- preparar o diretório de trabalho;
- clonar ou reutilizar uma árvore do `spack-stack`;
- copiar `site` e `template` para a árvore do `spack-stack`;
- criar o ambiente com `spack stack create env`;
- concretizar e instalar;
- atualizar módulos Lmod;
- configurar meta-módulos;
- executar testes funcionais;
- gerar um ativador privado em `~/.spack/<env>/start_spack_bundle.sh`.

### `start_spack_bundle.sh`
Script base de ativação do ambiente já instalado.

O instalador copia esse script para um diretório privado do usuário e reescreve alguns defaults, como versão do `spack-stack`, nome do ambiente e prefixo-base.

---

## Uso do instalador

### Exemplo básico

```bash
./install_and_test_spack_stack.sh \
  --version 1.7.0 \
  --site egeon \
  --template mpas-bundle \
  --env mpas-bundle \
  --compiler-module gnu9
```

### Exemplo com limpeza e sem testes

```bash
./install_and_test_spack_stack.sh \
  --site egeon \
  --template mpas-bundle \
  --clean \
  --skip-tests
```

### Exemplo com diretório de trabalho alternativo

```bash
./install_and_test_spack_stack.sh \
  --version 1.7.0 \
  --site egeon \
  --template mpas-bundle \
  --workdir /mnt/beegfs/$USER \
  --config-repo /mnt/beegfs/$USER/spack-stack-inpe
```

---

## Parâmetros suportados

### `--version <ver>`
Versão do `spack-stack` a clonar ou reutilizar.

Exemplo:

```bash
--version 1.7.0
```

### `--env <name>`
Nome do ambiente a ser criado em `envs/<name>`.

Exemplo:

```bash
--env mpas-bundle
```

### `--site <name>`
Nome do site em `configs/sites/<name>`.

Exemplo:

```bash
--site egeon
```

### `--template <name>`
Nome do template em `configs/templates/<name>`.

Exemplo:

```bash
--template mpas-bundle
```

### `--workdir <path>`
Diretório base onde a árvore `spack-stack_<version>` será criada.

Exemplo:

```bash
--workdir /mnt/beegfs/$USER
```

### `--config-repo <path>`
Caminho local do repositório `spack-stack-inpe`.

Útil quando o repositório já foi clonado manualmente.

### `--config-repo-url <url>`
URL Git do repositório de configuração.

Útil para apontar para um fork ou um branch remoto diferente.

### `--compiler-module <mod>`
Módulo base carregado antes de `source setup.sh`.

Exemplo na EGEON:

```bash
--compiler-module gnu9
```

### `--clean`
Remove caches e recria o ambiente localmente.

Útil quando houve mudanças grandes em:

- `compilers.yaml`
- `packages.yaml`
- `modules.yaml`
- `config.yaml`
- `template`

### `--skip-tests`
Pula os testes funcionais no fim da instalação.

---

## O que o instalador faz internamente

Em termos práticos, o fluxo é:

1. define caminhos e caches;
2. opcionalmente limpa o ambiente anterior;
3. garante a presença do repositório institucional;
4. garante a presença da árvore do `spack-stack`;
5. carrega o módulo base do compilador;
6. executa `source setup.sh`;
7. copia `site` e `template` para dentro do `spack-stack`;
8. cria o ambiente com `spack stack create env`;
9. ativa o ambiente;
10. executa:

```bash
spack concretize
spack install --source
spack module lmod refresh -y
spack stack setup-meta-modules
```

11. executa testes funcionais, quando habilitados;
12. gera um script privado de ativação em `~/.spack/<env>/start_spack_bundle.sh`.

---

## Ativação posterior do ambiente

Após a instalação, o caminho recomendado é:

```bash
source ~/.spack/mpas-bundle/start_spack_bundle.sh
```

Esse script gerado:

- desativa Conda, se houver ambiente ativo;
- inicializa o `spack`;
- ativa o ambiente instalado;
- adiciona o caminho correto dos módulos;
- carrega meta-módulos principais, quando encontrados;
- exporta `NETCDF_DIR`, `NETCDF_CXX_DIR` e `HDF5_DIR`;
- complementa `LD_LIBRARY_PATH`.

---

## Uso direto do script base

O script `start_spack_bundle.sh` do repositório também pode ser usado diretamente:

```bash
source ./start_spack_bundle.sh \
  --version 1.7.0 \
  --env mpas-bundle \
  --root-prefix /mnt/beegfs/$USER
```

Parâmetros suportados:

- `--version <ver>`
- `--env <name>`
- `--root-prefix <path>`
- `--compiler-module <mod>`
- `--mpi-module <mod>`

---

## Quando usar o fluxo automatizado

O fluxo automatizado é o mais indicado quando você quer:

- instalar o ambiente do zero;
- repetir uma instalação com rastreabilidade;
- validar rapidamente um `site` novo;
- testar se `site + template` continuam consistentes;
- padronizar a criação do ambiente entre usuários.

---

## Quando usar o fluxo manual

O fluxo manual é mais indicado quando você precisa:

- depurar um problema específico de concretização;
- analisar comportamento do Spack passo a passo;
- revisar detalhadamente um `compilers.yaml` ou `packages.yaml`;
- isolar erros de módulo, compiler wrapper ou dependência externa.

Para isso, veja:

- [`manual-installation.md`](manual-installation.md)
