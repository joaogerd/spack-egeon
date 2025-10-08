#!/usr/bin/env bash
###############################################################################
# test_hdf5.sh — HDF5 smoke test (compile + create .h5 file)
# -----------------------------------------------------------------------------
# Maintainer : João Gerd Zell de Mattos <joao.gerd@gmail.com>
# Purpose    : Verify that libhdf5 is usable in the active environment.
# Behavior   : SKIP if hdf5 not found via spack location.
###############################################################################
set -Eeuo pipefail

log(){ echo "[INFO] $*"; }
pass(){ echo "[OK]   $*"; }
warn(){ echo "[WARN] $*"; }
fail(){ echo "[ERROR] $*"; exit 1; }

CC="${CC:-gcc}"
HDF5_DIR="$(spack location -i hdf5 2>/dev/null || true)"
if [[ -z "${HDF5_DIR}" ]]; then
  warn "hdf5 not found — SKIP"
  exit 0
fi

TMPDIR="$(mktemp -d)"; trap 'rm -rf "${TMPDIR}"' EXIT
pushd "${TMPDIR}" >/dev/null

cat > test_hdf5.c <<'C'
#include "hdf5.h"
#include <stdio.h>
int main(){
  hid_t file = H5Fcreate("test.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
  if (file < 0) { puts("H5Fcreate failed"); return 1; }
  if (H5Fclose(file) < 0) { puts("H5Fclose failed"); return 1; }
  puts("HDF5 OK");
  return 0;
}
C

INC="${HDF5_DIR}/include"
LIB="${HDF5_DIR}/lib"; [[ -d "${HDF5_DIR}/lib64" ]] && LIB="${HDF5_DIR}/lib64"

log "Compiling with ${CC} ..."
"${CC}" test_hdf5.c -o test_hdf5 -I"${INC}" -L"${LIB}" -lhdf5

./test_hdf5
[[ -f test.h5 ]] || fail "expected output file test.h5 not created"
pass "HDF5 smoke test completed"

popd >/dev/null
