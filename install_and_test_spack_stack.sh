#!/usr/bin/env bash
#BOP
# !ROUTINE: install_and_test_spack_stack.sh
#
# !INTERFACE:
#   install_and_test_spack_stack.sh [COMMON OPTIONS] -- [SCRIPT OPTIONS]
#
# !FUNCTION:
#   Unified entrypoint for managing the Spack-Stack deployment lifecycle
#   across HPC sites. Handles installation, environment creation, and testing
#   phases in a reproducible and modular way.
#
# !DESCRIPTION:
#   This script automates the setup of Spack-Stack and JEDI-related environments
#   for HPC systems (e.g., Egeon, XC50). It provides a structured and safe
#   installation procedure divided into three independent phases:
#
#   (1) **Install/Refresh** the shared Spack-Stack tree (no env creation)
#   (2) **Create/Concretize** a user- or project-specific environment
#   (3) **Test** both baseline and environment-specific functionality
#
#   The workflow is designed to be idempotent, supports dry-run mode, and
#   integrates tightly with the project’s helper library `__helpers__.sh`.
#
#   **Helper integration:**
#     - Logging: `_log_info`, `_log_warn`, `_log_err`, `_log_debug`, `_log_ok`, `_log_action`
#     - Execution: `_run` (honors `--dry-run`)
#     - Argument parsing: `__parse_args__` (handles common options)
#
# !COMMON OPTIONS (handled by __helpers__.sh):
#   -v|--verbose            Verbose logging
#   -q|--quiet              Disable INFO logs
#   -d|--debug              Enable debug messages
#   --dry-run               Log commands without executing them
#   -y|--yes                Auto-confirm operations
#   -f|--fix                Allow corrective actions (mkdirs/symlinks) when supported
#
# !SCRIPT OPTIONS (parsed here):
#   --site NAME             HPC site shortname (e.g., egeon) [default: auto]
#   --spack-version VER     Spack-Stack version/tag (default: ${SPACK_STACK_VERSION:-1.8.0})
#   --spack-root DIR        Root installation prefix [${ROOT_PREFIX:-$HOME/.spack/mpas-bundle}]
#   --env-name NAME         Environment/bundle name (default: ${ENV_NAME:-mpas-bundle})
#   --env-yaml PATH         Template spack.yaml (site-aware) [auto-detected]
#   --site-config DIR       Site configuration directory (compilers.yaml, packages.yaml, etc.)
#   --jobs N                Parallel spack build jobs (default: ${JOBS:-8})
#   --timeout N             Timeout per command (seconds; default: ${TIMEOUT:-900})
#   --gcc-version VER       Minimum GCC required (default: ${GCC_VERSION:-12.3.0})
#   --cmake-min VER         Minimum CMake required (default: ${CMAKE_MIN_VERSION:-3.21})
#   --openmpi-min VER       Minimum OpenMPI required (default: ${OPENMPI_MIN_VERSION:-4.1})
#   --hdf5-min VER          Minimum HDF5 required (default: ${HDF5_MIN_VERSION:-1.12})
#   --only-stack            Execute only Phase 1 (Spack-Stack bootstrap)
#   --only-env              Execute only Phase 2 (Environment creation)
#   --only-tests            Execute only Phase 3 (Testing)
#   --with-baseline-tests   Run baseline validation tests (NetCDF, HDF5, OpenMPI)
#   --with-env-tests        Run environment-specific test suite
#   -h|--help               Display this help message
#
# !ENVIRONMENT:
#   verbose, debug, dry_run  (from __helpers__.sh)
#   SPACK_STACK_VERSION, ROOT_PREFIX, ENV_NAME, JOBS, TIMEOUT
#   /etc/profile.d/lmod.sh is sourced when available to enable module systems.
#
# !EXIT STATUS:
#   0 on success; non-zero on failure (with contextual diagnostics).
#
# !EXAMPLES:
#   # Install shared stack only:
#   ./install_and_test_spack_stack.sh -- --only-stack --spack-version 1.9.3 \
#       --spack-root /mnt/beegfs/das.group --site egeon
#
#   # Create the mpas-bundle environment:
#   ./install_and_test_spack_stack.sh -- --only-env --spack-root /mnt/beegfs/das.group \
#       --env-name mpas-bundle
#
#   # Run both baseline and environment tests:
#   ./install_and_test_spack_stack.sh -- --only-tests --with-baseline-tests --with-env-tests
#
# !SEE ALSO:
#   Spack-Stack documentation, JEDI build guides, site-specific README files.
#
# !AUTHOR:
#   João Gerd Zell de Mattos <joao.gerd@gmail.com>
#
# !LICENSE:
#   LGPL-3.0 (as per project policy) or the accompanying project license file.
#EOP

#BOC
set -Eeuo pipefail
umask 022
IFS=$'\n\t'

# -----------------------------------------------------------
# Locate and source project helper library (__helpers__.sh)
# -----------------------------------------------------------
__HERE__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if   [[ -r "${__HERE__}/__helpers__.sh" ]]; then source "${__HERE__}/__helpers__.sh"
elif [[ -r "./__helpers__.sh"          ]]; then source "./__helpers__.sh"
elif [[ -r "${__HERE__}/lib/__helpers__.sh" ]]; then source "${__HERE__}/lib/__helpers__.sh"
else
  echo "[ERROR] __helpers__.sh not found; this script requires it." >&2
  exit 2
fi

# -----------------------------------------------------------
# Local aliases for convenience and house style
# -----------------------------------------------------------
info()  { _log_info  "$@"; }
warn()  { _log_warn  "$@"; }
error() { _log_err   "$@"; }
debug() { _log_debug "$@"; }
die()   { _die       "$@"; }

# -----------------------------------------------------------
# Inline help extractor (uses script header)
# -----------------------------------------------------------
usage() {
  sed -n '1,200p' "$0" | sed -n '/#BOP/,/#EOP/p' | sed 's/^# \?//'
  cat <<'USAGE'

Script options (parsed after __helpers__ common flags):
  --site NAME             e.g., egeon
  --spack-version VER     e.g., 1.8.0
  --spack-root DIR        root installation prefix
  --env-name NAME         e.g., mpas-bundle
  --env-yaml PATH         spack.yaml template
  --site-config DIR       site configs (compilers.yaml, packages.yaml, ...)
  --jobs N                parallel spack builds
  --timeout N             per-command timeout seconds
  --gcc-version VER       minimum GCC to bootstrap
  --cmake-min VER         minimum CMake required
  --openmpi-min VER       minimum OpenMPI required
  --hdf5-min VER          minimum HDF5 required
  --only-stack | --only-env | --only-tests
  --with-baseline-tests   enable baseline tests
  --with-env-tests        enable env-specific tests
  -h|--help               this help
USAGE
}

