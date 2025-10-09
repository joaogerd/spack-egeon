# Makefile — user-friendly tasks for spack-egeon
# -----------------------------------------------------------------------------
# Scenarios covered:
#  1) Admin installs a shared Spack-Stack (group root: /mnt/beegfs/das.group)
#  2) Regular users just "consume" the shared stack:
#     - seed per-env module lists into $HOME/.spack/<env>/env.modules.sh
#     - install the generic starter into $HOME/.spack/start_spack_bundle.sh
#     - add handy aliases/functions to ~/.bashrc
#
# All variables are overridable on the CLI, e.g.:
#   make install-admin ENV=obsproc-bundle VERSION=1.8.0
#   make setup-user-admin ROOT_PREFIX=/mnt/beegfs/das.group
#
# Nothing here compiles packages unless you call *install-...* targets (which
# delegate to install_and_test_spack_stack.sh). "seed" and "aliases" are light.

SHELL := /usr/bin/env bash

# ----------------------------- Defaults --------------------------------------

ENV              ?= mpas-bundle
VERSION          ?= 1.8.0                          # spack-stack tag/branch
SITE             ?= egeon

<<<<<<< HEAD
ROOT_PREFIX      ?= /mnt/beegfs/das.group          # onde fica spack-stack (novo layout)
SELF_ROOT_PREFIX ?= /mnt/beegfs/$(USER)
ENV_ROOT         ?= $(HOME)/.spack
=======
# Where the compiled Spack-Stack trees live (root prefix)
ROOT_PREFIX ?= /mnt/beegfs/das.group
SELF_ROOT_PREFIX ?= /mnt/beegfs/$(USER)

# Fallbacks even if variables are defined but empty in the environment
ROOT_PREFIX := $(strip $(ROOT_PREFIX))
ifeq ($(ROOT_PREFIX),)
  ROOT_PREFIX := /mnt/beegfs/das.group
endif

SELF_ROOT_PREFIX := $(strip $(SELF_ROOT_PREFIX))
ifeq ($(SELF_ROOT_PREFIX),)
  SELF_ROOT_PREFIX := /mnt/beegfs/$(USER)
endif
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a

CONFIG_REPO      ?= $(CURDIR)
CONFIG_DIR       ?= $(CURDIR)/configs/templates
SITE_CONFIG_DIR  ?= $(CURDIR)/configs/sites/$(SITE)  # aponta templates .in do site

STARTER_SRC      ?= $(CURDIR)/start_spack_bundle.sh
STARTER_DST      ?= $(HOME)/.spack/start_spack_bundle.sh

INSTALL_SCRIPT   ?= $(CURDIR)/install_and_test_spack_stack.sh
BASHRC           ?= $(HOME)/.bashrc

# número de jobs para builds do Spack
JOBS             ?= 8

ALIAS_BEGIN := "# >>> spack-egeon aliases >>>"
ALIAS_END   := "# <<< spack-egeon aliases <<<"

<<<<<<< HEAD
# Strip/fallback
ENV              := $(strip $(ENV))
VERSION          := $(strip $(VERSION))
SITE             := $(strip $(SITE))
ENV_ROOT         := $(strip $(ENV_ROOT))
CONFIG_REPO      := $(strip $(CONFIG_REPO))
CONFIG_DIR       := $(strip $(CONFIG_DIR))
SITE_CONFIG_DIR  := $(strip $(SITE_CONFIG_DIR))
STARTER_SRC      := $(strip $(STARTER_SRC))
STARTER_DST      := $(strip $(STARTER_DST))
BASHRC           := $(strip $(BASHRC))
=======
# --------------------------- Sanitize / Fallbacks ----------------------------
# Strip accidental spaces and fallback if env provided empty values
ENV            := $(strip $(ENV))
VERSION        := $(strip $(VERSION))
ENV_ROOT       := $(strip $(ENV_ROOT))
CONFIG_REPO    := $(strip $(CONFIG_REPO))
CONFIG_DIR     := $(strip $(CONFIG_DIR))
STARTER_SRC    := $(strip $(STARTER_SRC))
STARTER_DST    := $(strip $(STARTER_DST))
BASHRC         := $(strip $(BASHRC))
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a

ROOT_PREFIX      := $(if $(strip $(ROOT_PREFIX)),$(strip $(ROOT_PREFIX)),/mnt/beegfs/das.group)
SELF_ROOT_PREFIX := $(if $(strip $(SELF_ROOT_PREFIX)),$(strip $(SELF_ROOT_PREFIX)),/mnt/beegfs/$(USER))

