#!/usr/bin/env bash
#BOP
# !ROUTINE: install_and_test_spack_stack.sh
#
# !INTERFACE:
#   install_and_test_spack_stack.sh [COMMON OPTIONS] -- [SCRIPT OPTIONS]
#
# !FUNCTION:
#   One entrypoint to manage Spack-Stack on an HPC site in three phases:
#   (1) Install/refresh the shared Spack-Stack (NO env creation),
#   (2) Create and concretize a specific environment/bundle,
#   (3) Run tests (baseline and/or per-environment).
#
# !DESCRIPTION:
#   This script implements a reproducible flow to deploy Spack-Stack and
#   JEDI-related environments on HPC clusters. It is designed to be re-runnable,
#   safe without root privileges, and to log with the house helpers.
#
#   It integrates tightly with "__helpers__.sh":
#     - Logging uses: _log_info/_log_warn/_log_err/_log_debug/_die
#     - Execution uses: _run (honors dry_run)
#     - Arg parsing: __parse_args__ for common flags (-v/--verbose, --dry-run, etc.)
#
# !COMMON OPTIONS (handled by __helpers__.sh):
#   -v|--verbose            Verbose logging
#   -q|--quiet              Disable INFO logs
#   -d|--debug              Enable debug
#   --dry-run               Log commands without executing
#   -y|--yes                Auto-confirm
#   -f|--fix                Allow fixes (createdirs/symlinks), if used by callers
#
# !SCRIPT OPTIONS (after `--` or mixed in; parsed here from leftover_args):
#   --site NAME             HPC site shortname (e.g., egeon) [default: auto]
#   --spack-version VER     Spack-Stack version/tag (e.g., 1.7.0) [${SPACK_VERSION:-1.7.0}]
#   --spack-root DIR        Root prefix for Spack-Stack [${ROOT_PREFIX:-$HOME/.spack/mpas-bundle}]
#   --env-name NAME         Environment/bundle name (e.g., mpas-bundle) [${ENV_NAME:-mpas-bundle}]
#   --env-yaml PATH         spack.yaml template (site-aware) [auto]
#   --site-config DIR       Site configs (compilers.yaml, packages.yaml, etc.) [auto]
#   --jobs N                Parallel build jobs [${JOBS:-4}]
#   --timeout N             Per-command timeout (s) [${TIMEOUT:-900}]
#   --only-stack            Only Phase 1 (install Spack-Stack)
#   --only-env              Only Phase 2 (create/install environment)
#   --only-tests            Only Phase 3 (run tests)
#   --with-baseline-tests   Enable baseline tests (NetCDF, CXX4, HDF5, OpenMPI)
#   --with-env-tests        Enable env-specific tests (configs/templates/<env>/tests)
#   -h|--help               Show help
#
# !ENVIRONMENT:
#   verbose, debug, dry_run  (from __helpers__.sh)
#   SPACK_VERSION, ROOT_PREFIX, ENV_NAME, JOBS, TIMEOUT
#   /etc/profile.d/lmod.sh will be sourced if present to enable modules.
#
# !EXIT STATUS:
#   0 on success; non-zero on errors (with contextual message).
#
# !EXAMPLES:
#   # Install a shared stack for the group (no env):
#   ./install_and_test_spack_stack.sh -- \
#       --only-stack --spack-version 1.7.0 --spack-root /mnt/beegfs/das.group --site egeon
#
#   # Create the mpas-bundle on that stack:
#   ./install_and_test_spack_stack.sh -- \
#       --only-env --spack-root /mnt/beegfs/das.group --env-name mpas-bundle
#
#   # Run tests (baseline + env):
#   ./install_and_test_spack_stack.sh -- \
#       --only-tests --with-baseline-tests --with-env-tests
#
# !SEE ALSO:
#   Spack-Stack docs, JEDI build guides, site-specific README.
#
# !AUTHOR:
#   João Gerd Zell de Mattos <joao.gerd@gmail.com>
#
# !LICENSE:
#   LGPL-3.0 (as per project policy) or the project-specific license file.
#EOP

set -Eeuo pipefail
umask 022
IFS=$'\n\t'

#-------------------------------#
# Source project helpers (mandatory)
#-------------------------------#
# Expect __helpers__.sh in the same dir or neighboring lib path.
__HERE__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if   [[ -r "${__HERE__}/__helpers__.sh" ]]; then source "${__HERE__}/__helpers__.sh"
elif [[ -r "./__helpers__.sh"          ]]; then source "./__helpers__.sh"
elif [[ -r "${__HERE__}/lib/__helpers__.sh" ]]; then source "${__HERE__}/lib/__helpers__.sh"
else
  echo "[ERROR] __helpers__.sh not found; this script requires it." >&2
  exit 2
fi

