# Changelog

Todas as mudanças notáveis neste repositório serão documentadas aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/).

---

## [Unreleased]

> **Planejado para v2.0.0**  
> Suporte completo a **múltiplos ambientes Spack**, reorganização da estrutura e novas automações.

### **Adicionado**
- **Templates de ambientes** (`configs/templates/`):
  - `mpas-bundle` → dependências para **MPAS-JEDI**.
  - `obsproc-bundle` → dependências para **NCEPLIBS/Obsproc**.
- **Scripts unificados** (`scripts/`):
  - `install_spack.sh` → instala ou ativa o Spack.
  - `setup_env.sh` → cria, ativa, concretiza e instala ambientes.
  - `sanity_check.sh` → valida ferramentas e bibliotecas essenciais.
- **Nova organização do diretório `configs/`**:
  - `sites/egeon/` → arquivos específicos do cluster.
  - `templates/` → pacotes agrupados por projeto.
- **Melhor documentação**:
  - Novo `README.md` principal com fluxo de uso.
  - `configs/README.md` explicando estrutura e templates.
- **Integração com CI** *(opcional)*:
  - Lint para YAML.
  - Validação básica de scripts.
  - Teste “dry-run” de concretização para cada template.

---

## [v1.1.0] - 2025-10-08
### **Resumo**
Refatoração completa do fluxo de instalação, configuração e teste do **Spack-Stack**.  
Integração direta com o sistema de *helpers* e padronização da estrutura para múltiplos ambientes.

### **Alterado**
- **`install_and_test_spack_stack.sh`**
  - Totalmente reescrito e modularizado em três fases:
    1. Instalação/atualização do Spack-Stack;
    2. Criação e concretização de ambientes (`mpas-bundle`, `obsproc-bundle`);
    3. Execução de testes (básicos e específicos por ambiente).
  - Integração nativa com `__helpers__.sh` (logs, parser, execução segura).
  - Implementação de `_run_with_timeout()` compatível com `dry_run`.
  - Adição de **ProTex** em inglês com documentação completa (FUNCTION, DESCRIPTION, OPTIONS, etc.).
  - Auto-detecção de site (Egeon/XC50) e configuração automática de `site-config` e `env-yaml`.
  - Suporte às flags:  
    `--only-stack`, `--only-env`, `--only-tests`, `--with-baseline-tests`, `--with-env-tests`.
  - Logs e saídas organizados em `logs/site_probe_<host>_<timestamp>/`.

### **Adicionado**
- **`__helpers__.sh`**
  - Biblioteca padrão para todos os scripts (logger e parser unificados).
  - Fornece `_log_info`, `_log_warn`, `_log_err`, `_log_debug`, `_log_ok`, `_log_action`, `_die`, `_run`.
  - Suporta `--verbose`, `--dry-run`, `--debug`, `--quiet` e integração com scripts de automação.

- **`anchor/.spack_root`**
  - Arquivo *anchor* que define o diretório-raiz padrão do Spack-Stack (`~/.spack/mpas-bundle`).
  - Usado para detectar dinamicamente a raiz dos scripts e instalações.
  - Contém cabeçalho descritivo explicando seu propósito.

- **`configs/templates/common-tests/`**
  - Conjunto padronizado de testes reutilizáveis:
    - `test_netcdf_c.sh`, `test_netcdf_cxx4.sh`, `test_hdf5.sh`, `test_openmpi.sh`.
  - Ambientes (`mpas-bundle` e `obsproc-bundle`) agora fazem *symlink* para esses testes em `tests/`.

### **Removido**
- Loggers locais duplicados e parsers redundantes nos scripts antigos.

### **Impacto**
- O fluxo agora é reprodutível e portável entre clusters.
- Os testes de ambiente podem ser executados isoladamente.
- A estrutura está pronta para suportar múltiplos ambientes e CI básico.

---

## [v1.0.0] - 2025-08-20
### **Resumo**
Versão estável anterior à reorganização.  

- Ambiente único baseado no **spack-stack 1.7.0**.
- Scripts `install_and_test_spack_stack.sh` e `start_spack_bundle.sh` para criar e ativar ambiente.
- Configurações do cluster Egeon em `configs/sites/egeon/`.
- Documentação básica no `README.md`.

---

## **Roadmap**

### **v2.0.0** *(próxima versão)*
- [ ] **Suporte completo a múltiplos ambientes** (MPAS-JEDI e NCEPLIBS/Obsproc).
- [ ] **Scripts robustos** com logs, checagens e flags configuráveis.
- [ ] **Documentação detalhada** para usuários novos.
- [ ] **CI mínima** com lint de YAML, ShellCheck e teste de concretização.
- [ ] Exploração do **Spack buildcache** para economizar tempo em instalações.

### **v2.1.0** *(planejado)*
- [ ] Automação para compilar **MPAS-JEDI** usando o ambiente do template.
- [ ] Automação para compilar **Obsproc** e dependências integradas.
- [ ] Guia de troubleshooting para problemas comuns (MPI, HDF5, NetCDF).

---