# --------------------------- Derived (re-evaluated) ---------------------------
<<<<<<< HEAD
# Novo layout (sem sufixo de versão no spack-stack)
SPACK_DIR        = $(ROOT_PREFIX)/spack-stack
SPACK_ROOT       = $(SPACK_DIR)/spack
SPACK_ENV_PATH   = $(ROOT_PREFIX)/envs/$(ENV)

# Módulos (detecção conservadora — melhor esforço)
# Se quiser fixar o caminho do Core, defina MODULE_CORE_PATH explicitamente fora do Make.
MODULE_CORE_PATH ?=
ifeq ($(strip $(MODULE_CORE_PATH)),)
  MODULE_CORE_PATH := $(shell \
    find "$(ROOT_PREFIX)" -type d -path "*/modulefiles/Core" -maxdepth 6 2>/dev/null | head -n1)
endif
=======
# Use recursive assignment (=) so changes to ROOT_PREFIX/ENV/VERSION at recipe
# time are reflected when used.
SPACK_DIR        = $(ROOT_PREFIX)/spack-stack_$(VERSION)
SPACK_ROOT       = $(SPACK_DIR)/spack
SPACK_ENV_PATH   = $(SPACK_DIR)/envs/$(ENV)
MODULE_CORE_PATH = $(SPACK_ENV_PATH)/install/modulefiles/Core
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a

# ----------------------------- Helpers ---------------------------------------

_print_cfg = \
  echo "[INFO] ENV           = '$(ENV)'"; \
  echo "[INFO] VERSION       = '$(VERSION)'"; \
<<<<<<< HEAD
  echo "[INFO] SITE          = '$(SITE)'"; \
=======
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a
  echo "[INFO] ROOT_PREFIX   = '$(ROOT_PREFIX)'"; \
  echo "[INFO] SELF_ROOT     = '$(SELF_ROOT_PREFIX)'"; \
  echo "[INFO] ENV_ROOT      = '$(ENV_ROOT)'"; \
  echo "[INFO] CONFIG_REPO   = '$(CONFIG_REPO)'"; \
  echo "[INFO] CONFIG_DIR    = '$(CONFIG_DIR)'"; \
<<<<<<< HEAD
  echo "[INFO] SITE_CONFIG   = '$(SITE_CONFIG_DIR)'"; \
  echo "[INFO] STARTER_SRC   = '$(STARTER_SRC)'"; \
  echo "[INFO] STARTER_DST   = '$(STARTER_DST)'"; \
  echo "[INFO] BASHRC        = '$(BASHRC)'"; \
  echo "[INFO] JOBS          = '$(JOBS)'";
=======
  echo "[INFO] STARTER_SRC   = '$(STARTER_SRC)'"; \
  echo "[INFO] STARTER_DST   = '$(STARTER_DST)'"; \
  echo "[INFO] BASHRC        = '$(BASHRC)'";
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a

modules_src = $(CONFIG_DIR)/$(ENV)/modules.sh
modules_dst = $(ENV_ROOT)/$(ENV)/env.modules.sh

# ------------------------------- Public --------------------------------------

.PHONY: help doctor doctor-admin doctor-self doctor-env print-config \
        seed seed-mpas-user seed-obs-user seed-all \
        install install-admin install-self \
        install-starter \
        add-aliases add-aliases-admin add-aliases-self remove-aliases \
        setup-user-admin setup-user-self

help:
	@printf '%s\n' \
	'Targets:' \
	'  help                  Show this help' \
	'  doctor                Quick checks for environment (module/spack presence)' \
	'  print-config          Print resolved variables/paths' \
	'' \
	'  seed                  Install per-env module list to $${ENV_ROOT}/$${ENV}/env.modules.sh' \
	'  seed-mpas-user        Shortcut: ENV=mpas-bundle' \
	'  seed-obs-user         Shortcut: ENV=obsproc-bundle' \
	'  seed-all              seed-mpas-user + seed-obs-user' \
	'' \
	'  install               Install selected ENV into ROOT_PREFIX (compiles packages)' \
	'  install-admin         Install into shared root (ROOT_PREFIX=/mnt/beegfs/das.group)' \
	'  install-self          Install into user root (ROOT_PREFIX=/mnt/beegfs/$${USER})' \
	'' \
	'  install-starter       Copy generic starter to $${STARTER_DST}' \
	'  add-aliases           Add functions/aliases to $${BASHRC} (uses ROOT_PREFIX & ENV_ROOT)' \
	'  add-aliases-admin     Same, but ROOT_PREFIX=$${ROOT_PREFIX} (shared)' \
	'  add-aliases-self      Same, but ROOT_PREFIX=$${SELF_ROOT_PREFIX} (self)' \
	'  remove-aliases        Remove the aliases/functions block from $${BASHRC}' \
	'' \
	'  setup-user-admin      seed-all + install-starter + add-aliases-admin' \
	'  setup-user-self       seed-all + install-starter + add-aliases-self' \
	'' \
	'Vars (override like VAR=value):' \
	'  ENV        (mpas-bundle|obsproc-bundle, default: mpas-bundle)' \
	'  VERSION    (default: 1.8.0)' \
	'  ROOT_PREFIX (default: /mnt/beegfs/das.group)' \
	'  SELF_ROOT_PREFIX (default: /mnt/beegfs/$${USER})' \
	'  ENV_ROOT   (default: $$HOME/.spack)' \
	'  JOBS       (default: 8)' \
	'  CONFIG_REPO/CONFIG_DIR, SITE_CONFIG_DIR, STARTER_SRC/STARTER_DST, INSTALL_SCRIPT, BASHRC'

