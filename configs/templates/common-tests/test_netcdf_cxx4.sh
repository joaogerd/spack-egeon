#!/usr/bin/env bash
###############################################################################
# test_netcdf_cxx4.sh — NetCDF-C++4 smoke test (compile + create file)
# -----------------------------------------------------------------------------
# Maintainer : João Gerd Zell de Mattos <joao.gerd@gmail.com>
# Purpose    : Verify that netcdf-cxx4 and netcdf-c are usable in the env.
# Behavior   : SKIP if either package is not found via spack location.
###############################################################################
set -Eeuo pipefail

log(){ echo "[INFO] $*"; }
pass(){ echo "[OK]   $*"; }
warn(){ echo "[WARN] $*"; }
fail(){ echo "[ERROR] $*"; exit 1; }

CXX="${CXX:-g++}"
NETCDF_DIR="$(spack location -i netcdf-c 2>/dev/null || true)"
NETCDF_CXX_DIR="$(spack location -i netcdf-cxx4 2>/dev/null || true)"

if [[ -z "${NETCDF_DIR}" || -z "${NETCDF_CXX_DIR}" ]]; then
  warn "netcdf-c and/or netcdf-cxx4 not found — SKIP"
  exit 0
fi

TMPDIR="$(mktemp -d)"; trap 'rm -rf "${TMPDIR}"' EXIT
pushd "${TMPDIR}" >/dev/null

cat > test_netcdf_cxx.cpp <<'CXX'
#include <netcdf>
#include <iostream>
int main(){
  try {
    netCDF::NcFile f("test_cxx.nc", netCDF::NcFile::replace);
    std::cout << "NetCDF-C++ OK\n";
  } catch(...) { return 1; }
  return 0;
}
CXX

INC_CXX="${NETCDF_CXX_DIR}/include"
LIB_CXX="${NETCDF_CXX_DIR}/lib"; [[ -d "${NETCDF_CXX_DIR}/lib64" ]] && LIB_CXX="${NETCDF_CXX_DIR}/lib64"
INC_C="${NETCDF_DIR}/include"
LIB_C="${NETCDF_DIR}/lib";       [[ -d "${NETCDF_DIR}/lib64" ]] && LIB_C="${NETCDF_DIR}/lib64"

log "Compiling with ${CXX} ..."
"${CXX}" test_netcdf_cxx.cpp -o test_netcdf_cxx \
  -I"${INC_CXX}" -L"${LIB_CXX}" \
  -I"${INC_C}"   -L"${LIB_C}"   \
  -lnetcdf_c++4 -lnetcdf

./test_netcdf_cxx
[[ -f test_cxx.nc ]] || fail "expected output file test_cxx.nc not created"
pass "NetCDF-C++ smoke test completed"

popd >/dev/null
