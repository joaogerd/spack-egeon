# Changelog

Todas as mudanças notáveis neste repositório serão documentadas aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/).

## [Unreleased]

### Adicionado
- Suporte a múltiplos **templates de ambientes Spack**:
  - `mpas-bundle` → dependências para **MPAS-JEDI**.
  - `obsproc-bundle` → dependências para **NCEPLIBS/Obsproc**.
- Novo diretório `scripts/` com automações:
  - `install_spack.sh` → instala/ativa o Spack.
  - `setup_env.sh` → cria, ativa, concretiza e instala um ambiente.
  - `sanity_check.sh` → checa compiladores, bibliotecas e ferramentas.
- Nova organização de `configs/`:
  - `sites/egeon/` → arquivos de configuração do cluster.
  - `templates/` → pacotes agrupados por finalidade.
- Novo `README.md` principal e `configs/README.md` detalhando a estrutura.
- Integração opcional com CI via GitHub Actions.

---

## [v1.0.0] - 2025-08-20
### Fixo
- Estado atual consolidado do repositório.
- Ambiente único baseado no **spack-stack 1.7.0** para **Egeon**.
- Script `install_and_test_spack_stack.sh` funcional para instalação e geração de módulos.
- Configurações específicas para o cluster Egeon em `configs/sites/egeon/`.

---

## Como versionamos

- **v1.x.x** → ambiente único (MPAS).
- **v2.x.x** → múltiplos ambientes, templates e scripts refatorados.