# -----------------------------------------------------------
# Execute a command with optional timeout (respects dry-run)
# -----------------------------------------------------------
_run_with_timeout() {
  local timeout_s="${TIMEOUT:-900}"
  if command -v timeout >/dev/null 2>&1; then
    if [[ "${dry_run:-false}" == "true" ]]; then
      _log_info "[DRY-RUN] timeout %s %s" "$timeout_s" "$*"
      return 0
    fi
    timeout --preserve-status "$timeout_s" "$@"
  else
    _run "$@"
  fi
}

# -----------------------------------------------------------
# Lifecycle timing & traps
# -----------------------------------------------------------
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
#EOC

# -------------------------------
# Defaults (overridable via flags)
# -------------------------------
# URL of the Spack-Stack Git repository. The installer clones from this remote.
# May be overridden to use a fork or an internal mirror.
: "${SPACK_STACK_GIT:=https://github.com/JCSDA/spack-stack.git}"

# Name of the Spack environment that will be created/activated.
# Used for logs, paths, and spack env operations.
: "${ENV_NAME:=mpas-bundle}"

# Optional path to a site-aware spack.yaml template.
# When set, this file is copied into the environment directory before concretization.
: "${ENV_YAML:=}"

# Root prefix for the Spack-Stack installation (stack + envs).
# Designed to be user- or group-owned, requiring no root privileges.
: "${ROOT_PREFIX:=${HOME}/.spack/${ENV_NAME}}"

# Git tag or branch of the Spack-Stack repository to use.
# Can be overridden to test newer versions or custom branches.
: "${SPACK_STACK_VERSION:=1.8.0}"

# Short identifier of the HPC site (e.g., egeon, xc50).
# Determines the subdirectory used under config/sites/<SITE_NAME>.
: "${SITE_NAME:=egeon}"

# Directory containing the site configuration YAMLs (config.yaml, packages.yaml, etc.).
# If not provided, the script attempts to auto-detect it.
: "${SITE_CONFIG:=}"

# Timeout in seconds for commands executed by _run_with_timeout.
# Used for long operations like git clone or spack install.
: "${TIMEOUT:=900}"

# Base directory for shared Spack-Stack storage (BeeGFS, Lustre, etc.).
# This path appears in config.yaml (install_tree, build_stage, caches).
: "${STACK_ROOT:=/mnt/beegfs/das.group/spack-stack}"

# Default number of parallel build jobs used by Spack.
# Should match the available cores on the build node.
: "${BUILD_JOBS:=8}"

# GCC version to bootstrap and register as the site’s default compiler.
# Used in packages.yaml and compilers.yaml templates.
: "${GCC_VERSION:=12.3.0}"

# Minimum required CMake version (used in packages.yaml).
# Ensures compatibility with the JEDI build system.
: "${CMAKE_MIN_VERSION:=3.21}"

# Minimum required OpenMPI version (used in packages.yaml).
# Can later be extended with fabrics=ucx and schedulers=slurm when IB is validated.
: "${OPENMPI_MIN_VERSION:=4.1}"

# Minimum required HDF5 version (used in packages.yaml).
# Ensures JEDI-compatible variants (+hl +fortran +shared).
: "${HDF5_MIN_VERSION:=1.12}"

# Phase toggle: enables Phase 1 (Spack-Stack installation).
# Set to 0 to skip stack installation.
: "${DO_STACK:=1}"

# Phase toggle: enables Phase 2 (environment creation/installation).
# Set to 0 to skip environment creation.
: "${DO_ENV:=1}"

# Phase toggle: enables Phase 3 (test execution).
# Disabled by default; reserved for future test hooks.
: "${DO_TESTS:=0}"

# Enables baseline tests (NetCDF, HDF5, MPI sanity checks) during Phase 3.
# Requires DO_TESTS=1 to take effect.
: "${WITH_BASELINE_TESTS:=0}"

# Enables environment-specific tests under configs/templates/<env>/tests.
# Requires DO_TESTS=1 to take effect.
: "${WITH_ENV_TESTS:=0}"


# ---------------- Arg parsing ----------------
#BOP
# !ROUTINE: _parse_script_args
#
# !INTERFACE:
#   _parse_script_args "$@"
#
# !FUNCTION:
#   Performs argument parsing for script-specific flags after the generic
#   argument handling provided by `__helpers__.sh`.
#   This routine extracts Spack-Stack site parameters, environment setup
#   options, version pins, and phase toggles.
#
# !DESCRIPTION:
#   The function executes two parsing passes:
#   1. Delegates to `__parse_args__` (from __helpers__.sh) to handle global
#      options like verbosity, debug mode, and dry-run.
#   2. Processes script-specific flags, storing leftovers for downstream
#      consumption.
#
#   It supports defining site-related parameters (e.g., --site, --site-config),
#   version controls (e.g., --spack-version, --gcc-version), environment
#   metadata (--env-name, --env-yaml), and runtime behavior toggles such as
#   --only-stack / --only-env / --only-tests.
#
# !OPTIONS:
#   --site NAME             HPC site short name (e.g., egeon)
#   --spack-version VER     Spack-Stack tag or branch
#   --spack-root DIR        Installation prefix for Spack-Stack
#   --env-name NAME         Spack environment name
#   --env-yaml PATH         Path to the spack.yaml template
#   --site-config DIR       Path to site-specific YAMLs (config, packages, etc.)
#   --jobs N                Parallel build jobs for Spack
#   --timeout N             Timeout (seconds) for long operations
#   --gcc-version VER       GCC version to bootstrap and register
#   --cmake-min VER         Minimum CMake version required
#   --openmpi-min VER       Minimum OpenMPI version required
#   --hdf5-min VER          Minimum HDF5 version required
#   --only-stack            Execute only Spack-Stack installation
#   --only-env              Execute only environment creation/installation
#   --only-tests            Execute only test phase
#   --with-baseline-tests   Enable baseline tests (NetCDF/HDF5/OpenMPI)
#   --with-env-tests        Enable environment-specific tests
#   -h|--help               Show help message and exit
#
# !OUTPUTS:
#   Sets environment variables consumed by subsequent script phases:
#   SITE_NAME, SPACK_STACK_VERSION, ROOT_PREFIX, ENV_NAME, ENV_YAML,
#   SITE_CONFIG, JOBS, TIMEOUT, GCC_VERSION, CMAKE_MIN_VERSION,
#   OPENMPI_MIN_VERSION, HDF5_MIN_VERSION, DO_STACK, DO_ENV, DO_TESTS,
#   WITH_BASELINE_TESTS, WITH_ENV_TESTS.
#
# !EXAMPLE:
#   _parse_script_args --site egeon --spack-version 1.8.0 \
#                      --spack-root /mnt/beegfs/das.group \
#                      --env-name mpas-bundle --only-env
#
# !SEE ALSO:
#   __parse_args__, install_stack, install_env, test_phase
#EOP
_parse_script_args() {
#BOC
  PARSER_WRITE_LEFTOVERS=1 __parse_args__ "$@"

  local opt
  local -a rest=()
  while [[ ${#leftover_args[@]} -gt 0 ]]; do
    opt="${leftover_args[0]}"
    leftover_args=("${leftover_args[@]:1}")
    case "$opt" in
      --site)                SITE_NAME="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --spack-version)       SPACK_STACK_VERSION="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --spack-root)          ROOT_PREFIX="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --env-name)            ENV_NAME="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --env-yaml)            ENV_YAML="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --site-config)         SITE_CONFIG="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --jobs)                JOBS="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --timeout)             TIMEOUT="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --gcc-version)         GCC_VERSION="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --cmake-min)           CMAKE_MIN_VERSION="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --openmpi-min)         OPENMPI_MIN_VERSION="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --hdf5-min)            HDF5_MIN_VERSION="${leftover_args[0]}"; leftover_args=("${leftover_args[@]:1}");;
      --only-stack)          DO_STACK=1; DO_ENV=0; DO_TESTS=0;;
      --only-env)            DO_STACK=0; DO_ENV=1; DO_TESTS=0;;
      --only-tests)          DO_STACK=0; DO_ENV=0; DO_TESTS=1;;
      --with-baseline-tests) WITH_BASELINE_TESTS=1;;
      --with-env-tests)      WITH_ENV_TESTS=1;;
      -h|--help)             usage; _exit_ok;;
      --)                    rest+=("${leftover_args[@]}"); break;;
      *)                     rest+=("$opt");;
    esac
  done
  leftover_args=("${rest[@]}")
  export SPACK_STACK_VERSION ROOT_PREFIX ENV_NAME JOBS TIMEOUT
