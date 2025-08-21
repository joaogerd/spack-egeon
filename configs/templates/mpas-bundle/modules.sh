#!/usr/bin/env bash
###############################################################################
# modules.sh (mpas-bundle)
# -----------------------------------------------------------------------------
# Per-environment module list for the **MPAS-JEDI bundle** on Egeon.
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
# - Prefer explicit "name/version" pairs when stability matters.
# - Order may matter if modules have implicit dependencies; keep curated order.
# - Keep this file small and focused on module names only.
###############################################################################

ESSENTIALS=(stack-gcc/9.4.0 stack-openmpi/4.1.1 stack-python/3.10.13)

EXTRA_PKGS=(
  boost/1.84.0 jedi-cmake/1.4.0 python/3.10.13 c-blosc/1.21.5 libbsd/0.11.7
  qhull/2020.2 ca-certificates-mozilla/2023-05-30 libmd/1.0.4 snappy/1.1.10
  cmake/3.23.1 libxcrypt/4.4.35 sqlite/3.43.2 curl/8.4.0 nghttp2/1.57.0
  ecbuild/3.7.2 openblas/0.3.24 eigen/3.4.0 tar/1.34 gcc-runtime/9.4.0
  py-pip/23.1.2 udunits/2.2.28 gettext/0.21.1 py-pycodestyle/2.11.0
  util-linux-uuid/2.38.1 gmake/4.3 py-setuptools/63.4.3 zlib-ng/2.1.5
  gsl-lite/0.37.0 py-wheel/0.41.2 zstd/1.5.2
)

MPI_PKGS=(
  atlas/0.36.0 fftw/3.3.10 nccmp/1.9.0.1 parallelio/2.6.2
  eckit/1.24.5 fiat/1.2.0 netcdf-c/4.9.2 ectrans/1.2.0 netcdf-cxx4/4.3.1
  gptl/8.1.1 netcdf-fortran/4.6.1 fckit/0.11.0 hdf5/1.14.3 parallel-netcdf/1.12.3
)

