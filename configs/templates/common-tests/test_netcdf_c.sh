#!/usr/bin/env bash
###############################################################################
# test_netcdf_c.sh — NetCDF-C smoke test (compile + create file)
# -----------------------------------------------------------------------------
# Maintainer : João Gerd Zell de Mattos <joao.gerd@gmail.com>
# Purpose    : Verify that netcdf-c is present and usable in the active env.
# Behavior   : SKIP if netcdf-c not found via `spack location -i netcdf-c`.
###############################################################################
set -Eeuo pipefail

log(){ echo "[INFO] $*"; }
pass(){ echo "[OK]   $*"; }
warn(){ echo "[WARN] $*"; }
fail(){ echo "[ERROR] $*"; exit 1; }

NETCDF_DIR="$(spack location -i netcdf-c 2>/dev/null || true)"
if [[ -z "${NETCDF_DIR}" ]]; then
  warn "netcdf-c not found in this environment — SKIP"
  exit 0
fi

CC="${CC:-gcc}"
TMPDIR="$(mktemp -d)"; trap 'rm -rf "${TMPDIR}"' EXIT
pushd "${TMPDIR}" >/dev/null

cat > test_netcdf_c.c <<'C'
#include <netcdf.h>
#include <stdio.h>
int main(){
  int ncid;
  if (nc_create("test_c.nc", NC_CLOBBER, &ncid)) { puts("nc_create failed"); return 1; }
  if (nc_close(ncid)) { puts("nc_close failed"); return 1; }
  puts("NetCDF-C OK");
  return 0;
}
C

INCDIR="${NETCDF_DIR}/include"
LIBDIR="${NETCDF_DIR}/lib"; [[ -d "${NETCDF_DIR}/lib64" ]] && LIBDIR="${NETCDF_DIR}/lib64"

log "Compiling with ${CC} ..."
"${CC}" test_netcdf_c.c -o test_netcdf_c -I"${INCDIR}" -L"${LIBDIR}" -lnetcdf

./test_netcdf_c
[[ -f test_c.nc ]] || fail "expected output file test_c.nc not created"
pass "NetCDF-C smoke test completed"

popd >/dev/null