#EOC
}

#BOP
# !ROUTINE: ensure_dirs
#
# !INTERFACE:
#   ensure_dirs
#
# !FUNCTION:
#   Ensures that the required directory structure exists before execution.
#   Creates the root installation directory for Spack-Stack and a timestamped
#   log directory for this run.
#
# !DESCRIPTION:
#   This function creates:
#     - ${ROOT_PREFIX}: the base directory where Spack-Stack and environments
#       will be installed or cloned.
#     - ./logs/${_tsdir}: a timestamped directory to store logs from this run,
#       ensuring reproducibility and traceability across multiple invocations.
#
#   It is safe to call multiple times, as `mkdir -p` ensures idempotency.
#
# !EXAMPLE:
#   ensure_dirs
#
# !OUTPUTS:
#   Creates directories if missing:
#     ${ROOT_PREFIX}
#     ./logs/${_tsdir}
#
# !SEE ALSO:
#   bootstrap_spack, create_env
#EOP
ensure_dirs() {
  #BOC
  mkdir -p "${ROOT_PREFIX}" "./logs/${_tsdir}"
  #EOC
}

#BOP
# !ROUTINE: detect_site
#
# !INTERFACE:
#   detect_site
#
# !FUNCTION:
#   Determines the site (cluster) configuration automatically from the hostname
#   if not explicitly provided via the `--site` flag.
#
# !DESCRIPTION:
#   This routine sets the variable `SITE_NAME` to identify the running site
#   (e.g., `egeon`, `xc50`, or `generic`) for proper configuration of the
#   Spack-Stack installation.
#
#   If the user already provided a value for `SITE_NAME`, the function simply
#   logs the site name and returns immediately.
#   Otherwise, it performs a pattern match on the short hostname:
#     - hostnames starting with “egeon” → SITE_NAME="egeon"
#     - hostnames starting with “xc50” or “cray” → SITE_NAME="xc50"
#     - all others → SITE_NAME="generic"
#
#   The resolved site name is logged via `_log_info` and later used to locate
#   the corresponding configuration directory under:
#     config/sites/${SITE_NAME}/
#
# !OUTPUTS:
#   - Sets `SITE_NAME` variable.
#   - Logs the detected or provided site name.
#
# !EXAMPLE:
#   detect_site
#   # Example output:
#   # [INFO] Auto-detected site: egeon
#
# !SEE ALSO:
#   setup_site_config, bootstrap_spack
#EOP
detect_site() {
  #BOC
  [[ -n "$SITE_NAME" ]] && { _log_info "Site provided: %s" "$SITE_NAME"; return 0; }
  case "$_host" in
    egeon*|egeon) SITE_NAME="egeon";;
    xc50*|cray*)  SITE_NAME="xc50";;
    *)            SITE_NAME="generic";;
  esac
  _log_info "Auto-detected site: %s" "$SITE_NAME"
  #EOC
}

#BOP
# !ROUTINE: setup_site_config
#
# !INTERFACE:
#   setup_site_config
#
# !FUNCTION:
#   Resolves and validates the locations of site-specific configuration
#   directories and environment templates required for Spack-Stack setup.
#
# !DESCRIPTION:
#   This routine ensures that the correct YAML configuration files are located
#   and registered before the Spack-Stack installation or environment creation
#   begins.
#
#   The search logic proceeds as follows:
#
#   1. **Site Configuration (`SITE_CONFIG`)**
#      - If `SITE_CONFIG` is not provided via CLI or environment variable,
#        the function searches common locations in this order:
#          - `configs/sites/${SITE_NAME}`
#          - `configs/${SITE_NAME}`
#      - Once found, the directory path is stored in `SITE_CONFIG`.
#
#   2. **Environment Template (`ENV_YAML`)**
#      - If `ENV_YAML` is not already defined, the function searches for
#        Spack environment templates associated with the current site and
#        environment name (`ENV_NAME`):
#          - `configs/templates/${ENV_NAME}/spack-${SITE_NAME}.yaml`
#          - `configs/templates/${ENV_NAME}/spack.yaml`
#      - The first matching file found is assigned to `ENV_YAML`.
#
#   3. **Logging Behavior**
#      - If both paths are successfully resolved, `_log_info` messages are issued.
#      - If one or both are missing, `_log_warn` is used to indicate fallback to defaults.
#
#   This mechanism allows a single installation script to handle multiple HPC
#   sites automatically, without user intervention.
#
# !OUTPUTS:
#   - Sets `SITE_CONFIG` and/or `ENV_YAML` variables.
#   - Emits log messages indicating whether configurations were found or defaulted.
#
# !EXAMPLE:
#   setup_site_config
#   # Output example:
#   # [INFO] Using site-config: configs/sites/egeon
#   # [INFO] Using env template: configs/templates/mpas-bundle/spack-egeon.yaml
#
# !SEE ALSO:
#   detect_site, bootstrap_spack, create_env
#EOP
setup_site_config() {
  #BOC
  if [[ -z "$SITE_CONFIG" ]]; then
    for d in "configs/sites/${SITE_NAME}" "configs/${SITE_NAME}" ; do
      [[ -d "$d" ]] && { SITE_CONFIG="$d"; break; }
    done
  fi

  if [[ -z "$ENV_YAML" ]]; then
    for f in "configs/templates/${ENV_NAME}/spack-${SITE_NAME}.yaml" \
             "configs/templates/${ENV_NAME}/spack.yaml"; do
      [[ -f "$f" ]] && { ENV_YAML="$f"; break; }
    done
  fi

  [[ -n "$SITE_CONFIG" ]] && _log_info "Using site-config: %s" "$SITE_CONFIG" \
    || _log_warn "No site-config directory found (will rely on defaults)."

  [[ -n "$ENV_YAML"   ]] && _log_info "Using env template: %s" "$ENV_YAML" \
    || _log_warn "No env template (spack.yaml) provided; you may create one."
  #EOC
}