# Short aliases to match house style
info()  { _log_info  "$@"; }
warn()  { _log_warn  "$@"; }
error() { _log_err   "$@"; }
debug() { _log_debug "$@"; }
die()   { _die       "$@"; }

# _run executes the command honoring dry_run; we add timeout wrapper when present
_run_with_timeout() {
  #BOP
  # !ROUTINE: _run_with_timeout
  # !DESCRIPTION: Execute a command with timeout when available, honoring dry_run via _run.
  #EOP
  local timeout_s="${TIMEOUT:-900}"
  if command -v timeout >/dev/null 2>&1; then
    if [[ "${dry_run:-false}" == "true" ]]; then
      _log_info "[DRY-RUN] timeout %s %s" "$timeout_s" "$*"
      return 0
    fi
    timeout "$timeout_s" "$@"
  else
    _run "$@"
  fi
}

#-------------------------------#
# Global context & traps
#-------------------------------#
_start_ts="$(date +%s)"
_script="$(basename "$0")"
_host="$(hostname -s 2>/dev/null || hostname || echo unknown)"
_tsdir="site_probe_${_host}_$(date +%Y%m%d-%H%M%S)"

on_error() {
  local ec=$? line="${BASH_LINENO[0]:-?}" cmd="${BASH_COMMAND:-?}"
  _log_err "FAIL line %s, exit %s: %s" "$line" "$ec" "$cmd"
  exit "$ec"
}
on_exit() {
  local dt=$(( $(date +%s) - _start_ts ))
  _log_debug "DONE %s completed in %ss" "$_script" "$dt"
}
trap on_error ERR
trap on_exit EXIT

#-------------------------------#
# Defaults (script-level)
#-------------------------------#
SPACK_VERSION="${SPACK_VERSION:-1.7.0}"
ENV_NAME="${ENV_NAME:-mpas-bundle}"
ROOT_PREFIX="${ROOT_PREFIX:-$HOME/.spack/mpas-bundle}"
SITE="${SITE:-}"
SITE_CONFIG="${SITE_CONFIG:-}"
ENV_YAML="${ENV_YAML:-}"
JOBS="${JOBS:-4}"
TIMEOUT="${TIMEOUT:-900}"

DO_STACK=1
DO_ENV=1
DO_TESTS=1
WITH_BASELINE_TESTS=0
WITH_ENV_TESTS=0

#-------------------------------#
# Usage (script options)
#-------------------------------#
usage() {
  sed -n '1,200p' "$0" | sed -n '/#BOP/,/#EOP/p' | sed 's/^# \?//'
  cat <<USAGE

Script options (parsed after __helpers__ common flags):
  --site NAME             e.g., egeon
  --spack-version VER     e.g., 1.7.0
  --spack-root DIR        root installation prefix
  --env-name NAME         e.g., mpas-bundle
  --env-yaml PATH         spack.yaml template
  --site-config DIR       site configs (compilers.yaml, packages.yaml,...)
  --jobs N                parallel spack builds (default ${JOBS})
  --timeout N             per-command timeout seconds (default ${TIMEOUT})
  --only-stack | --only-env | --only-tests
  --with-baseline-tests   enable baseline test suite
  --with-env-tests        enable env-specific tests
  -h|--help               this help
USAGE
}

#-------------------------------#
# Parse args: common via __parse_args__, then script-specific from leftover_args
#-------------------------------#
_parse_script_args() {
  # First pass (common flags); writes leftover_args[]
  PARSER_WRITE_LEFTOVERS=1 __parse_args__ "$@"

  # Second pass: parse this script's flags from leftover_args
  local opt
  local -a rest=()
  while [[ ${#leftover_args[@]} -gt 0 ]]; do
    opt="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}")
    case "$opt" in
      --site) SITE="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --spack-version) SPACK_VERSION="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --spack-root) ROOT_PREFIX="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --env-name) ENV_NAME="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --env-yaml) ENV_YAML="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --site-config) SITE_CONFIG="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --jobs) JOBS="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --timeout) TIMEOUT="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --only-stack) DO_STACK=1; DO_ENV=0; DO_TESTS=0;;
      --only-env)   DO_STACK=0; DO_ENV=1; DO_TESTS=0;;
      --only-tests) DO_STACK=0; DO_ENV=0; DO_TESTS=1;;
      --with-baseline-tests) WITH_BASELINE_TESTS=1;;
      --with-env-tests)      WITH_ENV_TESTS=1;;
      -h|--help) usage; _exit_ok;;
      --) rest+=("${leftover_args[@]}"); break;;
      *)  rest+=("$opt");;
    esac
  done

  # Push any remaining tokens back to leftover_args for downstream tools (rare)
  leftover_args=("${rest[@]}")
  export SPACK_VERSION ROOT_PREFIX ENV_NAME JOBS TIMEOUT
}

