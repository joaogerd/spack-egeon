#!/usr/bin/env bash
###############################################################################
# test_openmpi.sh — OpenMPI smoke test (compile with mpicc; try mpirun)
# -----------------------------------------------------------------------------
# Maintainer : João Gerd Zell de Mattos <joao.gerd@gmail.com>
# Purpose    : Verify that mpicc exists and can build a tiny MPI hello world.
# Behavior   : SKIP if mpicc not in PATH and openmpi not resolvable via spack.
###############################################################################
set -Eeuo pipefail

log(){ echo "[INFO] $*"; }
pass(){ echo "[OK]   $*"; }
warn(){ echo "[WARN] $*"; }

if ! command -v mpicc >/dev/null 2>&1; then
  OMPI_DIR="$(spack location -i openmpi 2>/dev/null || true)"
  if [[ -n "${OMPI_DIR}" && -x "${OMPI_DIR}/bin/mpicc" ]]; then
    export PATH="${OMPI_DIR}/bin:${PATH}"
  fi
fi

if ! command -v mpicc >/dev/null 2>&1; then
  warn "mpicc not available — SKIP"
  exit 0
fi

TMPDIR="$(mktemp -d)"; trap 'rm -rf "${TMPDIR}"' EXIT
pushd "${TMPDIR}" >/dev/null

cat > mpi_hello.c <<'C'
#include <mpi.h>
#include <stdio.h>
int main(int argc, char** argv){
  MPI_Init(&argc, &argv);
  int rank,size; MPI_Comm_rank(MPI_COMM_WORLD,&rank); MPI_Comm_size(MPI_COMM_WORLD,&size);
  printf("Hello from rank %d of %d\n", rank, size);
  MPI_Finalize();
  return 0;
}
C

mpicc mpi_hello.c -o mpi_hello

# Some nodes may restrict mpirun; treat run failure as SKIP-RUN
set +e
mpirun --oversubscribe -n 2 ./mpi_hello
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  warn "mpirun failed on this node (rc=$rc) — compile step OK (SKIP-RUN)"
else
  pass "mpirun completed"
fi

popd >/dev/null
pass "OpenMPI smoke test completed"