#BOP
# !ROUTINE: render_site_templates
#
# !INTERFACE:
#   render_site_templates
#
# !FUNCTION:
#   Renders all site configuration templates (*.yaml.in) by substituting
#   environment variables into finalized YAML configuration files.
#
# !DESCRIPTION:
#   This routine processes template files (`*.yaml.in`) in the current
#   site configuration directory (`SITE_DIR`), replacing placeholders with
#   actual values from environment variables using the `envsubst` utility.
#
#   The function performs the following steps:
#
#   1. **Dependency Check**
#      - Verifies that `envsubst` (part of GNU gettext) is available.
#        If not found, logs a warning and skips template rendering.
#
#   2. **Environment Export**
#      - Exports key environment variables used within templates:
#        `STACK_ROOT`, `SPACK_STACK_VERSION`, `GCC_VERSION`, `BUILD_JOBS`,
#        `CMAKE_MIN_VERSION`, `OPENMPI_MIN_VERSION`, `HDF5_MIN_VERSION`,
#        and `SITE_NAME`.
#
#   3. **Template Rendering**
#      - Iterates over the standard configuration templates:
#        `config.yaml.in`, `packages.yaml.in`, and `modules.yaml.in`.
#      - For each existing file, generates its corresponding output:
#        - Input:  `${SITE_DIR}/${t}.in`
#        - Output: `${SITE_DIR}/${t}`
#      - Logs each rendered file via `_log_info`.
#
#   This mechanism allows site-specific configurations to remain flexible,
#   parameterized, and version-controlled without manual intervention.
#
# !INPUTS:
#   - Requires `SITE_DIR` to be set by `bootstrap_spack()`.
#   - Expects template files `${SITE_DIR}/config.yaml.in`, etc.
#
# !OUTPUTS:
#   - Creates rendered YAML files in `${SITE_DIR}`:
#       config.yaml, packages.yaml, modules.yaml
#
# !EXAMPLE:
#   render_site_templates
#   # Output example:
#   # [INFO] Rendered config.yaml from template.
#   # [INFO] Rendered packages.yaml from template.
#
# !SEE ALSO:
#   bootstrap_spack, setup_site_config, bootstrap_compiler
#EOP
render_site_templates() {
  #BOC
  # SITE_DIR must be set by bootstrap_spack()
  command -v envsubst >/dev/null 2>&1 || { _log_warn "envsubst not found; skipping template rendering."; return 0; }

  # Export variables so envsubst can see them
  export STACK_ROOT SPACK_STACK_VERSION GCC_VERSION BUILD_JOBS \
         CMAKE_MIN_VERSION OPENMPI_MIN_VERSION HDF5_MIN_VERSION SITE_NAME

  for t in config.yaml packages.yaml modules.yaml; do
    if [[ -f "${SITE_DIR}/${t}.in" ]]; then
      envsubst < "${SITE_DIR}/${t}.in" > "${SITE_DIR}/${t}"
      _log_info "Rendered %s from template." "${t}"
    fi
  done
  #EOC
}

#BOP
# !ROUTINE: bootstrap_compiler
#
# !INTERFACE:
#   bootstrap_compiler
#
# !FUNCTION:
#   Ensures that a modern GCC compiler (gcc@${GCC_VERSION}) is available,
#   installed via Spack, and registered in the site configuration scope.
#
# !DESCRIPTION:
#   This function automates the entire compiler bootstrapping process
#   required for a clean Spack-Stack installation on HPC sites.
#   It is fully non-interactive and safe for repeated execution.
#
#   Steps performed:
#
#   1. **Initialization**
#      - Defines local paths:
#        - `${spack_dir}` → Root of Spack-Stack.
#        - `${site_dir}`  → Site configuration directory under config/sites/${SITE_NAME}.
#      - Verifies that `${spack_dir}/setup.sh` exists, otherwise terminates
#        execution with an error.
#      - Sources `setup.sh` to load Spack into the current shell session.
#
#   2. **Site Configuration Setup**
#      - Ensures `${site_dir}` exists.
#      - Exports both `SPACK_SYSTEM_CONFIG_PATH` and `SPACK_USER_CONFIG_PATH`
#        to point to the site configuration directory.
#      - Logs debug information for these environment variables.
#
#   3. **Compiler Installation**
#      - Checks whether gcc@${GCC_VERSION} is already installed
#        using `spack find`.
#      - If missing, installs it with timeout support using `_run_with_timeout`.
#      - If present, logs and skips rebuild to save time.
#
#   4. **Compiler Registration**
#      - Determines the GCC installation prefix using `spack location -i`.
#      - Loads the compiler into the current shell environment
#        (`spack load --sh gcc@${GCC_VERSION}`).
#      - Registers the compiler under the **site scope** using:
#        `spack compiler find --scope site ${gcc_prefix}`.
#      - This ensures the `compilers.yaml` file under `${site_dir}`
#        includes the correct paths for GCC.
#
#   5. **Completion**
#      - Emits a success log confirming that the compiler bootstrap
#        process has completed successfully.
#
# !OUTPUTS:
#   - Installs gcc@${GCC_VERSION} if missing.
#   - Updates `${site_dir}/compilers.yaml` with correct compiler paths.
#
# !EXAMPLE:
#   bootstrap_compiler
#   # Output:
#   # [INFO] Installing gcc@12.3.0 (bootstrap)
#   # [OK] Compiler bootstrap complete (gcc@12.3.0)
#
# !SEE ALSO:
#   bootstrap_spack, render_site_templates, create_env
#EOP
bootstrap_compiler() {
  #BOC
  local spack_dir="${ROOT_PREFIX}/spack-stack"
  local site_dir="${spack_dir}/config/sites/${SITE_NAME}"

  [[ -f "${spack_dir}/setup.sh" ]] || die "spack not initialized (missing setup.sh)."
  # shellcheck source=/dev/null
  source "${spack_dir}/setup.sh"

  mkdir -p "${site_dir}"
  export SPACK_SYSTEM_CONFIG_PATH="${site_dir}"
  export SPACK_USER_CONFIG_PATH="${site_dir}"
  _log_debug "SPACK_SYSTEM_CONFIG_PATH=%s" "${SPACK_SYSTEM_CONFIG_PATH}"
  _log_debug "SPACK_USER_CONFIG_PATH=%s"   "${SPACK_USER_CONFIG_PATH}"

  if ! spack find --format "{name}@{version}" gcc | grep -q "^gcc@${GCC_VERSION}\$"; then
    _log_info "Installing gcc@%s (bootstrap)" "${GCC_VERSION}"
    _run_with_timeout spack install -y "gcc@${GCC_VERSION}"
  else
    _log_info "gcc@%s already installed; skipping build" "${GCC_VERSION}"
  fi

  local gcc_prefix
  gcc_prefix="$(spack location -i "gcc@${GCC_VERSION}")"

  _log_info "Loading gcc@%s into current shell" "${GCC_VERSION}"
  # shellcheck disable=SC2046
  eval "$(spack load --sh gcc@${GCC_VERSION})"

  _log_info "Registering compiler under site scope: %s" "${gcc_prefix}"
  _run_with_timeout spack compiler find --scope site "${gcc_prefix}"

  _log_ok "Compiler bootstrap complete (gcc@%s)" "${GCC_VERSION}"
  #EOC
}