#-------------------------------#
# Helpers / phases
#-------------------------------#
ensure_dirs() { mkdir -p "${ROOT_PREFIX}" "./logs/${_tsdir}"; }

detect_site() {
  #BOP
  # !ROUTINE: detect_site
  # !DESCRIPTION: Best-effort site detection from hostname if --site not provided.
  #EOP
  [[ -n "$SITE" ]] && { _log_info "Site provided: %s" "$SITE"; return; }
  case "$_host" in
    egeon*|egeon) SITE="egeon";;
    xc50*|cray*)  SITE="xc50";;
    *)            SITE="generic";;
  esac
  _log_info "Auto-detected site: %s" "$SITE"
}

setup_site_config() {
  #BOP
  # !ROUTINE: setup_site_config
  # !DESCRIPTION: Resolve site-config and env-yaml locations if not provided.
  #EOP
  if [[ -z "$SITE_CONFIG" ]]; then
    for d in "configs/sites/${SITE}" "configs/${SITE}" ; do
      [[ -d "$d" ]] && { SITE_CONFIG="$d"; break; }
    done
  fi
  if [[ -z "$ENV_YAML" ]]; then
    for f in "configs/templates/${ENV_NAME}/spack.yaml" "configs/templates/${ENV_NAME}/spack-${SITE}.yaml"; do
      [[ -f "$f" ]] && { ENV_YAML="$f"; break; }
    done
  fi

  [[ -n "$SITE_CONFIG" ]] && _log_info "Using site-config: %s" "$SITE_CONFIG" || _log_warn "No site-config directory found (will rely on defaults)."
  [[ -n "$ENV_YAML"   ]] && _log_info "Using env template: %s" "$ENV_YAML"     || _log_warn "No env template (spack.yaml) provided; you may create one."
}

bootstrap_spack() {
  #BOP
  # !ROUTINE: bootstrap_spack
  # !DESCRIPTION: Install or refresh the Spack-Stack tree under ROOT_PREFIX.
  #EOP
  local spack_dir="${ROOT_PREFIX}/spack-stack"

  if [[ -d "$spack_dir/.git" ]]; then
    _log_info "Refreshing Spack-Stack @ %s (version: %s)" "$spack_dir" "${SPACK_VERSION}"
    ( cd "$spack_dir" && _run_with_timeout git fetch --all && _run_with_timeout git checkout "${SPACK_VERSION}" && _run_with_timeout git pull --rebase || true )
  else
    _log_info "Cloning Spack-Stack %s → %s" "${SPACK_VERSION}" "$spack_dir"
    mkdir -p "$spack_dir"
    _run_with_timeout git clone --branch "${SPACK_VERSION}" --depth 1 https://github.com/JCSDA/spack-stack.git "$spack_dir"
  fi

  # Load spack env
  if [[ -f "${spack_dir}/setup.sh" ]]; then
    # shellcheck source=/dev/null
    source "${spack_dir}/setup.sh"
  elif [[ -f "${spack_dir}/spack/share/spack/setup-env.sh" ]]; then
    # shellcheck source=/dev/null
    source "${spack_dir}/spack/share/spack/setup-env.sh"
  else
    _die "Cannot find spack setup scripts under %s" "${spack_dir}"
  fi

  # Site configs
  if [[ -n "$SITE_CONFIG" ]]; then
    _log_info "Copying site configs (*.yaml) into Spack-Stack site dir"
    mkdir -p "${spack_dir}/config/sites/${SITE}"
    _run_with_timeout rsync -a "${SITE_CONFIG}/" "${spack_dir}/config/sites/${SITE}/"
  fi

  # Cache
  export SPACK_USER_CACHE_PATH="${ROOT_PREFIX}/.spack_cache"
  mkdir -p "${SPACK_USER_CACHE_PATH}"
  _log_debug "SPACK_USER_CACHE_PATH=%s" "${SPACK_USER_CACHE_PATH}"
}

create_env() {
  #BOP
  # !ROUTINE: create_env
  # !DESCRIPTION: Create (if missing) and concretize the requested environment.
  #EOP
  local spack_dir="${ROOT_PREFIX}/spack-stack"
  [[ -f "${spack_dir}/setup.sh" ]] || _die "spack not initialized (missing setup.sh)."
  # shellcheck source=/dev/null
  source "${spack_dir}/setup.sh"

  local env_dir="${ROOT_PREFIX}/envs/${ENV_NAME}"
  mkdir -p "${env_dir}"
  if [[ -n "$ENV_YAML" && -f "$ENV_YAML" ]]; then
    _log_info "Seeding %s with %s" "${ENV_NAME}" "${ENV_YAML}"
    _run_with_timeout rsync -a "$ENV_YAML" "${env_dir}/spack.yaml"
  else
    _log_warn "No env template provided; creating an empty environment."
  fi

  _run_with_timeout spack env create -d "${env_dir}" || true
  _run_with_timeout spack env activate -d "${env_dir}"
  _run_with_timeout spack -e "${env_dir}" concretize -f
  _run_with_timeout spack -e "${env_dir}" install -j "${JOBS}" --fail-fast
  _log_ok "Environment %s installed at %s" "${ENV_NAME}" "${env_dir}"
}

