# spack-stack-inpe

Repositório institucional do INPE para uso do **spack-stack** em máquinas do grupo, com foco atual na **EGEON** e estrutura preparada para expansão para outras máquinas, como a **JACI**.

O repositório concentra três coisas distintas:

- **configuração de site** (`configs/sites/<machine>/`)
- **template de aplicação** (`configs/templates/<template>/`)
- **scripts de provisão e ativação** do ambiente

A ideia central é manter uma separação clara entre **máquina**, **aplicação** e **automação do fluxo**.

---

## Visão geral

O **spack-stack-inpe** existe para padronizar o uso institucional do `spack-stack`, reduzir erros recorrentes de instalação e manter um caminho reproduzível para criação de ambientes científicos, especialmente o ambiente **mpas-bundle** usado em fluxos ligados ao MPAS-JEDI.

No estado atual do projeto, o repositório contém:

- configuração de site para a **EGEON**;
- template de ambiente **mpas-bundle**;
- scripts para criação, instalação, testes e ativação do ambiente;
- documentação técnica e operacional.

---

## Arquitetura do repositório

Este repositório segue a separação explícita entre:

- **infraestrutura da máquina** (`site`)
- **definição da aplicação** (`template`)
- **automação da criação e ativação do ambiente** (`scripts`)

Fluxo conceitual:

```text
site (máquina)
+
template (aplicação)
+
scripts (provisão/ativação)
=
ambiente final
```

Para uma descrição mais detalhada da arquitetura, veja:

- [`docs/architecture.md`](docs/architecture.md)

---

## Estrutura do repositório

```text
configs/
├── sites/
│   └── egeon/
└── templates/
    └── mpas-bundle/

install_and_test_spack_stack.sh
start_spack_bundle.sh

docs/
├── architecture.md
├── automation.md
└── manual-installation.md
```

### Componentes principais

#### `configs/sites/<machine>/`
Define a configuração institucional da máquina.

Exemplo atual:

- `configs/sites/egeon/compilers.yaml`
- `configs/sites/egeon/packages.yaml`
- `configs/sites/egeon/modules.yaml`
- `configs/sites/egeon/config.yaml`

Esses arquivos representam uma **fotografia operacional do site** em um determinado momento.

#### `configs/templates/<template>/`
Define a aplicação e suas dependências.

Exemplo atual:

- `configs/templates/mpas-bundle/spack.yaml`

Regra importante:

> O `site` descreve a infraestrutura da máquina. O `template` descreve a aplicação. Dependências específicas do `mpas-bundle` devem permanecer no template, não no site.

#### `install_and_test_spack_stack.sh`
Script principal para:

- preparar o diretório de trabalho;
- clonar o `spack-stack`;
- copiar site e template para a árvore do `spack-stack`;
- criar e ativar o ambiente;
- concretizar e instalar;
- atualizar módulos;
- configurar meta-módulos;
- executar testes funcionais;
- gerar um script privado de ativação em `~/.spack/<env>/start_spack_bundle.sh`.

#### `start_spack_bundle.sh`
Script genérico de ativação do ambiente já instalado.

Ele deve ser usado com `source` e serve como base para o script privado gerado pelo instalador.

---

## Requisitos

Antes de usar o repositório, confirme:

- acesso a um diretório de trabalho estável, como `/mnt/beegfs/$USER`;
- `git` disponível;
- sistema de módulos funcional;
- compilador base disponível na máquina (na EGEON, por exemplo, `gnu9`);
- acesso ao GitHub para clonagem do `spack-stack` e deste repositório;
- permissões adequadas para criar diretórios e instalar no espaço de trabalho escolhido.

---

## Fluxo recomendado

Para a maioria dos casos, o caminho recomendado é usar o script automatizado.

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

---

## Opções do script principal

O script `install_and_test_spack_stack.sh` hoje suporta:

- `--version <ver>`: versão do `spack-stack`;
- `--env <name>`: nome do ambiente Spack;
- `--site <name>`: site em `configs/sites/<name>`;
- `--template <name>`: template em `configs/templates/<name>`;
- `--workdir <path>`: diretório base de trabalho;
- `--config-repo <path>`: caminho local deste repositório;
- `--config-repo-url <url>`: URL Git deste repositório;
- `--compiler-module <mod>`: módulo base a carregar antes de `setup.sh`;
- `--clean`: remove caches e recria o ambiente;
- `--skip-tests`: pula os testes funcionais.