#BOP
# !ROUTINE: bootstrap_spack
#
# !INTERFACE:
#   bootstrap_spack
#
# !FUNCTION:
#   Prepares or refreshes the Spack-Stack tree under ${ROOT_PREFIX}, sources
#   the Spack environment, installs site configuration files, renders templates,
#   configures site-scoped Spack paths, and triggers compiler bootstrap.
#
# !DESCRIPTION:
#   The routine implements an idempotent setup for Spack-Stack:
#
#   1) **Clone/Refresh**
#      - If ${ROOT_PREFIX}/spack-stack is already a Git checkout, it fetches tags,
#        checks out ${SPACK_STACK_VERSION}, and initializes submodules.
#      - Otherwise, it clones the requested branch/tag with submodules initialized.
#
#   2) **Spack Environment**
#      - Sources the Spack setup scripts (`setup.sh` or `spack/share/spack/setup-env.sh`)
#        to make the `spack` CLI available in the current shell.
#
#   3) **Site Config**
#      - If a `SITE_CONFIG` directory is provided, copies all YAMLs (and optionally
#        `.in` templates) into `config/sites/${SITE_NAME}/` using `rsync` (or `cp` fallback).
#      - Exposes `SITE_DIR` for downstream functions.
#
#   4) **Template Rendering**
#      - Calls `render_site_templates` to transform `*.yaml.in` into final YAMLs using
#        environment substitution (envsubst).
#
#   5) **Site Scope**
#      - Sets `SPACK_SYSTEM_CONFIG_PATH` and `SPACK_USER_CONFIG_PATH` to `SITE_DIR`
#        so reads/writes (e.g., compilers.yaml) happen in the site configuration space,
#        ensuring reproducibility and isolation from `~/.spack`.
#      - Configures `SPACK_USER_CACHE_PATH` for downloaded sources/metadata caching.
#
#   6) **Compiler Bootstrap**
#      - Invokes `bootstrap_compiler` to install and register `gcc@${GCC_VERSION}`
#        at the site scope if not already present.
#
#   The function is safe to run multiple times, only performing the minimum work
#   required when the target state already exists.
#
# !INPUTS:
#   ROOT_PREFIX, SPACK_STACK_VERSION, SITE_NAME, SITE_CONFIG (optional)
#
# !OUTPUTS:
#   - Populates/updates ${ROOT_PREFIX}/spack-stack
#   - Ensures site configs under ${ROOT_PREFIX}/spack-stack/config/sites/${SITE_NAME}
#   - Sets SPACK_* environment variables for site scope and cache
#   - Installs/registers gcc@${GCC_VERSION} (delegated to bootstrap_compiler)
#
# !EXAMPLE:
#   bootstrap_spack
#   # [INFO] Cloning/Refreshing Spack-Stack …
#   # [INFO] Copying site configs …
#   # [INFO] Rendered config.yaml from template.
#   # [OK]   Compiler bootstrap complete (gcc@12.3.0)
#
# !SEE ALSO:
#   render_site_templates, bootstrap_compiler, setup_site_config
#EOP
bootstrap_spack() {
  #BOC
  local spack_dir="${ROOT_PREFIX}/spack-stack"

  # Clone or refresh Spack-Stack
  if [[ -d "$spack_dir/.git" ]]; then
    _log_info "Refreshing Spack-Stack @ %s (version: %s)" "$spack_dir" "${SPACK_STACK_VERSION}"
    ( cd "$spack_dir" && \
      _run_with_timeout git fetch --all --tags && \
      _run_with_timeout git checkout "${SPACK_STACK_VERSION}" && \
      _run_with_timeout git submodule update --init --recursive )
  else
    _log_info "Cloning Spack-Stack %s → %s" "${SPACK_STACK_VERSION}" "$spack_dir"
    mkdir -p "$spack_dir"
    _run_with_timeout git clone --recurse-submodules --branch "${SPACK_STACK_VERSION}" \
      "${SPACK_STACK_GIT}" "$spack_dir"
  fi

  # Source Spack environment (make spack CLI available)
  if   [[ -f "${spack_dir}/setup.sh" ]]; then source "${spack_dir}/setup.sh"
  elif [[ -f "${spack_dir}/spack/share/spack/setup-env.sh" ]]; then source "${spack_dir}/spack/share/spack/setup-env.sh"
  else die "Cannot find spack setup scripts under %s" "${spack_dir}"; fi
  # shellcheck source=/dev/null

  # Install site configs (if provided)
  if [[ -n "$SITE_CONFIG" ]]; then
    _log_info "Copying site configs (*.yaml) into Spack-Stack site dir"
    mkdir -p "${spack_dir}/config/sites/${SITE_NAME}"
    if command -v rsync >/dev/null 2>&1; then
      _run_with_timeout rsync -a "${SITE_CONFIG}/" "${spack_dir}/config/sites/${SITE_NAME}/"
    else
      _run_with_timeout cp -r "${SITE_CONFIG}/." "${spack_dir}/config/sites/${SITE_NAME}/"
    fi
  fi

  # Site directory + template rendering
  SITE_DIR="${spack_dir}/config/sites/${SITE_NAME}"
  export SITE_DIR
  render_site_templates

  # Configure site scope + caches
  export SPACK_SYSTEM_CONFIG_PATH="${SITE_DIR}"
  export SPACK_USER_CONFIG_PATH="${SITE_DIR}"
  export SPACK_USER_CACHE_PATH="${ROOT_PREFIX}/.spack_cache"
  mkdir -p "${SPACK_USER_CACHE_PATH}"
  _log_debug "SPACK_SYSTEM_CONFIG_PATH=%s" "${SPACK_SYSTEM_CONFIG_PATH}"
  _log_debug "SPACK_USER_CONFIG_PATH=%s"   "${SPACK_USER_CONFIG_PATH}"
  _log_debug "SPACK_USER_CACHE_PATH=%s"    "${SPACK_USER_CACHE_PATH}"

  # Ensure GCC toolchain is installed and registered for this site
  bootstrap_compiler
  #EOC
}

