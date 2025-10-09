#!/usr/bin/env bash
#BOP
# !SCRIPT: hpc_site_probe.sh
# !DESCRIPTION:
#   Levanta informações essenciais do cluster/host para preparar um "site"
#   do spack-stack / JEDI. Seguro para rodar sem privilégios e armazena as
#   saídas em uma pasta datada. Inclui sumários (MD/ENV/JSON) e um TAR.
#
# !USAGE:
#   hpc_site_probe.sh [--fast] [--no-net] [--full-modules]
#                     [--timeout N] [-o|--out DIR] [-h|--help]
#
# !OPTIONS:
#   --fast            Coleta rápida (pula checagens pesadas/lentas)
#   --no-net          Não executa consultas de rede/InfiniBand
#   --full-modules    Tenta listar todos os módulos (pode ser lento)
#   --timeout N       Timeout (s) por comando externo (padrão: 8)
#   -o, --out DIR     Diretório de saída (padrão: ./site_probe_<host>_<ts>)
#   -h, --help        Mostra esta ajuda e sai
#
# !OUTPUT:
#   <OUT>/raw/            # saídas "brutas" dos comandos
#   <OUT>/summary.md      # resumo legível
#   <OUT>/summary.env     # chave=valor (greppable)
#   <OUT>/summary.json    # JSON simples (sem jq)
#   <OUT>/archive.tgz     # pacote com tudo
#
# !NOTES:
#   - Projeto: Reformate Scripts Shell — probe de site para spack-stack/JEDI.
#   - Não requer root/sudo. Usa 'timeout' se disponível.
#   - Idempotente em diretório novo; não sobrescreve saídas existentes.
#EOP

set -euo pipefail

#-----------------------------#
# Constantes e códigos de saída
#-----------------------------#
EX_OK=0
EX_USAGE=1
EX_CONFIG=3
EX_CANTCREAT=5

#-----------------------------#
# Flags/variáveis padrão
#-----------------------------#
TS="$(date +%Y%m%d-%H%M%S)"
HOST="$(hostname -s 2>/dev/null || hostname || echo unknown)"
OUT_DIR="${PWD}/site_probe_${HOST}_${TS}"

FAST=0
WITH_NET=1
REDUCE_MODULES_LIST=1
TIMEOUT=8

# Permite ajustar via env (ex.: MAX_MODULES=400 ./hpc_site_probe.sh)
MAX_MODULES_DEFAULT_REDUCED=200
MAX_MODULES_DEFAULT_FULL=2000

#-----------------------------#
# Utilidades de log
#-----------------------------#
_log_ts() { date +%H:%M:%S; }
_log_info() { printf '[%s] [INFO] %s\n' "$(_log_ts)" "$(printf "$@")"; }
_log_warn() { printf '[%s] [WARN] %s\n' "$(_log_ts)" "$(printf "$@")" >&2; }
_log_err()  { printf '[%s] [ERROR] %s\n' "$(_log_ts)" "$(printf "$@")" >&2; }

#-----------------------------#
# Ajuda/uso
#-----------------------------#
usage() {
  cat <<USAGE
Uso: $0 [opções]
  --fast                 Coleta rápida (pula checagens pesadas/lentas)
  --no-net               Não executa consultas de rede/InfiniBand
  --full-modules         Tenta listar todos os módulos (pode ser lento)
  --timeout N            Timeout (s) por comando externo (padrão: ${TIMEOUT})
  -o, --out DIR          Diretório de saída (padrão: ${OUT_DIR})
  -h, --help             Esta ajuda

Saídas:
  <OUT>/raw/            Coleção "bruta" de comandos
  <OUT>/summary.md      Resumo humano
  <OUT>/summary.env     Chave=valor (greppable)
  <OUT>/summary.json    JSON simples (sem jq)
  <OUT>/archive.tgz     Tudo compactado
USAGE
}

