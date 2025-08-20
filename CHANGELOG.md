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