#BOP
# !ROUTINE: create_env
#
# !INTERFACE:
#   create_env
#
# !FUNCTION:
#   Creates, seeds, concretizes, and installs a Spack environment under
#   ${ROOT_PREFIX}/envs/${ENV_NAME}, using a provided or default spack.yaml template.
#
# !DESCRIPTION:
#   This routine automates the setup of an environment (bundle) in Spack-Stack.
#   It can be executed repeatedly and safely to refresh or reinitialize the environment.
#
#   The sequence is as follows:
#
#   1) **Spack Setup**
#      - Verifies that Spack is initialized by checking `${spack_dir}/setup.sh`.
#      - Sources the setup script to make the `spack` command available.
#
#   2) **Environment Directory**
#      - Defines `${env_dir}` as `${ROOT_PREFIX}/envs/${ENV_NAME}`.
#      - Ensures the directory exists before proceeding.
#
#   3) **Template Seeding**
#      - If `ENV_YAML` is defined and points to a valid file, it is copied into
#        `${env_dir}/spack.yaml` using `rsync` (preferred) or `cp` as a fallback.
#      - Logs the operation for traceability.
#      - If no template is found, logs a warning and allows Spack to create an empty environment.
#
#   4) **Environment Creation and Installation**
#      - Executes:
#          spack env create -d ${env_dir}
#          spack env activate -d ${env_dir}
#          spack -e ${env_dir} concretize -f
#          spack -e ${env_dir} install -j ${JOBS} --fail-fast
#      - The concretization ensures all dependencies are fully resolved.
#      - Installation uses parallel jobs defined by ${JOBS}.
#
#   5) **Completion**
#      - Logs a success message upon successful installation of the environment.
#
# !INPUTS:
#   - ROOT_PREFIX, ENV_NAME, ENV_YAML, JOBS
#
# !OUTPUTS:
#   - Creates ${ROOT_PREFIX}/envs/${ENV_NAME}/spack.yaml (if missing)
#   - Installs all concretized dependencies for the environment
#
# !EXAMPLE:
#   create_env
#   # Output:
#   # [INFO] Seeding mpas-bundle with configs/templates/mpas-bundle/spack-egeon.yaml
#   # [OK]   Environment mpas-bundle installed at /mnt/beegfs/das.group/envs/mpas-bundle
#
# !SEE ALSO:
#   bootstrap_spack, render_site_templates, setup_site_config
#EOP
create_env() {
  #BOC
  local spack_dir="${ROOT_PREFIX}/spack-stack"
  [[ -f "${spack_dir}/setup.sh" ]] || die "spack not initialized (missing setup.sh)."
  # shellcheck source=/dev/null
  source "${spack_dir}/setup.sh"

  local env_dir="${ROOT_PREFIX}/envs/${ENV_NAME}"
  mkdir -p "${env_dir}"

  if [[ -n "$ENV_YAML" && -f "$ENV_YAML" ]]; then
    _log_info "Seeding %s with %s" "${ENV_NAME}" "${ENV_YAML}"
    if command -v rsync >/dev/null 2>&1; then
      _run_with_timeout rsync -a "$ENV_YAML" "${env_dir}/spack.yaml"
    else
      _run_with_timeout cp -f "$ENV_YAML" "${env_dir}/spack.yaml"
    fi
  else
    _log_warn "No env template provided; creating empty environment (spack env create)."
  fi

  _run_with_timeout spack env create -d "${env_dir}" || true
  _run_with_timeout spack env activate -d "${env_dir}"
  _run_with_timeout spack -e "${env_dir}" concretize -f
  _run_with_timeout spack -e "${env_dir}" install -j "${JOBS}" --fail-fast
  _log_ok "Environment %s installed at %s" "${ENV_NAME}" "${env_dir}"
  #EOC
}

#BOP
# !ROUTINE: run_baseline_tests
#
# !INTERFACE:
#   run_baseline_tests
#
# !FUNCTION:
#   Executes baseline validation tests for core dependencies (NetCDF, NetCDF-CXX4,
#   HDF5, OpenMPI) to verify that the installed toolchain and libraries are working
#   correctly in the current Spack-Stack setup.
#
# !DESCRIPTION:
#   This routine runs a predefined set of test scripts located under
#   `configs/templates/common-tests/`. These tests ensure that the baseline
#   environment is correctly configured before proceeding with more advanced
#   environment-specific checks.
#
#   The tests typically verify:
#     - NetCDF: ability to compile and link C/Fortran test programs.
#     - NetCDF-CXX4: C++ API linkage and runtime functionality.
#     - HDF5: basic I/O read/write tests.
#     - OpenMPI: MPI run sanity (mpicc/mpirun execution).
#
#   The function:
#     1. Iterates over known test script paths within the standard directory.
#     2. Checks if each script exists and is executable (`-x`).
#     3. Runs each test via `_run_with_timeout`, logging progress with `_log_action`.
#     4. On failure, aborts with `die` to prevent continuation on invalid builds.
#     5. If no valid test scripts are found, logs a warning message instead.
#
# !INPUTS:
#   - Expects test scripts under: configs/templates/common-tests/
#   - Uses internal helper: _run_with_timeout
#
# !OUTPUTS:
#   - Executes test scripts for baseline dependencies.
#   - Logs the result of each test (INFO/ACTION/FAIL/WARN).
#
# !EXAMPLE:
#   run_baseline_tests
#   # Output:
#   # [ACTION] Running baseline test: test_hdf5.sh
#   # [ACTION] Running baseline test: test_openmpi.sh
#   # [WARN]   No baseline tests found under configs/templates/common-tests; skipping.
#
# !SEE ALSO:
#   run_env_tests, create_env, bootstrap_spack
#EOP
run_baseline_tests() {
  #BOC
  # usa o diretório padronizado do repo: configs/templates/common-tests/
  local any=0
  local base_dir="configs/templates/common-tests"

  for t in "${base_dir}/test_netcdf.sh" \
           "${base_dir}/test_netcdf_cxx4.sh" \
           "${base_dir}/test_hdf5.sh" \
           "${base_dir}/test_openmpi.sh"
  do
    if [[ -x "$t" ]]; then
      any=1
      _log_action "Running baseline test: %s" "$(basename "$t")"
      _run_with_timeout "$t" || die "Baseline test failed: %s" "$(basename "$t")"
    fi
  done

  [[ $any -eq 0 ]] && _log_warn "No baseline tests found under %s; skipping." "${base_dir}"
  #EOC
}

