#!/usr/bin/env bash
###############################################################################
# modules.sh (obsproc-bundle)
# -----------------------------------------------------------------------------
# Per-environment module list for the **NCEPLIBS / Obsproc bundle** on Egeon.
# Loaded by start_spack_bundle.sh to activate curated module sets.
# -----------------------------------------------------------------------------
# Maintainer : João Gerd Zell de Mattos <joao.gerd@gmail.com>
# Created    : 2025-08-20
# Last update: 2025-08-20
#
# PURPOSE
# =======
# Define the arrays ESSENTIALS, EXTRA_PKGS and MPI_PKGS that will be consumed
# by start_spack_bundle.sh as:
#   for m in "${ESSENTIALS[@]}"; do load_module "$m"; done
#   for m in "${EXTRA_PKGS[@]}";  do load_module "$m"; done
#   for m in "${MPI_PKGS[@]}";    do load_module "$m"; done
#
# USAGE
# -----
#   # Do not execute directly; this file is *sourced* by:
#   #   ~/.spack/<ENV_NAME>/start_spack_bundle.sh  (or the generic starter)
#
# CONVENTIONS
# -----------
# - Start with module *names* (unversioned) to use site defaults, then pin
#   versions as needed after installation (`module avail` to inspect).
# - Keep this file small and focused on module names only.
###############################################################################

ESSENTIALS=(stack-gcc/9.4.0 stack-openmpi/4.1.1 stack-python/3.10.13)

EXTRA_PKGS=(
  cmake
  hdf5
  netcdf-c
  netcdf-fortran
  eccodes
  jasper
  libpng
  zlib
  nccmp
  wgrib2
  crtm
)

MPI_PKGS=(
  bufr
  bacio
  w3emc
  w3nco
  sp
  ip
  g2c
  sigio
  sfcio
  gfsio
  nemsio
)