# ------------------------------- Doctor --------------------------------------

doctor:
	@$(call _print_cfg)
	@bash -euo pipefail -c '\
	  err=0; \
	  echo "==> Checking Lmod/module..."; \
	  if ! type module >/dev/null 2>&1; then \
	    echo "[WARN] module not found; attempting to init Lmod"; \
	    [[ -f /etc/profile.d/modules.sh ]] && . /etc/profile.d/modules.sh || true; \
	    [[ -f /usr/share/lmod/lmod/init/bash ]] && . /usr/share/lmod/lmod/init/bash || true; \
	  fi; \
	  if type module >/dev/null 2>&1; then \
	    echo "[OK] module command available"; \
	  else \
	    echo "[WARN] Lmod not initialized (continuing)"; \
	  fi; \
<<<<<<< HEAD
	  echo; echo "==> Checking Spack tree..."; \
=======
	  echo; echo "==> Checking stack directories..."; \
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a
	  if [[ -d "$(SPACK_DIR)" ]]; then \
	    echo "[OK] Spack-Stack dir exists: $(SPACK_DIR)"; \
	  else \
	    echo "[WARN] Spack-Stack dir missing: $(SPACK_DIR)"; \
	  fi; \
	  echo; echo "==> Checking Spack setup script..."; \
	  setup1="$(SPACK_DIR)/setup.sh"; \
	  setup2="$(SPACK_DIR)/spack/share/spack/setup-env.sh"; \
	  spack_setup=""; \
<<<<<<< HEAD
	  if [[ -f "$$setup1" ]]; then spack_setup="$$setup1"; echo "[OK] Found: $$setup1"; \
	  elif [[ -f "$$setup2" ]]; then spack_setup="$$setup2"; echo "[OK] Found: $$setup2"; \
	  else echo "[ERROR] Spack setup not found under $(SPACK_DIR)"; err=1; fi; \
=======
	  if [[ -f "$$setup1" ]]; then \
	    spack_setup="$$setup1"; echo "[OK] Found: $$setup1"; \
	  elif [[ -f "$$setup2" ]]; then \
	    spack_setup="$$setup2"; echo "[OK] Found: $$setup2"; \
	  else \
	    echo "[ERROR] Spack setup not found under $(SPACK_ROOT)"; err=1; \
	  fi; \
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a
	  if [[ -n "$$spack_setup" ]]; then \
	    . "$$spack_setup"; \
	    if spack --version >/dev/null 2>&1; then \
	      echo "[OK] spack is usable: $$(spack --version)"; \
	    else \
	      echo "[ERROR] spack not usable after sourcing $$spack_setup"; err=1; \
	    fi; \
	  fi; \
<<<<<<< HEAD
	  echo; echo "==> Checking environment dir..."; \
	  if [[ -d "$(SPACK_ENV_PATH)" ]]; then \
	    echo "[OK] Env path exists: $(SPACK_ENV_PATH)"; \
	  else \
	    echo "[WARN] Env path missing: $(SPACK_ENV_PATH)"; \
	  fi; \
	  echo; echo "==> Checking Core modulefiles (best-effort)..."; \
	  if [[ -n "$(MODULE_CORE_PATH)" && -d "$(MODULE_CORE_PATH)" ]]; then \