#BOP
# !ROUTINE: run_env_tests
#
# !INTERFACE:
#   run_env_tests
#
# !FUNCTION:
#   Executes environment-specific test scripts located under
#   `configs/templates/${ENV_NAME}/tests/`, verifying that all
#   environment dependencies and configurations work as expected.
#
# !DESCRIPTION:
#   This routine automatically discovers and runs all executable test
#   scripts (`test_*.sh`) for the currently selected environment (`ENV_NAME`).
#   These tests are meant to validate that the built environment (e.g. mpas-bundle)
#   runs correctly and that the compiled stack integrates with MPI, NetCDF, etc.
#
#   The function performs the following steps:
#
#   1) **Locate Test Directory**
#      - Sets the expected directory path:
#        `configs/templates/${ENV_NAME}/tests`.
#      - If the directory does not exist, logs a warning and exits.
#
#   2) **Discover Tests**
#      - Uses `find` to collect all executable scripts matching `test_*.sh`.
#      - If no tests are found, logs a warning and exits gracefully.
#
#   3) **Execute Tests**
#      - Logs the number of detected tests and iterates through each one.
#      - For each test:
#         - Logs its execution via `_log_action`.
#         - Runs it under timeout control via `_run_with_timeout`.
#         - If any test fails, terminates execution via `die` with a clear message.
#
#   This mechanism ensures consistent testing and validation across multiple
#   environments (e.g. `mpas-bundle`, `fv3-bundle`, etc.) without requiring
#   manual test selection.
#
# !INPUTS:
#   - ENV_NAME: Environment name (used to resolve the test directory).
#   - Tests located in configs/templates/${ENV_NAME}/tests/.
#
# !OUTPUTS:
#   - Executes each test script sequentially.
#   - Logs all progress and results (INFO/ACTION/WARN/FAIL).
#
# !EXAMPLE:
#   run_env_tests
#   # Output:
#   # [INFO] Running 3 env tests in configs/templates/mpas-bundle/tests
#   # [ACTION] → test_io_links.sh
#   # [ACTION] → test_diag_read.sh
#
# !SEE ALSO:
#   run_baseline_tests, create_env, test_phase
#EOP
run_env_tests() {
  #BOC
  local dir="configs/templates/${ENV_NAME}/tests"
  if [[ -d "$dir" ]]; then
    local -a tests=()
    mapfile -t tests < <(find "$dir" -maxdepth 1 -type f -name "test_*.sh" -perm -u+x | sort)
    if [[ ${#tests[@]} -eq 0 ]]; then
      _log_warn "No env tests found in %s" "${dir}"
      return 0
    fi
    _log_info "Running %d env tests in %s" "${#tests[@]}" "${dir}"
    for t in "${tests[@]}"; do
      _log_action "→ %s" "$(basename "$t")"
      _run_with_timeout "$t" || die "Env test failed: %s" "$(basename "$t")"
    done
  else
    _log_warn "Env test directory '%s' not found; skipping env tests." "${dir}"
  fi
  #EOC
}

#BOP
# !ROUTINE: install_stack
#
# !INTERFACE:
#   install_stack
#
# !FUNCTION:
#   Executes Phase 1 of the installation workflow — installs or refreshes the
#   Spack-Stack under ${ROOT_PREFIX}, including site detection, configuration setup,
#   and compiler bootstrapping.
#
# !DESCRIPTION:
#   This routine orchestrates the entire first phase of the installation process,
#   responsible for preparing the shared Spack-Stack installation for a given site.
#
#   The function performs the following sequence:
#
#   1. **Site Detection**
#      - Calls `detect_site` to determine the current HPC site automatically
#        (e.g. `egeon`, `xc50`, `generic`).
#
#   2. **Configuration Setup**
#      - Runs `setup_site_config` to locate or assign site-specific configuration
#        directories (`config.yaml`, `packages.yaml`, `modules.yaml`, etc.) and
#        environment templates (`spack.yaml`).
#
#   3. **Spack Bootstrap**
#      - Calls `bootstrap_spack`, which clones or updates the Spack-Stack repository,
#        renders configuration templates, establishes site-scoped caches, and triggers
#        compiler installation and registration (via `bootstrap_compiler`).
#
#   4. **Finalization**
#      - Logs a success message confirming that the Spack-Stack is ready under
#        ${ROOT_PREFIX}.
#
#   This phase must complete successfully before creating or installing specific
#   environments (Phase 2) or running validation tests (Phase 3).
#
# !INPUTS:
#   - ROOT_PREFIX, SITE_NAME (auto-detected or provided)
#
# !OUTPUTS:
#   - Populates ${ROOT_PREFIX}/spack-stack with a fully bootstrapped stack.
#   - Logs completion message.
#
# !EXAMPLE:
#   install_stack
#   # Output:
#   # [INFO] Auto-detected site: egeon
#   # [OK]   [STACK] Spack-Stack ready under /mnt/beegfs/das.group/spack-stack
#
# !SEE ALSO:
#   bootstrap_spack, create_env, detect_site
#EOP
install_stack() {
  #BOC
  detect_site
  setup_site_config
  bootstrap_spack
  _log_ok "[STACK] Spack-Stack ready under %s" "${ROOT_PREFIX}"
  #EOC
}
#BOP
# !ROUTINE: install_env
#
# !INTERFACE:
#   install_env
#
# !FUNCTION:
#   Executes Phase 2 of the installation workflow — creates and installs the
#   requested Spack environment using the site configuration and templates.
#
# !DESCRIPTION:
#   This routine is a simple wrapper for `create_env`, representing the second
#   major phase in the Spack-Stack automation workflow.
#
#   While `install_stack` prepares the base stack (Phase 1), this phase:
#     - Initializes or refreshes the environment directory under
#       `${ROOT_PREFIX}/envs/${ENV_NAME}`.
#     - Seeds it with a `spack.yaml` (template) if available.
#     - Concretizes dependencies and installs all packages.
#
#   The function exists as a logical boundary between the stack-level and
#   environment-level operations, improving readability and modular execution.
#
# !INPUTS:
#   - ROOT_PREFIX, ENV_NAME, ENV_YAML
#
# !OUTPUTS:
#   - Fully built environment under ${ROOT_PREFIX}/envs/${ENV_NAME}
#
# !EXAMPLE:
#   install_env
#   # Output:
#   # [OK] Environment mpas-bundle installed successfully.
#
# !SEE ALSO:
#   install_stack, create_env, run_env_tests
#EOP
install_env() {
  #BOC
  create_env
  #EOC
}

#BOP
# !ROUTINE: test_phase
#
# !INTERFACE:
#   test_phase
#
# !FUNCTION:
#   Executes Phase 3 of the installation workflow — runs validation tests
#   (baseline and/or environment-specific) to ensure the correctness of the
#   Spack-Stack installation and environment setup.
#
# !DESCRIPTION:
#   This routine orchestrates the testing phase of the Spack-Stack workflow.
#   It is optional but strongly recommended after each build, serving as a
#   verification layer to confirm that the software stack and its environments
#   function correctly.
#
#   The sequence executed is as follows:
#
#   1. **Spack Environment Setup**
#      - Verifies that the Spack environment has been initialized by checking
#        for `${spack_dir}/setup.sh`.
#      - Sources the setup file to make Spack commands available.
#
#   2. **Baseline Tests**
#      - If `WITH_BASELINE_TESTS=1`, runs `run_baseline_tests`, which validates
#        core libraries (NetCDF, HDF5, MPI, etc.).
#      - Otherwise, logs that baseline tests are disabled.
#
#   3. **Environment Tests**
#      - If `WITH_ENV_TESTS=1`, the routine:
#          - Activates the environment (`spack env activate -d`).
#          - Executes `run_env_tests` to validate environment-specific
#            components and workflows.
#      - If the environment directory does not exist, logs a warning.
#      - If disabled, logs that environment tests are skipped.
#
#   This modular testing structure ensures that core functionality and
#   environment integration are independently verifiable, improving
#   reproducibility and diagnostics.
#
# !INPUTS:
#   - ROOT_PREFIX, ENV_NAME, WITH_BASELINE_TESTS, WITH_ENV_TESTS
#
# !OUTPUTS:
#   - Runs selected test suites and logs their results.
#
# !EXAMPLE:
#   test_phase
#   # Output:
#   # [INFO] Running baseline test: test_hdf5.sh
#   # [INFO] Running 2 env tests in configs/templates/mpas-bundle/tests
#   # [OK]   All tests completed successfully.
#
# !SEE ALSO:
#   run_baseline_tests, run_env_tests, install_env
#EOP
test_phase() {
  #BOC
  local spack_dir="${ROOT_PREFIX}/spack-stack"
  [[ -f "${spack_dir}/setup.sh" ]] || die "spack not initialized (missing setup.sh)."
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
  #EOC
}

#BOP
# !ROUTINE: main
#
# !INTERFACE:
#   main "$@"
#
# !FUNCTION:
#   Entry point of the installation workflow — orchestrates the full Spack-Stack
#   deployment pipeline (stack installation, environment setup, and testing).
#
# !DESCRIPTION:
#   This is the central coordination routine of the installer. It processes
#   arguments, prepares directories, initializes logging, and executes the
#   selected phases according to user-specified flags.
#
#   The workflow proceeds as follows:
#
#   1. **Argument Parsing**
#      - Calls `_parse_script_args "$@"` to process both generic and
#        script-specific command-line options.
#
#   2. **Environment Preparation**
#      - Runs `ensure_dirs` to create necessary directories for logs and
#        the Spack installation root.
#
#   3. **Execution Logging**
#      - Logs contextual information (script name, hostname, and root paths).
#      - Reports current parameters: ROOT_PREFIX, SPACK_STACK_VERSION,
#        ENV_NAME, and JOBS.
#
#   4. **Phase Execution**
#      - Conditionally executes each phase according to control flags:
#        - Phase 1 → `install_stack` (bootstrap Spack-Stack and compiler)
#        - Phase 2 → `install_env` (create and install Spack environment)
#        - Phase 3 → `test_phase` (run baseline and environment tests)
#
#   5. **Completion**
#      - Logs a final success message confirming that all enabled phases have
#        completed successfully.
#
#   The modular design allows selective execution of specific phases via
#   command-line flags (`--only-stack`, `--only-env`, `--only-tests`).
#
# !INPUTS:
#   - Command-line arguments passed to `_parse_script_args`
#   - Environment variables controlling behavior (ROOT_PREFIX, DO_STACK, etc.)
#
# !OUTPUTS:
#   - Executes the requested phases, logging each stage.
#
# !EXAMPLE:
#   main "$@"
#   # Output:
#   # [BEGIN] install_and_test_spack_stack.sh on egeon
#   # [OK] [STACK] Spack-Stack ready under /mnt/beegfs/das.group/spack-stack
#   # [OK] Environment mpas-bundle installed successfully.
#   # [DONE] Completed.
#
# !SEE ALSO:
#   _parse_script_args, install_stack, install_env, test_phase
#EOP
main() {
  #BOC
  _parse_script_args "$@"
  ensure_dirs
  _log_info "[BEGIN] %s on %s" "${_script}" "${_host}"
  _log_info "Root: %s | Spack-Stack: %s | Env: %s | Jobs: %s" "${ROOT_PREFIX}" "${SPACK_STACK_VERSION}" "${ENV_NAME}" "${JOBS}"

  if [[ $DO_STACK -eq 1 ]]; then install_stack; fi
  if [[ $DO_ENV   -eq 1 ]]; then install_env; fi
  if [[ $DO_TESTS -eq 1 ]]; then test_phase; fi

  _log_ok "[DONE] Completed."
  #EOC
}
#BOP
# !ROUTINE: module_init_and_entrypoint
#
# !INTERFACE:
#   [[ -r /etc/profile.d/lmod.sh ]] && source /etc/profile.d/lmod.sh || true
#   main "$@"
#
# !FUNCTION:
#   Performs optional module initialization (for environments that use Lmod)
#   and then invokes the main entrypoint of the Spack-Stack installation workflow.
#
# !DESCRIPTION:
#   Some HPC systems (e.g., Egeon, XC50) manage software environments through
#   **Lmod**, a dynamic module system. This block safely initializes Lmod if
#   its shell initialization script exists and is readable.
#
#   The logic is:
#     1. Check for `/etc/profile.d/lmod.sh`.
#     2. Source it to enable the `module` command and preloaded compiler/MPI modules.
#     3. Continue execution silently if Lmod is unavailable (avoids breaking generic hosts).
#
#   After that, the script calls:
#     `main "$@"`
#   — which handles argument parsing, directory setup, and orchestrates all installation
#   and testing phases according to user-defined flags.
#
# !EXAMPLE:
#   # Typical invocation (with optional Lmod support):
#   ./install_and_test_spack_stack.sh -- --only-env --env-name mpas-bundle
#
#   # On systems without Lmod, the initialization line is skipped automatically:
#   [WARN] Lmod not found; proceeding without module support.
#
# !SEE ALSO:
#   main, install_stack, install_env, test_phase
#EOP

#BOC
# Initialize modules (optional)
[[ -r /etc/profile.d/lmod.sh ]] && source /etc/profile.d/lmod.sh || true

# Execute main routine
main "$@"
#EOC

