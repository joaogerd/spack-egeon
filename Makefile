# Makefile — seed per-user environment module lists
# -----------------------------------------------------------------------------
# Installs configs/templates/<ENV>/modules.sh into $ENV_ROOT/<ENV>/env.modules.sh
#
# Examples:
#   make seed-mpas-user
#   make seed-obs-user
#   make seed ENV=obsproc-bundle
#   make seed-all
#   make seed ENV=mpas-bundle ENV_ROOT=/mnt/beegfs/das.group/.spack
#
# Notes:
# - No packages are compiled; this just installs the per-environment module list.
# - Existing files are backed up if content differs.

SHELL := /usr/bin/env bash

# Defaults (override on the CLI if needed)
ENV       ?= mpas-bundle
ENV_ROOT  ?= $(HOME)/.spack
CONFIG_DIR?= $(CURDIR)/configs/templates

MODULES_SRC := $(CONFIG_DIR)/$(ENV)/modules.sh
MODULES_DST := $(ENV_ROOT)/$(ENV)/env.modules.sh

.PHONY: help seed seed-mpas-user seed-obs-user seed-all print-paths

help:
	@printf '%s\n' \
	  'Usage:' \
	  '  make seed-mpas-user                      # install mpas-bundle module list to $$HOME/.spack/mpas-bundle' \
	  '  make seed-obs-user                       # install obsproc-bundle module list to $$HOME/.spack/obsproc-bundle' \
	  '  make seed ENV=<bundle>                   # generic (e.g., ENV=obsproc-bundle)' \
	  '  make seed-all                            # mpas-bundle + obsproc-bundle' \
	  '  make seed ENV=<bundle> ENV_ROOT=<dir>    # change destination root (shared)' \
	  '' \
	  'Variables:' \
	  '  ENV        (default: mpas-bundle)' \
	  '  ENV_ROOT   (default: $$HOME/.spack)' \
	  '  CONFIG_DIR (default: ./configs/templates)'

print-paths:
	@echo "[INFO] ENV        = $(ENV)"
	@echo "[INFO] CONFIG_DIR = $(CONFIG_DIR)"
	@echo "[INFO] Source     = $(MODULES_SRC)"
	@echo "[INFO] ENV_ROOT   = $(ENV_ROOT)"
	@echo "[INFO] Dest dir   = $(dir $(MODULES_DST))"
	@echo "[INFO] Dest file  = $(MODULES_DST)"

seed: print-paths
	@[ -f "$(MODULES_SRC)" ] || { echo "[ERROR] Not found: $(MODULES_SRC)"; exit 1; }
	@mkdir -p "$(dir $(MODULES_DST))"
	@if [ -f "$(MODULES_DST)" ] && ! cmp -s "$(MODULES_SRC)" "$(MODULES_DST)"; then \
	  cp -a "$(MODULES_DST)" "$(MODULES_DST).bak.$$(date +%Y%m%d%H%M%S)"; \
	  echo "[INFO] Backup -> $(MODULES_DST).bak.$$(date +%Y%m%d%H%M%S)"; \
	fi
	@install -m 0644 "$(MODULES_SRC)" "$(MODULES_DST)"
	@echo "[OK] Installed: $(MODULES_DST)"

# Convenience targets
seed-mpas-user: ENV = mpas-bundle
seed-mpas-user: seed

seed-obs-user: ENV = obsproc-bundle
seed-obs-user: seed

seed-all: seed-mpas-user seed-obs-user