=======
	  echo; echo "==> Checking Core modulefiles..."; \
	  if [[ -d "$(MODULE_CORE_PATH)" ]]; then \
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a
	    echo "[OK] Core modules dir: $(MODULE_CORE_PATH)"; \
	    cnt=$$(find "$(MODULE_CORE_PATH)" -maxdepth 1 -type f -name "*.lua" | wc -l | tr -d " "); \
	    echo "[INFO] Modulefiles in Core: $$cnt"; \
	    module use "$(MODULE_CORE_PATH)" || true; \
	    echo "[INFO] module -t avail (first 20 lines):"; module -t avail 2>&1 | sed -n "1,20p"; \
	  else \
<<<<<<< HEAD
	    echo "[INFO] Core modules dir not set or missing; skipping listing."; \
=======
	    echo "[WARN] Core modules dir missing: $(MODULE_CORE_PATH)"; \
	  fi; \
	  echo; echo "==> Checking per-env light files..."; \
	  env_modules="$(modules_dst)"; \
	  if [[ -f "$$env_modules" ]]; then \
	    echo "[OK] Env module list present: $$env_modules"; \
	  else \
	    echo "[WARN] Missing $$env_modules — run: make seed ENV=$(ENV)"; \
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a
	  fi; \
	  echo; echo "==> Permissions sanity..."; \
	  if [[ -d "$(ROOT_PREFIX)" && -w "$(ROOT_PREFIX)" ]]; then \
	    echo "[OK] Write access to ROOT_PREFIX: $(ROOT_PREFIX)"; \
	  else \
	    echo "[INFO] No write access to ROOT_PREFIX ($(ROOT_PREFIX))"; \
<<<<<<< HEAD
	    echo "      - Admin installs: make install-admin"; \
	    echo "      - Self installs:  make install-self"; \
=======
	    echo "      - Admin installs use: make install-admin (requires write)"; \
	    echo "      - Users can just seed/start or use: make install-self"; \
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a
	  fi; \
	  if [[ -d "$(ENV_ROOT)" ]]; then \
	    if [[ -w "$(ENV_ROOT)" ]]; then \
	      echo "[OK] Write access to ENV_ROOT: $(ENV_ROOT)"; \
	    else \
	      echo "[ERROR] No write access to ENV_ROOT: $(ENV_ROOT)"; err=1; \
	    fi; \
	  else \
	    echo "[WARN] ENV_ROOT missing: $(ENV_ROOT)"; \
	    echo "      Create it with: mkdir -p $(ENV_ROOT)"; \
	  fi; \
	  echo; echo "==> Summary"; \
	  if [[ $$err -eq 0 ]]; then echo "[DOCTOR] All critical checks passed."; \
	  else echo "[DOCTOR] Completed with issues (see above)."; exit 1; fi; \
	'

# Convenience wrappers that reuse the same checks with different roots
doctor-admin: ROOT_PREFIX := $(ROOT_PREFIX)
doctor-admin: doctor

doctor-self: ROOT_PREFIX := $(SELF_ROOT_PREFIX)
doctor-self: doctor

# Check a specific environment (override ENV on the CLI)
doctor-env: doctor

print-config:
	@$(call _print_cfg)

# --------------------------- Per-user seeding --------------------------------

seed: print-config
	@[ -f "$(modules_src)" ] || { echo "[ERROR] Not found: $(modules_src)"; exit 1; }
	@mkdir -p "$(dir $(modules_dst))"
	@if [ -f "$(modules_dst)" ] && ! cmp -s "$(modules_src)" "$(modules_dst)"; then \
	  cp -a "$(modules_dst)" "$(modules_dst).bak.$$(date +%Y%m%d%H%M%S)"; \
	  echo "[INFO] Backup -> $(modules_dst).bak.$$(date +%Y%m%d%H%M%S)"; \
	fi
	@install -m 0644 "$(modules_src)" "$(modules_dst)"
	@echo "[OK] Installed: $(modules_dst)"

seed-mpas-user: ENV ?= mpas-bundle
seed-mpas-user: seed

<<<<<<< HEAD
seed-obs-user: ENV ?= obsproc-bundle
=======
seed-obs-user: ENV ?= mpas-bundle
>>>>>>> 899212d5bc0c1d02842d325ba6effe65b665853a
seed-obs-user: seed

seed-all: seed-mpas-user seed-obs-user

# ------------------------------ Installer ------------------------------------