#-----------------------------#
# Parse de argumentos
#-----------------------------#
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast) FAST=1; shift;;
    --no-net) WITH_NET=0; shift;;
    --full-modules) REDUCE_MODULES_LIST=0; shift;;
    --timeout)
      [[ $# -ge 2 ]] || { _log_err "Falta valor para --timeout"; exit ${EX_USAGE}; }
      TIMEOUT="$2"; shift 2;;
    -o|--out)
      [[ $# -ge 2 ]] || { _log_err "Falta valor para --out"; exit ${EX_USAGE}; }
      OUT_DIR="$2"; shift 2;;
    -h|--help) usage; exit ${EX_OK};;
    *)
      _log_warn "Argumento desconhecido ignorado: %s" "$1"
      shift;;
  esac
done

#-----------------------------#
# Preparação do diretório
#-----------------------------#
mkdir -p "${OUT_DIR}/raw" 2>/dev/null || {
  _log_err "Não foi possível criar %s" "${OUT_DIR}/raw"
  exit ${EX_CANTCREAT}
}

# Verifica se é gravável
testfile="${OUT_DIR}/.writable.$$"
if ! ( : >"${testfile}" ) 2>/dev/null; then
  _log_err "Diretório de saída não é gravável: %s" "${OUT_DIR}"
  exit ${EX_CANTCREAT}
fi
rm -f "${testfile}"

#-----------------------------#
# Helpers
#-----------------------------#
have() { command -v "$1" >/dev/null 2>&1; }

# run <nome> <comando...>
run() {
  local name="$1"; shift || true
  local outfile="${OUT_DIR}/raw/${name}.txt"
  _log_info "Coletando: %s" "${name}"

  # shell: -l (login) para respeitar módulos/ambiente se existir
  if have timeout; then
    ( timeout "${TIMEOUT}" bash -lc "$*" || true ) >"${outfile}" 2>&1 || true
  else
    _log_warn "timeout(1) ausente; executando %s sem timeout" "${name}"
    ( bash -lc "$*" || true ) >"${outfile}" 2>&1 || true
  fi
}

# imprime até N linhas (default 80) de um arquivo, tolerante a erros
short() {
  local f="$1" n="${2:-80}"
  head -n "${n}" "$f" 2>/dev/null || true
}

#-----------------------------#
# Coletas básicas
#-----------------------------#
run uname         'uname -a'
run os-release    'cat /etc/os-release || true'
run cpu-lscpu     'lscpu || true'
run cpu-proc      'grep -m1 -E "^model name|^cpu cores|^siblings|^vendor_id" /proc/cpuinfo || true; echo; grep -c ^processor /proc/cpuinfo || true'
run mem-free      'free -h || true'
run mem-numa      'numactl --hardware || true'
run kernel-cmd    'cat /proc/cmdline || true'
run selinux       'getenforce 2>/dev/null || echo disabled'
run ulimits       'ulimit -a'
run env-basic     'env | sort'
run mounts        'mount | sort'
run filesystems   'df -hT | sort -k2,2 -k3,3h'
run tmpdirs       'ls -ld /tmp /var/tmp 2>/dev/null; echo; getconf PAGESIZE 2>/dev/null || true'

# Lustre / GPFS / BeeGFS
run lustre  'type lfs >/dev/null 2>&1 && (lfs df -h; echo; lfs osts || true) || echo "lfs não disponível"'
run gpfs    'type mmlsfs >/dev/null 2>&1 && mmlsfs all 2>&1 || echo "GPFS não disponível"'
run beegfs  'type beegfs-ctl >/dev/null 2>&1 && beegfs-ctl --getcfg 2>&1 || echo "BeeGFS não disponível"'

#-----------------------------#
# Schedulers
#-----------------------------#
run scheduler '
if command -v sbatch >/dev/null 2>&1; then
  echo SLURM
  [[ '"${FAST}"' -eq 1 ]] || sinfo || true
  scontrol show config 2>/dev/null | head -n 120 || true
elif command -v qsub >/dev/null 2>&1; then
  echo PBS
  qstat --version 2>&1 || true
  qmgr -c "p s" 2>&1 | head -n 160 || true
else
  echo "unknown"
fi'

#-----------------------------#
# Módulos (Lmod/EnvModules)
#-----------------------------#
# Controla tamanho de 'module avail' conforme flags/env
if [[ ${REDUCE_MODULES_LIST} -eq 1 ]]; then
  MAX_MODULES="${MAX_MODULES:-$MAX_MODULES_DEFAULT_REDUCED}"
else
  MAX_MODULES="${MAX_MODULES:-$MAX_MODULES_DEFAULT_FULL}"
fi

run modules-core '
if type module >/dev/null 2>&1; then
  module --version 2>&1 || true
  echo
  echo "MODULEPATH=${MODULEPATH}"
  echo
  # Evita paginador e banners longos
  MODULES_AVAIL=$(module -t avail 2>&1 | sed -e "1,2d" || true)
  printf "%s\n" "${MODULES_AVAIL}" | head -n '"${MAX_MODULES}"'
else
  echo "module não encontrado"
fi'

#-----------------------------#
# Compiladores
#-----------------------------#
run compilers '
for cc in gcc icc icx clang nvc; do
  printf "\n== %s ==\n" "$cc"
  if command -v "$cc" >/dev/null 2>&1; then ("$cc" --version || "$cc" -v) 2>&1 | head -n 6; fi
done
for fc in gfortran ifort ifx flang nvfortran; do
  printf "\n== %s ==\n" "$fc"
  if command -v "$fc" >/dev/null 2>&1; then ("$fc" --version || "$fc" -v) 2>&1 | head -n 6; fi
done'

#-----------------------------#
# MPI
#-----------------------------#
run mpi-basic '
for m in mpirun mpiexec; do
  printf "\n== %s ==\n" "$m"
  if command -v "$m" >/dev/null 2>&1; then "$m" --version 2>&1 | head -n 6; fi
done
for x in mpicc mpicxx mpifort; do
  printf "\n== %s -show ==\n" "$x"
  if command -v "$x" >/dev/null 2>&1; then "$x" -show 2>&1 | head -n 4; fi
done
(ompi_info --parsable 2>/dev/null | head -n 40) || (ompi_info 2>/dev/null | head -n 40) || true
(mpichversion 2>/dev/null || true)
'

#-----------------------------#
# NetCDF/HDF5 e amigos
#-----------------------------#
run netcdf-hdf5 '(nc-config --all 2>/dev/null || true); echo; (nf-config --all 2>/dev/null || true); echo; (nccopy -V 2>&1 | head -n 2 || true); echo; (h5cc -showconfig 2>/dev/null || h5pcc -showconfig 2>/dev/null || true)'
run esmf-eccodes '(esmfinfo 2>/dev/null | head -n 60 || true); echo; (eccodes_info 2>/dev/null | head -n 80 || true)'
run eckit-atlas '(eckit-version 2>/dev/null || true); echo; (atlas-version 2>/dev/null || true)'

#-----------------------------#
# Build tools
#-----------------------------#
run build-tools '(cmake --version 2>&1 | head -n 2 || true); (ninja --version 2>&1 || true); (make --version 2>&1 | head -n 1 || true); (git --version 2>&1 || true)'

#-----------------------------#
# Python
#-----------------------------#
run python '
for py in python3 python; do
  printf "\n== %s ==\n" "$py"
  if command -v "$py" >/dev/null 2>&1; then "$py" -V 2>&1; fi
done
(pip3 --version 2>&1 || true)
(virtualenv --version 2>&1 || true)
'

#-----------------------------#
# GPU / Drivers
#-----------------------------#
run gpu-nvidia 'nvidia-smi -L 2>/dev/null || true; echo; nvidia-smi 2>/dev/null | head -n 20 || true'
run gpu-rocm   'rocm-smi 2>/dev/null || true; rocminfo 2>/dev/null | head -n 40 || true'

#-----------------------------#
# Rede / OFED / IB
#-----------------------------#
if [[ ${WITH_NET} -eq 1 && ${FAST} -eq 0 ]]; then
  run net-ips   'ip -o -4 addr show 2>/dev/null || true; echo; ip -o -6 addr show 2>/dev/null || true; echo; hostname -f 2>/dev/null || true'
  run ofed      '(ofed_info -s 2>/dev/null || ofed_info 2>/dev/null || true)'
  run ibv       '(ibv_devinfo 2>/dev/null || true)'
  run ibstat    '(ibstat 2>/dev/null || true)'
else
  _log_info "Bloco de rede/IB foi pulado (WITH_NET=%s, FAST=%s)" "${WITH_NET}" "${FAST}"
fi

#-----------------------------#
# Spack / Spack-Stack / JEDI bits
#-----------------------------#
run spack-core 'command -v spack >/dev/null 2>&1 && spack --version || echo "spack não encontrado"'
run spack-arch 'command -v spack >/dev/null 2>&1 && spack arch || true'
run spack-comp 'command -v spack >/dev/null 2>&1 && spack compiler find || true'
run spack-vars 'command -v spack >/dev/null 2>&1 && spack config get compilers || true'

run jedi-cmake 'jedi-cmake --version 2>/dev/null || true'
run fckit      'fckit-config --version 2>/dev/null || true'

#-----------------------------#
# Sumários
#-----------------------------#
SMRY_MD="${OUT_DIR}/summary.md"
SMRY_ENV="${OUT_DIR}/summary.env"
SMRY_JSON="${OUT_DIR}/summary.json"

# summary.env (chave=valor)
{
  echo "host=${HOST}"
  echo -n "os_name=";   grep -E '^NAME='    "${OUT_DIR}/raw/os-release.txt" | head -1 | cut -d= -f2- | tr -d '"' || true
  echo -n "os_version="; grep -E '^VERSION=' "${OUT_DIR}/raw/os-release.txt" | head -1 | cut -d= -f2- | tr -d '"' || true
  echo -n "kernel=";     head -1 "${OUT_DIR}/raw/uname.txt" || true
  echo -n "cpu_model=";  grep -m1 'model name' "${OUT_DIR}/raw/cpu-proc.txt" | cut -d: -f2- | sed 's/^[[:space:]]*//' || true
  echo -n "cpu_sockets="; grep -E 'NUMA node\(s\):' "${OUT_DIR}/raw/cpu-lscpu.txt" | awk '{print $3}' | head -1 || true
  echo -n "cpu_cores=";   grep -m1 '^CPU(s):' "${OUT_DIR}/raw/cpu-lscpu.txt" | awk '{print $2}' || true
  echo -n "mem_total=";   awk '/^Mem:/ {print $2; exit}' "${OUT_DIR}/raw/mem-free.txt" || true
  echo -n "scheduler=";   head -1 "${OUT_DIR}/raw/scheduler.txt" || true
  echo -n "modules=";     head -3 "${OUT_DIR}/raw/modules-core.txt" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' || true
  echo -n "mpi_hint=";    grep -E -m1 'Open MPI|MPICH|Intel\(R\) MPI' "${OUT_DIR}/raw/mpi-basic.txt" || true
  echo -n "netcdf_hint="; grep -m1 -E 'netCDF .* version' "${OUT_DIR}/raw/netcdf-hdf5.txt" || true
  echo -n "hdf5_hint=";   grep -m1 -E 'HDF5 (library|Version)' "${OUT_DIR}/raw/netcdf-hdf5.txt" || true
  echo -n "cmake=";       grep -m1 -E 'cmake version' "${OUT_DIR}/raw/build-tools.txt" || true
  echo -n "python=";
  # procura primeira linha de versão do bloco python
  awk '/^== python3 ==/{getline; print; exit} /^== python ==/{getline; print; exit}' "${OUT_DIR}/raw/python.txt" 2>/dev/null || true
} >"${SMRY_ENV}" 2>/dev/null || true

# summary.md (legível)
cat >"${SMRY_MD}" <<MD
# Site Probe — ${HOST}
Data/hora: ${TS}

## SO / Kernel
$(short "${OUT_DIR}/raw/os-release.txt")

**Kernel**
\`\`\`
$(short "${OUT_DIR}/raw/uname.txt")
\`\`\`

## CPU / Memória
\`\`\`
$(short "${OUT_DIR}/raw/cpu-lscpu.txt")
\`\`\`
\`\`\`
$(short "${OUT_DIR}/raw/mem-free.txt")
\`\`\`

## Scheduler
\`\`\`
$(short "${OUT_DIR}/raw/scheduler.txt")
\`\`\`

## Módulos
\`\`\`
$(short "${OUT_DIR}/raw/modules-core.txt")
\`\`\`

## Compilers
\`\`\`
$(short "${OUT_DIR}/raw/compilers.txt")
\`\`\`

## MPI
\`\`\`
$(short "${OUT_DIR}/raw/mpi-basic.txt")
\`\`\`

## NetCDF / HDF5 / ESMF / (ecCodes, eckit, atlas)
\`\`\`
$(short "${OUT_DIR}/raw/netcdf-hdf5.txt")
\`\`\`
\`\`\`
$(short "${OUT_DIR}/raw/esmf-eccodes.txt")
\`\`\`
\`\`\`
$(short "${OUT_DIR}/raw/eckit-atlas.txt")
\`\`\`

## Build Tools / Git
\`\`\`
$(short "${OUT_DIR}/raw/build-tools.txt")
\`\`\`

## Python
\`\`\`
$(short "${OUT_DIR}/raw/python.txt")
\`\`\`

## GPU
\`\`\`
$(short "${OUT_DIR}/raw/gpu-nvidia.txt")
\`\`\`
\`\`\`
$(short "${OUT_DIR}/raw/gpu-rocm.txt")
\`\`\`

## Rede / OFED / IB
\`\`\`
$(short "${OUT_DIR}/raw/net-ips.txt")
\`\`\`
\`\`\`
$(short "${OUT_DIR}/raw/ofed.txt")
\`\`\`
\`\`\`
$(short "${OUT_DIR}/raw/ibv.txt")
\`\`\`
\`\`\`
$(short "${OUT_DIR}/raw/ibstat.txt")
\`\`\`

## Spack
\`\`\`
$(short "${OUT_DIR}/raw/spack-core.txt")
\`\`\`
\`\`\`
$(short "${OUT_DIR}/raw/spack-arch.txt")
\`\`\`
\`\`\`
$(short "${OUT_DIR}/raw/spack-comp.txt")
\`\`\`
MD

# summary.json (robusto e simples; escapa aspas)
{
  printf '{\n'
  awk -F= '{
    gsub(/\\/,"\\\\",$2);
    gsub(/"/,"\\\"",$2);
    printf("%s  \"%s\": \"%s\"", NR==1?"":",\n", $1, $2)
  } END { printf("\n}\n") }' "${SMRY_ENV}" >"${SMRY_JSON}" || true
}

#-----------------------------#
# Pacote final (tar.gz)
#-----------------------------#
( cd "${OUT_DIR}" && tar -czf archive.tgz raw summary.md summary.env summary.json >/dev/null 2>&1 || true )

_log_info "Coleta concluída. Saídas em: %s" "${OUT_DIR}"
_log_info "Sugestão: anexe %s para análise." "${OUT_DIR}/archive.tgz"
exit ${EX_OK}