run_baseline_tests() {
  #BOP
  # !ROUTINE: run_baseline_tests
  # !DESCRIPTION: Run site-wide baseline tests if available (NetCDF, NetCDF-CXX4, HDF5, OpenMPI).
  #EOP
  local any=0
  for t in \
    "configs/templates/tests/test_netcdf.sh" \
    "configs/templates/tests/test_netcdf_cxx4.sh" \
    "configs/templates/tests/test_hdf5.sh" \
    "configs/templates/tests/test_openmpi.sh"
  do
    if [[ -x "$t" ]]; then
      any=1; _log_action "Running baseline test: %s" "$(basename "$t")"
      _run_with_timeout "$t" || _die "Baseline test failed: %s" "$(basename "$t")"
    fi
  done
  [[ $any -eq 0 ]] && _log_warn "No baseline tests found; skipping."
}

run_env_tests() {
  #BOP
  # !ROUTINE: run_env_tests
  # !DESCRIPTION: Run env-specific tests if present under configs/templates/<env>/tests/.
  #EOP
  local dir="configs/templates/${ENV_NAME}/tests"
  if [[ -d "$dir" ]]; then
    local tests=()
    mapfile -t tests < <(find "$dir" -maxdepth 1 -type f -name "test_*.sh" -perm -u+x | sort)
    if [[ ${#tests[@]} -eq 0 ]]; then
      _log_warn "No env tests found in %s" "${dir}"
      return 0
    fi
    _log_info "Running %d env tests in %s" "${#tests[@]}" "${dir}"
    for t in "${tests[@]}"; do
      _log_action "→ %s" "$(basename "$t")"
      _run_with_timeout "$t" || _die "Env test failed: %s" "$(basename "$t")"
    done
  else
    _log_warn "Env test directory '%s' not found; skipping env tests." "${dir}"
  fi
}

install_stack() {
  #BOP
  # !ROUTINE: install_stack
  # !DESCRIPTION: Phase 1 — install/refresh Spack-Stack under ROOT_PREFIX.
  #EOP
  detect_site
  setup_site_config
  bootstrap_spack
  _log_ok "[STACK] Spack-Stack ready under %s" "${ROOT_PREFIX}"
}

install_env() {
  #BOP
  # !ROUTINE: install_env
  # !DESCRIPTION: Phase 2 — create and install the requested environment.
  #EOP
  create_env
}

test_phase() {
  #BOP
  # !ROUTINE: test_phase
  # !DESCRIPTION: Phase 3 — run baseline and/or env tests if requested.
  #EOP
  local spack_dir="${ROOT_PREFIX}/spack-stack"
  [[ -f "${spack_dir}/setup.sh" ]] || _die "spack not initialized (missing setup.sh)."
  # shellcheck source=/dev/null
  source "${spack_dir}/setup.sh"

  if [[ $WITH_BASELINE_TESTS -eq 1 ]]; then
    run_baseline_tests
  else
    _log_info "Baseline tests disabled."
  fi

  if [[ $WITH_ENV_TESTS -eq 1 ]]; then
    local env_dir="${ROOT_PREFIX}/envs/${ENV_NAME}"
    if [[ -d "$env_dir" ]]; then
      _run_with_timeout spack env activate -d "${env_dir}"
    else
      _log_warn "Env dir %s not found; env tests might fail." "${env_dir}"
    fi
    run_env_tests
  else
    _log_info "Env tests disabled."
  fi
}

main() {
  _parse_script_args "$@"
  ensure_dirs
  _log_info "[BEGIN] %s on %s" "${_script}" "${_host}"
  _log_info "Root: %s | Spack-Stack: %s | Env: %s" "${ROOT_PREFIX}" "${SPACK_VERSION}" "${ENV_NAME}"

  if [[ $DO_STACK -eq 1 ]]; then install_stack; fi
  if [[ $DO_ENV   -eq 1 ]]; then install_env; fi
  if [[ $DO_TESTS -eq 1 ]]; then test_phase; fi

  _log_ok "[DONE] Completed."
}

# Initialize modules if available (optional for your site)
[[ -r /etc/profile.d/lmod.sh ]] && source /etc/profile.d/lmod.sh || true

main "$@"