install:
	@$(call _print_cfg)
	@[ -x "$(INSTALL_SCRIPT)" ] || { echo "[ERROR] Not executable: $(INSTALL_SCRIPT)"; exit 1; }
	@# Seleciona automaticamente o melhor spack.yaml (site-aware > genérico), se existir
	@if [ -f "$(CONFIG_DIR)/$(ENV)/spack-$(SITE).yaml" ]; then \
	  ENV_YAML_OPT="--env-yaml $(CONFIG_DIR)/$(ENV)/spack-$(SITE).yaml"; \
	elif [ -f "$(CONFIG_DIR)/$(ENV)/spack.yaml" ]; then \
	  ENV_YAML_OPT="--env-yaml $(CONFIG_DIR)/$(ENV)/spack.yaml"; \
	else \
	  ENV_YAML_OPT=""; \
	fi; \
	"$(INSTALL_SCRIPT)" -- \
	  --site            "$(SITE)" \
	  --spack-version   "$(VERSION)" \
	  --spack-root      "$(ROOT_PREFIX)" \
	  --env-name        "$(ENV)" \
	  --site-config     "$(SITE_CONFIG_DIR)" \
	  $$ENV_YAML_OPT \
	  --jobs            "$(JOBS)"

install-admin: install

install-self:
	@$(MAKE) install ROOT_PREFIX ?= /mnt/beegfs/das.group

# ----------------------------- Starter script --------------------------------

install-starter:
	@mkdir -p "$(dir $(STARTER_DST))"
	@install -m 0755 "$(STARTER_SRC)" "$(STARTER_DST)"
	@echo "[OK] Starter installed at: $(STARTER_DST)"
	@echo "[INFO] Remember: this script must be *sourced*, e.g.:"
	@echo "       source $(STARTER_DST) --env mpas-bundle --spack-root $(ROOT_PREFIX)"

# --------------------------- Aliases / functions -----------------------------

define _ALIAS_BLOCK
$(ALIAS_BEGIN)
# Auto-generated by spack-egeon Makefile on $$(date)
# Adjust these three lines if your site defaults differ:
export SPACK_ENV_ROOT ?= $(HOME)/.spack
_spack_egeon_starter='$(STARTER_DST)'
_spack_egeon_root='$(ROOT_PREFIX)'

use_env() {
  local env="$${1:-mpas-bundle}"
  SPACK_ENV_ROOT ?= $(HOME)/.spack
}

# Handy shortcuts:
alias use-mpas='use_env mpas-bundle'
alias use-obs='use_env obsproc-bundle'

# Usage:
#   use-env <name>   (generic)  -> call as: use_env obsproc-bundle
#   use-mpas         (shortcut)
#   use-obs          (shortcut)
$(ALIAS_END)
endef
export _ALIAS_BLOCK

add-aliases:
	@touch "$(BASHRC)"
	@# remove previous block if present
	@awk 'BEGIN{del=0} $$0=="$(ALIAS_BEGIN)"{del=1; next} del && $$0=="$(ALIAS_END)"{del=0; next} !del{print $$0}' \
	  "$(BASHRC)" > "$(BASHRC).tmp" && mv "$(BASHRC).tmp" "$(BASHRC)"
	@# append new block
	@printf '%s\n' "$$_ALIAS_BLOCK" >> "$(BASHRC)"
	@echo "[OK] Aliases/functions added to $(BASHRC)"
	@echo "[INFO] Reload your shell:   source $(BASHRC)"
	@echo "[INFO] Then use:             use-mpas   |   use-obs   |   use_env <name>"

# Convenience variants pointing to different roots
add-aliases-admin: ROOT_PREFIX := $(ROOT_PREFIX)
add-aliases-admin: add-aliases

add-aliases-self: ROOT_PREFIX := $(SELF_ROOT_PREFIX)
add-aliases-self: add-aliases

remove-aliases:
	@touch "$(BASHRC)"
	@awk 'BEGIN{del=0} $$0=="$(ALIAS_BEGIN)"{del=1; next} del && $$0=="$(ALIAS_END)"{del=0; next} !del{print $$0}' \
	  "$(BASHRC)" > "$(BASHRC).tmp" && mv "$(BASHRC).tmp" "$(BASHRC)"
	@echo "[OK] Removed alias block from $(BASHRC)"

# ---------------------------- One-shot setups --------------------------------

setup-user-admin: ENV ?= mpas-bundle
setup-user-admin: seed-mpas-user
	@$(MAKE) seed-obs-user
	@$(MAKE) install-starter
	@$(MAKE) add-aliases-admin
	@echo "[DONE] User setup (admin stack): try 'use-mpas' or 'use-obs'"

setup-user-self: ENV ?= mpas-bundle
setup-user-self: seed-mpas-user
	@$(MAKE) seed-obs-user
	@$(MAKE) install-starter
	@$(MAKE) add-aliases-self
	@echo "[DONE] User setup (self stack): try 'use-mpas' or 'use-obs'"

