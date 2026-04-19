# Arquitetura do repositório

Este repositório foi organizado para separar de forma explícita três responsabilidades diferentes:

- **infraestrutura da máquina** (`site`)
- **definição da aplicação** (`template`)
- **automação do fluxo de criação e ativação** (`scripts`)

Essa separação é importante para manter:

- reprodutibilidade;
- portabilidade entre máquinas;
- menor acoplamento entre ambiente local e aplicação;
- consistência institucional ao longo do tempo.

---

## Fluxo completo

O fluxo completo deve ser entendido assim:

```text
máquina real
→ bootstrap-spack
→ site institucional
→ template
→ scripts de provisão/ativação
→ ambiente final
```

### Onde entra o `bootstrap-spack`

O **bootstrap-spack** é um projeto separado, dedicado à descoberta e derivação de configuração de `site`.

Repositório:

- https://github.com/joaogerd/bootstrap-spack

Ele existe para ajudar a transformar a realidade da máquina em artefatos compatíveis com o ecossistema do `spack-stack`, principalmente:

- `compilers.yaml`
- `packages.yaml`
- `modules.yaml`
- `config.yaml`

Em termos práticos, o `bootstrap-spack` ajuda a:

- detectar compiladores e wrappers reais;
- identificar MPI, módulos e externals disponíveis;
- derivar providers e parâmetros básicos de runtime;
- separar o que é **fato detectado** do que é **política institucional**;
- reduzir o esforço manual para fechar um novo `site`.

### Onde entra o `spack-stack-inpe`

O **spack-stack-inpe** é o repositório institucional que guarda:

- os `site`s aprovados e versionados;
- os `template`s de aplicação;
- os scripts operacionais de criação, teste e ativação;
- a documentação do fluxo institucional.

Em resumo:

- **bootstrap-spack** → ajuda a descobrir a máquina e gerar ou revisar o `site`;
- **spack-stack-inpe** → guarda a configuração consolidada e distribui o fluxo operacional.

---

## Motivação histórica: por que o bootstrap passou a ser necessário

A necessidade de um fluxo de **bootstrap** mais forte ficou clara quando começou o trabalho de preparação da configuração da **JACI**.

Na EGEON, a configuração de site conseguiu ser consolidada com esforço manual e refinamentos sucessivos. Mas a experiência com a JACI mostrou com mais nitidez que a parte mais difícil não era escrever o template do ambiente, e sim fechar corretamente a camada de `site`.

Ou seja, o gargalo real estava em transformar a realidade da máquina em arquivos consistentes como:

- `compilers.yaml`
- `packages.yaml`
- `modules.yaml`
- `config.yaml`

Esse processo exige ao mesmo tempo:

- identificar compiladores reais e seus wrappers;
- descobrir MPI e módulos associados;
- reconstruir externals válidos para o Spack;
- definir providers sem degradar a concretização;
- distinguir o que é **fato da máquina** do que é **política institucional**.

Foi dessa dificuldade prática que surgiu a necessidade de fortalecer o desenvolvimento do **bootstrap-spack**. A função dele não é substituir o repositório institucional, mas tornar mais viável e menos frágil a criação dos arquivos de `site` para novas máquinas.

---

## Camadas do repositório

## 1. Site

Local:

```text
configs/sites/<machine>/
```

Responsabilidade:

- representar a infraestrutura da máquina;
- registrar a configuração institucional aprovada para aquela máquina;
- servir como base para criação do ambiente com `spack stack create env`.

Arquivos típicos:

- `compilers.yaml`
- `packages.yaml`
- `modules.yaml`
- `config.yaml`

### Interpretação correta do site

O diretório `configs/sites/<machine>/` representa uma **fotografia operacional da máquina** em um dado momento.

Isso significa que ele:

- pode ser revisado;
- pode ser regenerado quando o ambiente da máquina mudar;
- não deve ser tratado como verdade eterna ou imutável.

### O que deve estar no site

No `site` devem ficar elementos ligados à infraestrutura, por exemplo:

- compiladores disponíveis;
- MPI e externals do host;
- backend de módulos;
- parâmetros de runtime da instalação;
- policy institucional da máquina.

### O que não deve estar no site

O `site` não deve carregar dependências específicas da aplicação final.

---

## 2. Template

Local:

```text
configs/templates/<template>/
```

Responsabilidade:

- definir a aplicação;
- definir specs e dependências científicas;
- definir como o ambiente final será montado a partir do site.

Exemplo atual:

```text
configs/templates/mpas-bundle/spack.yaml
```

### Regra crítica

> O `site` descreve a máquina. O `template` descreve a aplicação.

Isso significa, por exemplo, que dependências específicas do `mpas-bundle` devem permanecer no template, e não migrar para `configs/sites/<machine>/`.

---

## 3. Scripts

Arquivos principais:

- `install_and_test_spack_stack.sh`
- `start_spack_bundle.sh`

Responsabilidade:

- automatizar o fluxo de criação do ambiente;
- reduzir repetição manual;
- incorporar verificações mínimas;
- facilitar ativação posterior do ambiente.

### `install_and_test_spack_stack.sh`

Esse script executa o fluxo completo de provisão:

- prepara diretórios e caches;
- clona ou reutiliza o `spack-stack`;
- copia `site` e `template`;
- cria e ativa o ambiente;
- concretiza e instala;
- atualiza módulos;
- configura meta-módulos;
- executa testes funcionais;
- gera um script privado de ativação.

### `start_spack_bundle.sh`

Esse script atua na fase posterior, quando o ambiente já foi instalado.

Ele serve para:

- inicializar o `spack`;
- ativar o ambiente correto;
- incluir caminhos de módulos;
- carregar meta-módulos principais;
- exportar variáveis úteis;
- ajustar `LD_LIBRARY_PATH`.

---

## Relação com o bootstrap-spack

O `spack-stack-inpe` não é o lugar certo para implementar toda a lógica de descoberta da máquina.

O repositório institucional deve permanecer centrado em:

- armazenar os sites aprovados;
- armazenar templates de aplicação;
- armazenar scripts operacionais;
- documentar o fluxo institucional.

Já o **bootstrap-spack** é o espaço natural para:

- descobrir compiladores e wrappers;
- identificar MPI, módulos e externals;
- derivar `packages.yaml` e `compilers.yaml` com mais automação;
- distinguir fato detectado de policy institucional;
- reduzir o esforço manual de criação de novos `site`s.

Assim, a relação correta entre os dois é:

- **bootstrap-spack** → ajuda a gerar ou revisar a configuração de `site`;
- **spack-stack-inpe** → guarda a configuração institucional consolidada.

---

## Estado atual

Hoje o foco operacional principal continua sendo a **EGEON**, mas a arquitetura já foi pensada para suportar expansão para outras máquinas, como a **JACI**.

O amadurecimento do bootstrap e a evolução dos scripts existem justamente para diminuir o custo de fechar novos sites e tornar esse processo mais confiável.