Detalhes completos e exemplos adicionais estão em:

- [`docs/automation.md`](docs/automation.md)

---

## Ativação do ambiente após a instalação

Ao final da instalação, o script gera um ativador privado em:

```bash
~/.spack/<env>/start_spack_bundle.sh
```

Exemplo:

```bash
source ~/.spack/mpas-bundle/start_spack_bundle.sh
```

Esse ativador:

- desativa Conda, quando necessário;
- inicializa o `spack`;
- ativa o ambiente correspondente;
- adiciona o caminho correto de módulos;
- carrega meta-módulos principais, quando disponíveis;
- exporta variáveis úteis, como `NETCDF_DIR`, `NETCDF_CXX_DIR` e `HDF5_DIR`;
- ajusta `LD_LIBRARY_PATH` para reduzir problemas com bibliotecas dinâmicas.

O script base também pode ser usado diretamente com parâmetros:

```bash
source ./start_spack_bundle.sh \
  --version 1.7.0 \
  --env mpas-bundle \
  --root-prefix /mnt/beegfs/$USER
```

---

## Instalação manual

O fluxo manual continua documentado e pode ser útil para depuração, validação de site ou entendimento do processo.

Veja:

- [`docs/manual-installation.md`](docs/manual-installation.md)

Esse documento cobre:

- preparação do ambiente;
- clone do `spack-stack`;
- cópia de `site` e `template`;
- criação do ambiente;
- concretização e instalação;
- geração de módulos;
- testes funcionais com NetCDF, NetCDF-C++, HDF5 e MPI.

---

## Testes funcionais

O instalador pode executar testes funcionais básicos para:

- **NetCDF**
- **NetCDF-C++**
- **HDF5**
- **OpenMPI**

Esses testes verificam o ambiente já concretizado e instalado.

Quando necessário, o script também exporta os caminhos para:

- `NETCDF_DIR`
- `NETCDF_CXX_DIR`
- `HDF5_DIR`

Além disso, complementa `LD_LIBRARY_PATH` para evitar problemas com carregamento de bibliotecas compartilhadas.

Os exemplos detalhados de teste estão em:

- [`docs/manual-installation.md`](docs/manual-installation.md)

---

## Indicadores de sucesso

Os principais sinais de que a instalação ocorreu corretamente são:

- `spack concretize` concluído com sucesso;
- `spack install --source` concluído com sucesso;
- criação do diretório `install/modulefiles` no ambiente;
- geração dos logs:
  - `log.concretize`
  - `log.install`
  - `log.modules`
  - `log.metamodules`
- sucesso nos testes funcionais, quando habilitados.

---

## Ambiente compartilhado

Quando houver um ambiente compartilhado do grupo, ele pode ser usado para evitar instalações duplicadas por usuário.

Exemplo conceitual:

```bash
source /mnt/beegfs/das.group/spack-envs/mpas-bundle/start_spack_bundle.sh
```

Essa estratégia ajuda a manter:

- uniformidade entre usuários;
- menor consumo de disco;
- menos divergência entre ambientes;
- maior facilidade de suporte interno.

---

## Estado atual e evolução

Hoje o foco principal continua sendo a **EGEON**, mas a estrutura do repositório já está organizada para suportar novas máquinas por meio da expansão de:

- `configs/sites/<machine>/`
- parâmetros do instalador (`--site`, `--template`, `--compiler-module`, `--workdir`)

Próximos passos naturais incluem:

- incorporação da configuração da **JACI**;
- refinamento contínuo dos scripts de provisão e ativação;
- integração mais forte com o fluxo de bootstrap e geração de site;
- sincronização contínua entre documentação, scripts e configurações versionadas.

---

## Documentação

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/automation.md`](docs/automation.md)
- [`docs/manual-installation.md`](docs/manual-installation.md)

---

## Licença

A licença do projeto ainda deve ser formalizada no repositório.
