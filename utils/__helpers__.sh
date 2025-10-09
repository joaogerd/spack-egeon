#!/usr/bin/env bash
#===============================================================================
# Script: __helpers__.sh
#
# Purpose:
#   Common helper utilities (logging, argument parsing, progress reporting,
#   simple copying/linking with progress, environment assignment/expansion,
#   system detection, and cluster environment export). Designed to be *sourced*
#   by other Bash scripts.
#
# Usage:
#   # Recommended: source this file at the top of your script
#   source "/path/to/__helpers__.sh"
#
#   # Example pattern inside caller scripts:
#   my_command() {
#     _parse_args "$@"
#     $verbose && _log_info "Running my_command with args: %s" "${leftover_args[*]}"
#     # ...
#   }
#
# Notes:
#   - This library is intended to be sourced (not executed). The shebang is
#     present for consistency only; no code runs on direct execution.
#   - Global flag `verbose` defaults to `false`. Set `verbose=true` in the
#     caller to enable logging, or pass `-v/--verbose` to functions that call
#     `_parse_args`.
#   - Functions prefixed with `_` are internal helpers; they can be used by
#     callers, but their interface may evolve conservatively.
#   - Requires Bash 4+ (for namerefs with `local -n`).
#
# Environment:
#   verbose      : boolean string "true"/"false" (default: false)
#   auto_yes     : when true, skip confirmation prompts (default: false)
#   dry_run      : when true, only log actions (default: false)
#   do_restore   : when true, enable restore behavior if supported (default: false)
#   do_fix       : when true, allow creating dirs/symlinks/copies if needed (default: false)
#
# License:
#   LGPL-3.0-or-later (adjust as needed for your project)
#===============================================================================


#-----------------------------------------------------------------------------#
#----------------------- internal helpers (hidden from help) -----------------#
#-----------------------------------------------------------------------------#
#BOP
# !SECTION: LOG CORE (centralized logging configuration)
#
# !DESCRIPTION:
#   Defines global, centralized logging configuration knobs used by the helpers.
#   These variables control tagging, timestamps, color behavior, and output
#   file descriptors, while keeping backward compatibility with the existing
#   `verbose`, `debug`, and `dry_run` booleans already used across scripts.
#
# !CONTENT:
#   - LOG_TAG           : Optional static tag prefixed to every log line.
#                         Example: "SPACK". Empty by default (no extra tag).
#   - LOG_TIMESTAMPS    : When "1", prepend a timestamp to log lines.
#                         Default "0" (no timestamp).
#   - LOG_TIME_FMT      : Format string for `date(1)` when timestamps are enabled.
#                         Default "%Y-%m-%d %H:%M:%S".
#   - LOG_FD_OUT        : File descriptor used for informational levels
#                         (INFO/OK/ACTION/DEBUG). Default "1" (stdout).
#   - LOG_FD_ERR        : File descriptor used for warning/error levels
#                         (WARN/ERROR/FAIL). Default "2" (stderr).
#   - COLOR             : If "1" and stdout is a TTY, enable ANSI colors.
#                         Set FORCE_COLOR=1 to force colors regardless of TTY.
#
#   Backward-compatibility flags:
#   - verbose           : "true"/"false". When true, INFO/OK/ACTION are printed.
#                         WARN/ERROR/FAIL always print regardless of `verbose`.
#   - debug             : "true"/"false". When true, DEBUG messages print and
#                         optional xtrace helpers may be enabled by the caller.
#   - dry_run           : "true"/"false". When true, execution helpers only log
#                         the intended command (no side effects) and return 0.
#
# !USAGE:
#   # Minimal example (enable timestamps and tag in a calling script):
#   export LOG_TAG="SPACK"
#   export LOG_TIMESTAMPS=1
#   export verbose=true
#   export debug=false
#
#   # To force colors even when redirected:
#   export FORCE_COLOR=1
#
#   # To route INFO to a file and keep ERR on stderr:
#   exec 3>>/var/log/mytool-info.log
#   export LOG_FD_OUT=3   # INFO/OK/ACTION/DEBUG → FD 3 (file)
#   export LOG_FD_ERR=2   # WARN/ERROR/FAIL      → FD 2 (stderr)
#
# !NOTES:
#   • These variables are read by the logging helpers during initialization.
#   • Changing them at runtime affects subsequent log lines immediately.
#   • `verbose`, `debug`, and `dry_run` are exported here for consistency across
#     sourced scripts. Call-site argument parsers may override them later.
#
# !LICENSE:
#   LGPL-3.0-or-later
#EOP

LOG_TAG="${LOG_TAG:-}"
LOG_TIMESTAMPS="${LOG_TIMESTAMPS:-0}"
LOG_TIME_FMT="${LOG_TIME_FMT:-%Y-%m-%d %H:%M:%S}"
LOG_FD_OUT="${LOG_FD_OUT:-1}"
LOG_FD_ERR="${LOG_FD_ERR:-2}"

#BOP
# !SECTION: Compatibility Flags
#
# !DESCRIPTION:
#   Preserve and export the commonly used global flags (`verbose`, `debug`,
#   `dry_run`) so they are available across all sourced scripts. These flags
#   control the logging verbosity, debug output, and dry-run behavior.
#
# !CONTENT:
#   - verbose : "true"/"false". When true, INFO/OK/ACTION messages are printed.
#               Default: false.
#   - debug   : "true"/"false". When true, DEBUG messages are printed and
#               optional xtrace helpers may be enabled. Default: false.
#   - dry_run : "true"/"false". When true, execution helpers (_run, copy
#               helpers, etc.) only log the intended actions instead of
#               executing them. Default: false.
#
# !USAGE:
#   # Enable verbose logs in a caller script:
#   export verbose=true
#
#   # Enable debug logs and traces:
#   export debug=true
#
#   # Run in dry-run mode (no side effects, only logs):
#   export dry_run=true
#
# !NOTES:
#   • Defaults are assigned only if variables are unset.
#   • The values are exported so that any sourced script sees a consistent state.
#   • Typically overridden by argument parsing (e.g. `__parse_args__`).
#EOP

export verbose=${verbose:-false}
export debug=${debug:-false}
export dry_run=${dry_run:-false}
export auto_yes=${auto_yes:-false}

#BOP
# !FUNCTION: _log_colors_init
# !DESCRIPTION:
#   Initialize ANSI color tags when stdout is an interactive TTY and COLOR=1.
#   When not a TTY or COLOR != 1, colors are disabled (empty strings).
#   This keeps logs clean when redirected to files or piped.
#
# !NOTES:
#   • Uses stdout (fd 1) as reference for color enablement.
#   • Honors env var COLOR (default: 1). Set COLOR=0 to force no color.
#EOP
#BOC
_log_colors_init() {
  local _COLOR="${COLOR:-1}"
  [[ "${FORCE_COLOR:-0}" == 1 ]] && _COLOR=1
  if [[ -t 1 && "${_COLOR}" = "1" ]]; then
    C_INFO=$'\033[1;34m'   # bold blue
    C_DBG=$'\033[1;35m'    # bold magenta
    C_OK=$'\033[1;32m'     # bold green
    C_WARN=$'\033[1;33m'   # bold yellow
    C_ERR=$'\033[1;31m'    # bold red
    C_ACT=$'\033[1;36m'    # bold cyan
    C_RST=$'\033[0m'
  else
    C_INFO=; C_DBG=; C_OK=; C_WARN=; C_ERR=; C_ACT=; C_RST=
  fi
}
# Initialize at load time (no-op if not TTY)
_log_colors_init
#EOC

#BOP
# !FUNCTION: __log_ts
#
# !DESCRIPTION:
#   Return a timestamp string when `LOG_TIMESTAMPS` is enabled. The format
#   is controlled by `LOG_TIME_FMT`. If `LOG_TIMESTAMPS` is not set to "1",
#   the function returns immediately without printing anything.
#
# !USAGE:
#   ts="$(__log_ts)"   # → "2025-09-27 18:23:45" (if enabled)
#   echo "[$ts] Starting process..."
#
# !ENVIRONMENT:
#   - LOG_TIMESTAMPS : "1" to enable, "0" (default) to disable.
#   - LOG_TIME_FMT   : Format string for date(1). Default "%Y-%m-%d %H:%M:%S".
#
# !RETURNS:
#   Prints the formatted timestamp to stdout when enabled.
#   Returns 0 in all cases.
#
# !NOTES:
#   • Uses the system `date` command, so the format specifiers follow `date(1)`.
#   • Safe to call inline inside log functions.
#   • When disabled, it produces no output, allowing simple concatenation in
#     log lines without extra conditionals.
#EOP
#BOC
__log_ts() {
  [[ "$LOG_TIMESTAMPS" == 1 ]] || return 0
  command date +"$LOG_TIME_FMT"
}
#EOC

#BOP
# !FUNCTION: _log_msg
# !DESCRIPTION:
#   Print a standardized log message with a given level (INFO, OK, WARNING,
#   ACTION, ERROR, FAIL, etc.). Messages are printed only when the global
#   variable `verbose` is set to `true`, unless forced with `-f`.
#   Supports printf-style formatting. Safe with 'set -u'.
#
# !INTERFACE:
#   _log_msg <LEVEL> [-f] <format> [args...]
#
# !EXAMPLES:
#   _log_msg INFO "Starting step %s" "$step"
#   _log_msg WARNING -f "Low disk space: %s" "$mountpoint"
#   _log_msg OK "Built %d target(s) in %0.2f s" "$n" "$elapsed"
#
# !NOTES:
#   • Do not add a trailing newline to <format>; it’s appended automatically.
#   • `verbose` is the Bash boolean string `true` or `false` (default: false).
#   • Output goes to stdout by default; to route to stderr temporarily, wrap:
#       { _log_msg ERR "msg"; } 1>&2
#   • When SUPPRESS_LOGS=true (e.g., help requested as first arg), nothing is printed.
#EOP
#BOC
_log_msg() {

  # Silence everything (including -f) when help was requested
  [[ "${SUPPRESS_LOGS:-false}" == true ]] && return 0

  local level="$1"; shift
  local force=false
  if [[ "${1:-}" == "-f" ]]; then force=true; shift; fi

  # default: verbose=false
  local v="${verbose:-false}"
  # default: debug=false
  local d="${debug:-false}"

  # Gate by log level
  case "${level^^}" in
    DEBUG)   $force || $d || return 0 ;;      # show only if forced or debug=true
    INFO|OK|ACTION)
             $force || $v || return 0 ;;      # show only if forced or verbose=true
    WARNING|WARN|ERROR|ERR|FAIL)
             ;;                               # always show
    *)       $force || $v || return 0 ;;      # unknown levels behave like INFO
  esac

  # map level → color tag + normalized label + File descriptor used (default stdout/stderr)
  local tag color fd ts ptag
  case "${level^^}" in
    DEBUG)    tag="[DEBUG]";   color="$C_DBG"; fd="$LOG_FD_OUT" ;;
    INFO)     tag="[INFO]";    color="$C_INFO"; fd="$LOG_FD_OUT" ;;
    OK)       tag="[OK]";      color="$C_OK";  fd="$LOG_FD_OUT" ;;
    ACTION)   tag="[ACTION]";  color="$C_ACT"; fd="$LOG_FD_OUT" ;;
    WARNING|WARN)
              tag="[WARNING]"; color="$C_WARN"; fd="$LOG_FD_ERR" ;;
    ERROR|ERR)
              tag="[ERROR]";   color="$C_ERR";  fd="$LOG_FD_ERR" ;;
    FAIL)     tag="[FAIL]";    color="$C_ERR";  fd="$LOG_FD_ERR" ;;
    *)        tag="[$level]";  color="";        fd="$LOG_FD_OUT" ;;
  esac

  ts="$(__log_ts)"                   # optional timestamp (empty if disabled)
  ptag="${tag}"                      # base tag (e.g., [INFO], [ERROR])
  [[ -n "$LOG_TAG" ]] && ptag="[$LOG_TAG] ${ptag}"   # prepend global tag if set

  # $1 is the format string; the rest are printf args
  local fmt; fmt="${1:-}"; shift || true

  if [[ -z "$fmt" ]]; then
    printf "%s%s%s\n" "${color}" "${tag}" "${C_RST}"
  else
    # colorize only the tag; message remains plain (better for grepping)
    # use -- to stop printf from interpretarando algo como opção
    printf "%s%s%s %s\n" "${color}" "${tag}" "${C_RST}" "$(printf -- "$fmt" "$@")"
  fi

}
#EOC

#BOP
# !FUNCTION: _log_debug, _log_info, _log_ok, _log_err, _log_warn, _log_action, _log_fail, _die
# !DESCRIPTION:
#   Convenience wrappers around `_log_msg` that set the appropriate level.
#   `_log_err` and `_log_fail` always force output (they behave as if `-f` was passed).
#   Other wrappers accept an optional `-f` to force output.
#
# !INTERFACE:
#   _log_debug   [-f] <format> [args...]
#   _log_info    [-f] <format> [args...]
#   _log_ok      [-f] <format> [args...]
#   _log_warn    [-f] <format> [args...]
#   _log_action  [-f] <format> [args...]
#   _log_err          <format> [args...]   # forced output
#   _log_fail         <format> [args...]   # forced output
#   _die       [code] <format> [args...]
#
# !EXAMPLES:
#   _log_info "Preparing NCEP input copy (layout=%s): %s" "$layout" "$cycle"
#   _log_ok   "Artifacts available at %s" "$outdir"
#   _log_warning -f "Retrying download (%d/%d)..." "$i" "$max"
#   _log_err  "Failed to load cluster paths via vars_export"
#
# !NOTES:
#   • Formatting follows `printf` semantics (placeholders are expanded).
#   • Wrappers append a newline automatically; do not include one in <format>.
#EOP
#BOC

# Wrappers (keep behavior consistent)
_log_debug()   { _log_msg "DEBUG"   "$@"; }
_log_info()    { _log_msg "INFO"    "$@"; }
_log_ok()      { _log_msg "OK"      "$@"; }
_log_warn()    { _log_msg "WARNING" "$@"; }
_log_action()  { _log_msg "ACTION"  "$@"; }

# Errors should always print, regardless of verbose
_log_fail()    { _log_msg "FAIL"  -f "$@"; }
_log_err()     { _log_msg "ERROR" -f "$@"; }
_die()         { local code="${1:-1}"; shift || true; _log_err "$@"; exit "$code"; }
#EOC

#BOP
# !EXIT CODES & WRAPPERS
# !DESCRIPTION:
#   Standardized exit codes and convenience wrappers for all scripts. They
#   ensure consistent error handling and logging across the project.
#
# !CODES:
#   EX_OK=0         Success — execution completed without errors.
#   EX_USAGE=1      Usage error — invalid command-line arguments or invocation.
#   EX_NOOP=2       No operation — script executed correctly but nothing to do
#                   (e.g., no files staged, empty input).
#   EX_CONFIG=3     Configuration error — required option, environment variable,
#                   or configuration file is missing/invalid.
#   EX_NOINPUT=4    Input missing — required source file or directory not found
#                   or unreadable.
#   EX_CANTCREAT=5  Output error — unable to create/write to destination (e.g.,
#                   permission denied, disk full).
#   EX_FAIL=6       Generic failure — execution error not covered by other codes.
#
# !WRAPPERS:
#   _exit_ok        <format> [args...]     # success, logs OK, exits EX_OK
#   _exit_usage     <format> [args...]     # logs ERROR, exits EX_USAGE
#   _exit_noop      <format> [args...]     # logs INFO, exits EX_NOOP
#   _exit_config    <format> [args...]     # logs ERROR, exits EX_CONFIG
#   _exit_noinput   <format> [args...]     # logs ERROR, exits EX_NOINPUT
#   _exit_cantcreat <format> [args...]     # logs ERROR, exits EX_CANTCREAT
#   _exit_fail      <format> [args...]     # logs ERROR, exits EX_FAIL
#
# !EXAMPLES:
#   [[ $# -eq 0 ]] && _exit_usage "Missing arguments"
#   [[ ! -f "$file" ]] && _exit_noinput "Input file not found: %s" "$file"
#   mkdir -p "$outdir" || _exit_cantcreat "Cannot create output dir: %s" "$outdir"
#
# !NOTES:
#   • Always use symbolic names (EX_*) instead of raw numbers.
#   • Wrappers combine logging + exit in a consistent way.
#   • `_die` remains available for custom codes outside this set.
#EOP
#BOC
readonly EX_OK=0
readonly EX_USAGE=1
readonly EX_NOOP=2
readonly EX_CONFIG=3
readonly EX_NOINPUT=4
readonly EX_CANTCREAT=5
readonly EX_FAIL=6

_exit_ok()        { _log_ok    "$@"; exit "$EX_OK"; }
_exit_usage()     { _die "$EX_USAGE"    "$@"; }
_exit_noop()      { _log_info  "$@"; exit "$EX_NOOP"; }
_exit_config()    { _die "$EX_CONFIG"   "$@"; }
_exit_noinput()   { _die "$EX_NOINPUT"  "$@"; }
_exit_cantcreat() { _die "$EX_CANTCREAT" "$@"; }
_exit_fail()      { _die "$EX_FAIL"     "$@"; }

#EOC

#BOP
# !FUNCTION: _debug_trace_on
#
# !DESCRIPTION:
#   Enable Bash execution tracing (xtrace) when `debug=true`. The trace prefix
#   (PS4) is customized to include timestamp, process ID, function name,
#   source file, and line number, providing detailed context for debugging.
#
# !USAGE:
#   export debug=true
#   _debug_trace_on
#   my_function arg1 arg2
#
# !BEHAVIOR:
#   • Only activates when global variable `debug` is "true".
#   • Sets PS4 so each traced command line has the format:
#       + [<EPOCHREALTIME>] (<PID>) <FUNC>@<SOURCE>:<LINENO>: <command...>
#   • Calls `set -x` to enable tracing.
#
# !EXAMPLE OUTPUT:
#   + [1695842356.123456] (12345) main@script.sh:42: cp input.txt output.txt
#
# !ENVIRONMENT:
#   - debug : "true"/"false". Controls whether trace mode is enabled.
#   - PS4   : Modified locally to format xtrace lines.
#
# !SEE ALSO:
#   _debug_trace_off (to disable tracing after use)
#
#EOP
#BOC
_debug_trace_on() {
  [[ "${debug:-false}" == true ]] || return 0
  # PS4 with timestamp + PID + function + source + line number
  export PS4='+ [${EPOCHREALTIME}] ($$) ${FUNCNAME[0]:-main}@${BASH_SOURCE}:${LINENO}: '
  set -x
}
#EOC

#BOP
# !FUNCTION: _debug_trace_off
#
# !DESCRIPTION:
#   Disable Bash execution tracing (xtrace) when `debug=true`. This is the
#   counterpart of `_debug_trace_on` and should be called after the section
#   you want to trace to restore normal output.
#
# !USAGE:
#   _debug_trace_on
#   # ... commands to trace ...
#   _debug_trace_off
#
# !BEHAVIOR:
#   • Only acts when the global `debug` flag is "true".
#   • Calls `set +x` to turn off tracing.
#
# !ENVIRONMENT:
#   - debug : "true"/"false". Controls whether the function performs any action.
#
# !SEE ALSO:
#   _debug_trace_on
#EOP
#BOC
_debug_trace_off() {
  [[ "${debug:-false}" == true ]] || return 0
  set +x
}
#EOC

#BOP
# !ROUTINE: _safe_source
#
# !INTERFACE:
#   _safe_source <file>
#
# !FUNCTION:
#   Sources a shell script safely under a global `set -u` (nounset) regime by
#   temporarily disabling nounset for the duration of the sourcing operation.
#
# !DESCRIPTION:
#   Many third-party initialization scripts (e.g., /etc/profile.d/lmod.sh, SLURM
#   env hooks) reference environment variables that may be undefined when the
#   installer runs with `set -u`. Directly sourcing such files can trigger
#   “unbound variable” errors and abort execution.
#
#   This helper:
#     1) Verifies the target file is readable; returns success if it is absent.
#     2) Temporarily disables nounset (`set +u`) in a controlled scope.
#     3) Sources the target file (no shellcheck path validation).
#     4) Restores nounset (`set -u`) and propagates the sourced script’s status.
#
#   Use this wrapper whenever you need to source external, non-owned scripts
#   whose contents you cannot control, preserving the safety of `set -Eeuo pipefail`
#   in the rest of the installer.
#
# !INPUTS:
#   - $1: Path to the script to be sourced.
#
# !OUTPUTS:
#   - Returns 0 if the file is absent/unreadable (no-op) or if sourcing succeeds.
#   - Returns the exit status from the sourced script otherwise.
#
# !EXAMPLE:
#   _safe_source /etc/profile.d/lmod.sh || true
#
# !SEE ALSO:
#   install_and_test_spack_stack.sh main epilogue (module init), doctor target in Makefile
#EOP
_safe_source() {
  #BOC
  # usage: _safe_source /path/to/file.sh
  local f="$1"
  [[ -r "$f" ]] || return 0
  # Temporarily disable nounset while sourcing third-party scripts.
  set +u
  # shellcheck source=/dev/null
  source "$f"
  local rc=$?
  set -u
  return "$rc"
  #EOC
}

#BOP
# !FUNCTION: _dump_cli
# !DESCRIPTION:
#   Print the *effective* CLI arguments received by the entry point or function.
#   Useful for debugging when options are re-parsed or altered.
# !USAGE:
#   _dump_cli "$@"
#EOP
#BOC
_dump_cli() {
  # Always show the argv in debug mode (INFO would be hidden if verbose=false).
  _log_debug 'CLI ARGV:' >&2
  local arg
  for arg in "$@"; do
    _log_debug '  %q' "$arg" >&2
  done
  printf '\n' >&2
}
#EOC

#BOP
# !FUNCTION: _with_strict_mode
#
# !DESCRIPTION:
#   Temporarily enable Bash "strict mode" within the current function scope:
#     - `set -e`       : exit on any error
#     - `set -u`       : error on unset variables
#     - `set -o pipefail` : pipeline fails if any command fails
#   The original shell options are snapshotted and automatically restored
#   on function RETURN, ensuring no side effects leak to the caller.
#
# !USAGE:
#   my_func() {
#     _with_strict_mode
#     # ... safe code here ...
#   }
#
# !BEHAVIOR:
#   • Captures the current shell option state via `set +o`.
#   • Enables strict mode.
#   • Installs a RETURN trap that restores the previous options upon exit.
#   • Emits a DEBUG-level log line if debug logging is enabled.
#
# !EXAMPLE:
#   safe_copy() {
#     _with_strict_mode
#     cp -- "$1" "$2"
#   }
#
#   # In this example, any error in cp (missing file, permission issue, etc.)
#   # will stop execution, but once safe_copy returns the original shell
#   # options are restored.
#
# !NOTES:
#   • This pattern allows strict behavior in critical sections without forcing
#     the entire script to run in strict mode.
#   • Safe to reuse in multiple functions; each invocation is scoped.
#
# !DEPENDENCIES:
#   - `_log_debug` for the diagnostic message (optional; silently no-ops if
#     DEBUG logs are disabled).
#
#EOP
#BOC
_with_strict_mode() {
  # Snapshot current options as shell code (e.g., 'set +o errexit; set +o nounset; ...')
  local __o; __o="$(set +o)"

  # Enable strict mode
  set -euo pipefail

  # Restore snapshot when this function returns (expand __o now, not later)
  trap -- "$(printf 'eval %q; trap - RETURN' "$__o")" RETURN
  _log_debug "Strict mode enabled within function scope"
}
#EOC

#BOP
# !FUNCTION: __need_val
# !INTERFACE: __need_val <opt> <val>
# !DESCRIPTION:
#   Guard helper to enforce that an option which requires an argument actually
#   receives one. It fails when the value is missing or when the next token
#   "looks like" another option (i.e., starts with a dash '-').
#
# !USAGE:
#   # Inside an option parser:
#   while [[ $# -gt 0 ]]; do
#     case "$1" in
#       -A|--analysis)
#         __need_val "$1" "$2" || exit $?
#         analysis="$2"; shift 2;;
#       -n|--ntasks)
#         __need_val "$1" "$2" || exit $?
#         ntasks="$2"; shift 2;;
#       --) shift; break;;
#       *)  break;;
#     esac
#   done
#
# !RETURNS:
#   0  if a non-empty value is provided and does not start with '-'
#   EX_USAGE (default 1) otherwise
#
# !EXIT CODES:
#   EX_USAGE  Usage error; missing or invalid value for the given option.
#
# !EXAMPLES:
#   __need_val "--levels" "$2" || exit $?
#   # If $2 is empty or "-x", logs an error and returns EX_USAGE.
#
# !DEPENDENCIES:
#   - _log_err: logging helper supporting printf-style formatting.
#   - EX_USAGE: optional environment variable with the numeric code for usage errors.
#
# !NOTES:
#   - This helper only validates presence and a simple shape check (leading '-').
#     If you need type/regex validation (e.g., integers), perform it after this call.
#   - Bash-specific conditionals ([[ ... ]]) are used intentionally.
#EOP
#BOC
__need_val() {  # usage: __need_val "$1" "$2" || return 1
  local opt="$1"
  local val="${2:-}"
  # Fail if value is empty or looks like a new option (starts with '-')
  if [[ -z "$val" || "$val" == -* ]]; then
    _log_err "Option %s requires a value" "$opt"
    return "${EX_USAGE:-1}"
  fi
  return 0
}
#EOC

###############################################################################
#BOP
#
# !FUNCTION: __parse_args__
#
# !INTERFACE:
#   __parse_args__ "$@"
#
# !DESCRIPTION:
#   Parse common CLI options for build/run scripts, including verbosity,
#   safety utilities (yes/restore/fix/dry-run), scheduler queue/job metadata,
#   and HPC resource layout (MPI/OpenMP). Unknown/legacy short flags are
#   rejected with a helpful error.
#
#   Verbosity & utilities:
#     -v, --verbose          → verbose=true     (enable logging)
#     -q, --quiet            → verbose=false    (disable logging)
#     -d, --debug            → debug=true       (enable debug logging)
#     -y, --yes              → auto_yes=true    (auto-confirm prompts)
#     -f, --fix              → do_fix=true      (create dirs/symlinks/copies as needed)
#         --dry-run          → dry_run=true     (skip actual actions)
#         --restore          → do_restore=true  (restore from *.bak when supported)
#
#   Scheduler / queueing:
#     -Q, --queue <name>     → queue="name"     (set queue/partition)
#         --queue=name       → same as above
#         --job-name <name>  → job_name="name"  (scheduler job name)
#         --walltime <HH:MM:SS> → walltime="..." (requested wall clock)
#
#   HPC resources (long-only):
#         --ntasks <N>           → mpi_tasks=N
#         --cpus-per-task <N>    → omp_threads=N
#         --nodes <N>            → nodes=N
#         --cores-per-node <N>   → cores_per_node=N
#         --procs <N>            → total_procs=N
#
#   Behavior:
#     1) Flags are evaluated in order — the *last one wins*.
#     2) If only --procs and --cpus-per-task are given, mpi_tasks is derived as:
#          mpi_tasks = ceil(total_procs / omp_threads)
#     3) Remaining positional arguments are preserved in leftover_args[].
#
#   Legacy flags (explicitly removed; cause an error if used):
#     -D, -dryrun      (use --dry-run)
#     -pq              (use -Q|--queue <name>)
#     -pn              (use --job-name <name>)
#     -pw              (use --walltime <HH:MM:SS>)
#     -np, -d, -N, -c, -P  (use the long forms: --ntasks/--cpus-per-task/--nodes/
#                           --cores-per-node/--procs)
#
# !USAGE:
#   __parse_args__ "$@"
#   # After parsing, use exported variables:
#   $verbose    && _log_info "Queue: %s" "$queue"
#   $debug      && _log_dbg  "MPI=%s OMP=%s Nodes=%s" "$mpi_tasks" "$omp_threads" "$nodes"
#   if $dry_run; then _log_info "DRY-RUN: args → %s" "${leftover_args[*]}"; fi
#
# !RETURNS:
#   0 on success.
#   2 if a removed/legacy flag is detected.
#
# !ENVIRONMENT:
#   Respects existing environment defaults when set before parsing:
#     verbose, debug, auto_yes, dry_run, do_restore, do_fix,
#     queue, job_name, walltime,
#     mpi_tasks, omp_threads (default 1), nodes, cores_per_node, total_procs.
#
# !EXAMPLES:
#   __parse_args__ -v --dry-run -Q PESQ1 --job-name test --walltime 00:20:00 \
#                  --ntasks 64 --cpus-per-task 2 --nodes 4 --cores-per-node 32 -- echo OK
#
#   __parse_args__ --procs 128 --cpus-per-task 4  # → derives mpi_tasks=32
#
# !NOTES:
#   - Uses a local "strict mode" wrapper (_with_strict_mode) only for this function.
#   - Declares leftover_args as a global array (declare -g -a) to avoid -u issues.
#   - Queue options are optional; default scheduler policy applies when unset.
#
#EOP
###############################################################################
#BOC

__parse_args__() {
  _with_strict_mode   # enable strict mode only for this function

  # --- respect optional write-leftovers toggle (generic) ---
  local write_leftovers="${PARSER_WRITE_LEFTOVERS:-1}"

  # ---- Safe defaults (respect existing env vars) ----
  verbose=${verbose:-false}
  debug=${debug:-false}
  auto_yes=${auto_yes:-false}
  dry_run=${dry_run:-false}
  do_restore=${do_restore:-false}
  do_fix=${do_fix:-false}

  queue=${queue:-}
  job_name=${job_name:-}
  walltime=${walltime:-}

  mpi_tasks=${mpi_tasks:-}
  omp_threads=${omp_threads:-1}
  nodes=${nodes:-}
  cores_per_node=${cores_per_node:-}
  total_procs=${total_procs:-}

  # Only (re)declare/reset leftover_args if we are allowed to write it
  if [[ "$write_leftovers" != 0 ]]; then
    declare -g -a leftover_args 2>/dev/null || true
    leftover_args=()
  fi

  # Parse only new canonical flags; reject legacy ones with a helpful error
  while [[ $# -gt 0 ]]; do
    opt="$1"
    case $opt in
      # ---- Verbosity and behavior ----
      -v|--verbose) verbose=true; shift; continue ;;
      -q|--quiet)   verbose=false; shift; continue ;;
      -d|--debug)   debug=true; shift; continue ;;
      -y|--yes)     auto_yes=true; shift; continue ;;
      -f|--fix)     do_fix=true; shift; continue ;;
      --dry-run)    dry_run=true; shift; continue ;;
      --restore)    do_restore=true; shift; continue ;;

      # ---- End of options / passthrough ----
      --)    (( write_leftovers )) && leftover_args+=("$1"); break ;;
      --?*)  (( write_leftovers )) && leftover_args+=("$1"); shift; continue ;;
      -?*)   (( write_leftovers )) && leftover_args+=("$1"); shift; continue ;;
      *)     (( write_leftovers )) && leftover_args+=("$1"); shift; continue ;;
    esac
  done

  
  # derive layout if only total_procs provided
  if [[ -n "${total_procs}" && -z "${mpi_tasks}" ]]; then
    (( omp_threads <= 0 )) && omp_threads=1
    mpi_tasks=$(( (total_procs + omp_threads - 1) / omp_threads ))
  fi

  export verbose debug auto_yes dry_run do_restore do_fix
  
  _log_debug "Parsed args: verbose=%s debug=%s dry_run=%s ..." "$verbose" "$debug" "$dry_run" 
  _log_debug 'leftovers=(%s)' "$(printf '%q ' "${leftover_args[@]}")"
}
#EOC

#BOP
# !FUNCTION: _run
#
# !DESCRIPTION:
#   Execute a given command with arguments, respecting the global `dry_run`
#   flag. In dry-run mode, the command is not executed; instead, a log line
#   is emitted to indicate what would have been run. In normal mode, the
#   command is executed directly.
#
# !USAGE:
#   dry_run=false
#   _run cp file1 file2          # executes: cp file1 file2
#
#   dry_run=true
#   _run rm -rf /tmp/data        # logs "[DRY-RUN] rm -rf /tmp/data", no action
#
# !BEHAVIOR:
#   • If `dry_run=true`, print a standardized "[DRY-RUN]" log message via
#     `_log_action`, quoting arguments safely, and return success (0).
#   • If `dry_run=false`, log a DEBUG-level message with the command line,
#     then execute the command in place.
#
# !RETURNS:
#   • In dry-run mode: always returns 0.
#   • In normal mode: returns the exit status of the executed command.
#
# !ENVIRONMENT:
#   - dry_run : "true"/"false" (default: false).
#   - _log_action : Logger function used to print simulated command execution.
#   - _log_debug  : Logger function used to print debug-level execution traces.
#
# !NOTES:
#   • Arguments are executed without eval, preserving exact quoting and avoiding
#     shell injection issues.
#   • Designed to be a safe wrapper for critical commands in scripts that need
#     dry-run simulation support.
#EOP
#BOC
# __helpers__.sh
_run() {
  # Always receive command as array
  local -a cmd=( "$@" )

  # Pretty-print for dry-run
  if [[ "${dry_run:-false}" == true ]]; then
    _log_info "DRY-RUN: %s" "${cmd[*]}"
    return 0
  fi

  # If first token is a shell function, call it directly
  if declare -F -- "${cmd[0]}" >/dev/null 2>&1; then
    "${cmd[@]}"
    return $?
  fi

  # Otherwise, execute as external command/binary
  "${cmd[@]}"
}


#EOC

#BOP
# !FUNCTION: _list_files_array
# !INTERFACE: _list_files_array VAR_NAME SRC_DIR [find_args...]
# !DESCRIPTION:
#   Populate the array named VAR_NAME with the basenames of files found in
#   SRC_DIR (optionally filtered with extra find(1) arguments).
#
# !USAGE:
#   _list_files_array filesArray /path/to/src -name '*.txt'
#
# !BEHAVIOR:
#   • Validates inputs and clears the target array
#   • Runs a pruned, single-level search: find -L SRC_DIR -maxdepth 1 -type f ...
#   • Stores only basenames into VAR_NAME
#   • Emits [DEBUG]/[INFO] logs if $verbose=true
#
# !NOTES:
#   • Requires Bash 4+ (nameref)
#   • Safe if no matches: returns 0 with an empty array
#EOP
#BOC
_list_files_array() {
  # optional strict mode if your helper exists
  if declare -F with_strict_mode >/dev/null 2>&1; then with_strict_mode; fi

  local __outvar="${1:?VAR_NAME required}"
  local src_dir="${2:?SRC_DIR required}"
  shift 2 || true

  # nameref to external array
  local -n __arr_ref="$__outvar" 2>/dev/null || {
    _log_err "Target array '%s' is not a valid name" "$__outvar"
    return 2
  }
  __arr_ref=()
  _log_debug "list_files_array: dir=%s filters=%q" "$src_dir" "$*"

  if [[ ! -d "$src_dir" ]]; then
    _log_warn "Source directory not found: %s" "$src_dir"
    return 0
  fi


  # Collect matches (null-delimited)
  local -a __found=()
  if ! mapfile -d '' -t __found < <(find -L "$src_dir" -maxdepth 1 -type f "$@" -print0 2>/dev/null); then
    _log_warn "find failed in %s with args: %q" "$src_dir" "$*"
    return 0
  fi
  
  # Fill array with basenames
  local p
  for p in "${__found[@]}"; do
    __arr_ref+=( "$(basename -- "$p")" )
  done

  _log_debug "list_files_array: found=%s" "${#__arr_ref[@]}"
  _log_info "Found %d file(s) in %s" "${#__arr_ref[@]}" "$src_dir"
  return 0
}
#EOC

#BOP
# !FUNCTION: _progress_bar
# !INTERFACE: _progress_bar <current> <total> <message>
# !DESCRIPTION:
#   Render a simple textual progress bar (width=40) with percentage and counters.
#
# !USAGE:
#   _progress_bar 3 10 "Copying files"
#
# !BEHAVIOR:
#   • Prints a single updating line with carriage return
#   • Shows percent complete and current/total count
#
# !EXAMPLE:
#   for i in {1..10}; do
#     _progress_bar "$i" 10 "Processing"
#     sleep 0.2
#   done
#EOP
#BOC
_progress_bar() {
  local current=${1:-0} total=${2:-0} msg="${3:-Processing}"
  local width=40
  (( total <= 0 )) && { printf "\r%s[INFO]%s %s [no files]\n" "$C_INFO" "$C_RST" "$msg"; return; }
  (( current < 0 )) && current=0
  (( current > total )) && current=$total

  local progress=$(( current * width / total ))
  local percent=$(( 100 * current / total ))

  local bar=""
  for ((i=0; i<width; i++)); do
    if (( i < progress )); then bar+="█"; else bar+="░"; fi
  done
  printf "\r%s[ACTION]%s %s [%s] %3d%% (%d/%d) " \
         "$C_ACT" "$C_RST" "$msg" "$bar" "$percent" "$current" "$total"
}
#EOC

#BOP
# !FUNCTION: _copy_one_safe
# !INTERFACE: _copy_one_safe SRC DST [METHOD]
# !DESCRIPTION:
#   Safely copy or link a single file from SRC to DST.
#
#   METHOD:
#     - copy     : atomic copy (cp -p to temp, then mv), preserves mode/mtime
#     - hardlink : create a hard link (fails if across filesystems)
#     - symlink  : create/replace a symlink to SRC (absolute target)
#     Aliases: link → hardlink, simlink → symlink
#
#   Behavior:
#     - If DST is an existing directory, the file is placed as DST/basename(SRC).
#     - Parent directory of final destination is created as needed.
#     - Returns non-zero on errors; prints concise error messages to stderr.
#
# !USAGE:
#   _copy_one_safe /data/in/a.bin /data/out copy
#   _copy_one_safe /data/in/a.bin /data/out/another.bin symlink
#   _copy_one_safe /data/in/a.bin /data/out link
#
# !RETURNS:
#   0  ok
#   1  invalid arguments
#   2  source missing or not a regular file
#   3  hardlink across different filesystems
#   4  operation failed (cp/ln/mv errors)
#
# !NOTES:
#   - Portable stat device check (GNU/BSD) to detect cross-FS for hardlink.
#   - Uses absolute SRC path for symlink to avoid broken links when cwd changes.
#EOP
#BOC
_copy_one_safe() {
  _with_strict_mode   # enable strict mode only for this function

  local src="${1:-}"; local dst="${2:-}"; local method="${3:-copy}"
  _log_debug "copy_one_safe: src=%s dst=%s method=%s" "${src:-<nil>}" "${dst:-<nil>}" "$method"

  [[ -n "${src}" && -n "${dst}" ]] || { _log_err "copy_one_safe: missing SRC or DST\n" >&2; return 1; }

  # normalize method aliases
  case "${method}" in
    copy|hardlink|symlink) ;;
    link)    method="hardlink" ;;   # alias
    simlink) method="symlink"  ;;   # alias (common typo)
    *) _log_err "copy_one_safe: unknown METHOD '%s' (expected copy|hardlink|symlink)\n" "${method}" >&2; return 1 ;;
  esac

  # source checks
  if [[ ! -e "${src}" ]]; then
    _log_err "copy_one_safe: source does not exist: %s\n" "${src}" >&2
    return 2
  fi
  if [[ ! -f "${src}" ]]; then
    _log_err "copy_one_safe: source is not a regular file: %s\n" "${src}" >&2
    return 2
  fi

  # resolve destination path: if DST is a directory, append basename(SRC)
  local dst_path="${dst}"
  if [[ -d "${dst_path}" ]]; then
    dst_path="${dst%/}/$(basename -- "${src}")"
  fi
  # ensure parent dir exists
  local parent; parent="$(dirname -- "${dst_path}")"
  if [[ "${dry_run:-false}" == true ]]; then
    _log_action "[DRY-RUN] ensure dir: %s" "$parent"
  else
    mkdir -p -- "$parent" || { _log_err "mkdir -p '%s' failed" "$parent"; return 4; }
  fi

  # absolute source path (for symlink target)
  local src_abs; src_abs="$(cd -- "$(dirname -- "${src}")" && pwd)/$(basename -- "${src}")"
  _log_debug "copy_one_safe paths: src_abs=%s final_dst=%s" "$src_abs" "$dst_path"

  # device id helper (GNU/BSD)
  _dev_id() { stat -Lc %d "$1" 2>/dev/null || stat -f %d "$1" 2>/dev/null; }

  case "${method}" in
    copy)
      if [[ "${dry_run:-false}" == true ]]; then
        _log_action "[DRY-RUN] copy %s -> %s" "$src_abs" "$dst_path"
      else
        # atomic-ish copy: cp to temp in same dir, then mv
        local tmp="${dst_path}.tmp.$$"
        # -p preserve mode/mtime; -f overwrite temp if exists
        cp -pf -- "${src_abs}" "${tmp}" 2>/dev/null || { _log_err "cp '%s' -> '%s' failed" "${src_abs}" "${tmp}"; rm -f -- "${tmp}" 2>/dev/null || true; return 4; }
        mv -f -- "${tmp}" "${dst_path}" 2>/dev/null || { _log_err "mv '%s' -> '%s' failed" "${tmp}" "${dst_path}"; rm -f -- "${tmp}" 2>/dev/null || true; return 4; }
      fi
      ;;

    hardlink)
      if [[ "${dry_run:-false}" == true ]]; then
        _log_action "[DRY-RUN] hardlink %s -> %s" "$src_abs" "$dst_path"
      else
        # must be same filesystem
        local sdev ddev
        sdev="$(_dev_id "$(dirname -- "${src_abs}")")" || { _log_err "stat device(src) failed\n" >&2; return 4; }
        ddev="$(_dev_id "$(dirname -- "${dst_path}")")" || { _log_err  "stat device(dst) failed\n" >&2; return 4; }
        if [[ "${sdev}" != "${ddev}" ]]; then
          printf "[ERROR] hardlink across filesystems: %s -> %s\n" "${src_abs}" "${dst_path}" >&2
          return 3
        fi
        ln -f -- "${src_abs}" "${dst_path}" 2>/dev/null || { _log_err "ln (hardlink) failed: %s -> %s\n" "${src_abs}" "${dst_path}" >&2; return 4; }
      fi
      ;;

    symlink)
      if [[ "${dry_run:-false}" == true ]]; then
        _log_action "[DRY-RUN] symlink %s -> %s" "$src_abs" "$dst_path"
      else
        # replace existing file/symlink
        ln -sfn -- "${src_abs}" "${dst_path}" 2>/dev/null || { _log_err "ln -s failed: %s -> %s\n" "${src_abs}" "${dst_path}" >&2; return 4; }
      fi
      ;;
  esac
  
  _log_debug "copy_one_safe done: %s -> %s (%s)" "$src_abs" "$dst_path" "$method"

  return 0
}
#EOC

#BOP
# !FUNCTION: _copy_with_progress
# !INTERFACE: _copy_with_progress <ARRAY_NAME> <SRC_DIR> <DEST_DIR> [ACTION] [MESSAGE]
# !DESCRIPTION:
#   Copy or link a list of files with a clean, minimal progress layout.
#   This implementation draws a TTY progress bar (or emits concise ACTION lines
#   when not attached to a TTY) and avoids rsync entirely. It is ideal when you
#   prefer a compact, consistent look across environments.
#
# !PARAMETERS:
#   ARRAY_NAME  Name of a Bash array variable holding basenames (no [@]).
#   SRC_DIR     Directory where files are read from.
#   DEST_DIR    Directory where files are written to.
#   ACTION      copy (default) | symlink|link|ln|sym | hardlink|hlink|hln
#   MESSAGE     Optional label for progress/log output (default: "Processing files").
#
# !BEHAVIOR:
#   • Respects global flags: dry_run, verbose, debug.
#   • Creates DEST_DIR if needed (mkdir -p).
#   • Progress:
#       - TTY: single-line progress bar via _progress_bar.
#       - Non-TTY: numbered ACTION logs.
#   • Copy semantics:
#       - copy: cp -pf; skips if cmp -s indicates unchanged.
#       - symlink: ln -sfn.
#       - hardlink: ln -f with fallback to copy on cross-device errors.
#
# !RETURNS:
#   0 on success; non-zero on first encountered error.
#
# !NOTES:
#   • Requires Bash 4+ (nameref).
#   • Preferred when you want the lightweight, non-rsync layout.
#EOP
#BOC
_copy_with_progress() {
  _with_strict_mode   # enable strict mode only for this function

  local -n _files_ref="$1"; shift        # nameref to the input array
  local src_dir="$1"; shift
  local dest_dir="$1"; shift
  local action="${1:-copy}"; shift || true
  local progress_msg="${1:-Processing files}"

  _log_debug "copy_with_progress: action=%s src=%s dest=%s total=%s" "$action" "$src_dir" "$dest_dir" "${#_files_ref[@]}"
  if [[ "${dry_run:-false}" == true ]]; then
    local f; for f in "${_files_ref[@]}"; do
      _log_action "[DRY-RUN] %s %s -> %s" "$action" "${src_dir%/}/$f" "${dest_dir%/}/$f"
    done
    _log_ok "%s: %d/%d processed (dry-run)" "$progress_msg" "${#_files_ref[@]}" "${#_files_ref[@]}"
    return 0
  fi

  mkdir -p -- "$dest_dir" || { _log_err "mkdir -p '%s' failed" "$dest_dir"; return 1; }

  local total=${#_files_ref[@]}
  (( total == 0 )) && { _log_info -f "%s [nothing to do]" "$progress_msg"; return 0; }

  local count=0 f src dst
  for f in "${_files_ref[@]}"; do
    ((count++))
    src="${src_dir%/}/$f"
    dst="${dest_dir%/}/$f"

    if [[ ! -e "$src" ]]; then
      _log_warn "Missing: %s" "$src"
      continue
    fi
    
    # Skip if src and dst are the same file (same inode/device)
    if [[ -e "$dst" ]] && [[ "$src" -ef "$dst" ]]; then
      _log_debug "Same file (skipping): %s" "$dst"
      [[ -t 1 ]] && _progress_bar "$count" "$total" "$progress_msg"
      continue
    fi

    # Show progress/log before executing
    if [[ -t 1 ]]; then
      _progress_bar "$count" "$total" "$progress_msg"
    else
      _log_action -f "(%d/%d) %s -> %s" "$count" "$total" "$src" "$dst"
    fi

    case "$action" in
      copy)
        # If destination exists and contents are identical, skip quietly
        if [[ -e "$dst" ]] && cmp -s -- "$src" "$dst"; then
          _log_debug "Unchanged (skipping): %s" "$dst"
        else
          # Ensure parent dir exists (in case list has subpaths)
          mkdir -p -- "$(dirname -- "$dst")" || { _log_err "mkdir -p '%s' failed" "$(dirname -- "$dst")"; return 1; }
          cp -pf -- "$src" "$dst" || { _log_err "Failed to copy '%s' -> '%s'" "$src" "$dst"; return 1; }
        fi
        ;;
      symlink|link|ln|sym)
        mkdir -p -- "$(dirname -- "$dst")" || { _log_err "mkdir -p '%s' failed" "$(dirname -- "$dst")"; return 1; }
        ln -sfn -- "$src" "$dst" || { _log_err "Failed to symlink '%s' -> '%s'" "$src" "$dst"; return 1; }
        ;;
      hardlink|hlink|hln)
        mkdir -p -- "$(dirname -- "$dst")" || { _log_err "mkdir -p '%s' failed" "$(dirname -- "$dst")"; return 1; }
        # Hard links must be on the same filesystem; if fails, fall back to copy
        if ! ln -f -- "$src" "$dst" 2>/dev/null; then
          _log_warn "Hardlink failed (cross-device?), falling back to copy: %s" "$dst"
          cp -pf -- "$src" "$dst" || { _log_err "Failed to copy '%s' -> '%s' (fallback)" "$src" "$dst"; return 1; }
        fi
        ;;
      *)
        _log_err "Unknown action '%s' (expected: copy|symlink|hardlink)" "$action"
        return 2
        ;;
    esac
  done

  # In TTY, the bar draws inline; append a clean OK marker once.
  if [[ -t 1 ]]; then
    printf " - $C_OK[OK]$C_RST\n"
  else
    _log_ok "%s done" "$progress_msg"
  fi
  return 0
}
#EOC

#BOP
# !FUNCTION: _copy_with_progress_rsync
# !INTERFACE: _copy_with_progress_rsync <array_name> <src_dir> <dest_dir> [copy|link] ["Message"]
# !DESCRIPTION:
#   Copy or link a list of files from a source directory to a destination
#   directory, with progress reporting. Supports two modes:
#     • If `rsync` is available → uses `rsync -a --human-readable --info=progress2`
#       for detailed progress (percentage, bytes, ETA).
#     • If `rsync` is not available → falls back to `_copy_with_progress`
#       which draws a simple progress bar (TTY only).
#   Also supports dry-run mode (global var `dry_run=true`) where operations are
#   only logged, not executed.
#
# !USAGE:
#   files=(file1 file2 file3)
#   _copy_with_progress_ files /path/src /path/dest copy "Copying input files"
#
# !OPTIONS:
#   array_name   Name of the bash array variable containing filenames (not expanded with [@]).
#   src_dir      Source directory containing the files.
#   dest_dir     Destination directory for copy/link.
#   action       Either "copy" (default) or "link".
#   message      Optional label for logging (default: "Copying files").
#
# !BEHAVIOR:
#   • Creates destination directory if missing.
#   • For each file in array:
#       - Verifies existence in src_dir.
#       - Executes copy/link or logs action if dry-run.
#       - Logs progress:
#           · With rsync: clean numeric progress (percentage, size, ETA).
#           · Without rsync: falls back to `_copy_with_progress` (TTY bar).
#   • Reports total processed vs expected at the end.
#
# !NOTES:
#   - Requires `_log_info`, `_log_warn`, `_log_action`, `_log_ok` helpers for logging.
#   - Respects global `dry_run` variable (true/false).
#   - Designed for internal use inside higher-level workflows.
#EOP
#BOC
_copy_with_progress_rsync() {
  _with_strict_mode   # enable strict mode only for this function

  local files_name="$1"; shift                 # array name (e.g., files), without [@]
  local -n _files_ref="$files_name"            # nameref to iterate here
  local src_dir="$1"; shift
  local dest_dir="$1"; shift
  local action="${1:-copy}"; shift || true
  local progress_msg="${1:-Copying files}"
  local dry="${dry_run:-false}"
  _log_debug "rsync mode: files=%s src=%s dest=%s action=%s dry=%s" "${#_files_ref[@]}" "$src_dir" "$dest_dir" "$action" "$dry"

  if (( ${#_files_ref[@]} == 0 )); then
    _log_info "%s [nothing to do]" "$progress_msg"
    return 0
  fi

  if [[ "$dry" == true ]]; then
    local f
    for f in "${_files_ref[@]}"; do
      _log_action "[DRY-RUN] %s %s -> %s" "$action" "${src_dir%/}/$f" "$dest_dir"
    done
    _log_ok "%s: %d/%d processed (dry-run)" "$progress_msg" "${#_files_ref[@]}" "${#_files_ref[@]}"
    return 0
  fi

  mkdir -p -- "$dest_dir" || { _log_err "mkdir -p failed: %s" "$dest_dir"; return 1; }

  local total=${#_files_ref[@]}
  echo "total: ${total}"
  if (( total == 0 )); then
    _log_info "%s [nothing to do]" "$progress_msg"
    return 0
  fi

  # No rsync: delegate to simple bar (with dry-run handling)
  if ! command -v rsync >/dev/null 2>&1; then
    _log_debug "rsync not found; falling back to simple progress"

    if $dry; then
      local f
      for f in "${_files_ref[@]}"; do
        _log_info "Dry-run: would %s %s -> %s/" "$action" "${src_dir%/}/$f" "$dest_dir"
      done
      _log_ok "%s: %d/%d processed (dry-run)" "$progress_msg" "$total" "$total"
      return 0
    fi
    _copy_with_progress "$files_name" "$src_dir" "$dest_dir" "$action" "$progress_msg"
    return $?
  fi

  # With rsync: show --info=progress2
  local n=0 ok=0 f src dst
  for f in "${_files_ref[@]}"; do
    src="${src_dir%/}/$f"
    dst="${dest_dir%/}/$f"

    if [[ ! -e "$src" ]]; then
      _log_warn "Missing: %s" "$src"
      continue
    fi

    ((n++))
    _log_action "(%d/%d) %s -> %s" "$n" "$total" "$src" "$dst"

    case "$action" in
      copy)
        if rsync -ai --dry-run -- "$src" "$dest_dir"/ | grep -q '^[^\.]'; then
          rsync -a --human-readable --partial \
                --info=progress2,name0 \
                -i --out-format='%i %n' -- "$src" "$dest_dir"/ && ((ok++)) || _log_warn "rsync failed: %s" "$src"
        else
          _log_info "Up-to-date: %s -> %s/" "$src" "$dest_dir"
          ((ok++))
        fi
        ;;
      link)
        if ln -sf -- "$src" "$dst"; then
          ((ok++))
        else
          _log_warn "link failed: %s" "$src"
        fi
        ;;
      *)
        _log_warn "Unknown action: %s (skipping)" "$action"
        ;;
    esac
  done

  _log_ok "%s: %d/%d processed" "$progress_msg" "$ok" "$total"
}
#EOC

#BOP
# !FUNCTION: _copy_with_progress_auto
# !INTERFACE: _copy_with_progress_auto <ARRAY_NAME> <SRC_DIR> <DEST_DIR> [ACTION] [MESSAGE]
# !DESCRIPTION:
#   Convenience wrapper that chooses between the simple layout and the rsync
#   layout without removing either implementation.
#
# !BEHAVIOR:
#   • Honors COPY_BACKEND env var:
#       - "simple" (default): calls _copy_with_progress.
#       - "rsync": calls _copy_with_progress_rsync.
#       - "auto": uses rsync only for ACTION=copy when rsync is available;
#                 otherwise uses the simple layout.
#   • Respects dry_run/verbose/debug through underlying helpers.
#
# !USAGE:
#   COPY_BACKEND=simple _copy_with_progress_auto files ./in ./out copy "Copying"
#   COPY_BACKEND=rsync  _copy_with_progress_auto files ./in ./out copy "Copying"
#   COPY_BACKEND=auto   _copy_with_progress_auto files ./in ./out copy "Copying"
#EOP
#BOC
_copy_with_progress_auto() {
  _with_strict_mode   # enable strict mode only for this function

  local backend="${COPY_BACKEND:-simple}" action="${4:-copy}"
  case "$backend" in
    rsync) _copy_with_progress_rsync "$@";;
    auto)
      if [[ "$action" == "copy" ]] && command -v rsync >/dev/null 2>&1; then
        _copy_with_progress_rsync "$@"
      else
        _copy_with_progress "$@"
      fi
      ;;
    simple|*) _copy_with_progress "$@";;
  esac
}
#EOC

#BOP
# !FUNCTION: _copy_dir_with_progress
# !INTERFACE: _copy_dir_with_progress <SRC_DIR> <DEST_DIR> [MESSAGE] [ACTION]
# !DESCRIPTION:
#   Copy or link all regular files from <SRC_DIR> into <DEST_DIR>, while
#   delegating file enumeration and progress reporting to existing helpers.
#   This is a thin wrapper that:
#     1) collects basenames from <SRC_DIR> via _list_files_array, then
#     2) calls _copy_with_progress to perform the requested ACTION.
#
# !BEHAVIOR:
#   • Depth: only files at max depth 1 (as implemented by _list_files_array).
#   • ACTION: "copy" (default), "symlink"/"link", or "hardlink" (as supported by
#     _copy_with_progress).
#   • Progress: handled by _copy_with_progress (TTY bar or rsync variant if used
#     elsewhere in your codebase).
#   • dry-run / verbose / debug: respected by the underlying helpers; this
#     wrapper does not change their semantics.
#   • Destination creation: mkdir -p (if needed) is handled inside
#     _copy_with_progress.
#
# !USAGE:
#   _copy_dir_with_progress /path/src /path/dst "Copying inputs" copy
#   _copy_dir_with_progress ./in ./out "Linking files" symlink
#
# !RETURNS:
#   0  on success.
#   >0 propagates the non-zero status from _list_files_array or _copy_with_progress.
#
# !NOTES:
#   • Requires Bash 4+ (the called _copy_with_progress uses nameref).
#   • Filtering (e.g., name patterns) should be done with _list_files_array
#     directly if you need more control; this wrapper collects all regular files.
#EOP
#BOC
_copy_dir_with_progress() {
  _with_strict_mode   # enable strict mode only for this function

  local src_dir="$1" dest_dir="$2" msg="${3:-Copying files}" action="${4:-copy}"
  local files=(); _list_files_array files "$src_dir" || return $?
  _copy_with_progress files "$src_dir" "$dest_dir" "$action" "$msg"
}
#EOC


#BOP
# !FUNCTION: _assign
# !INTERFACE: _assign <KEY> <VALUE...>
# !DESCRIPTION:
#   Define and export an environment variable from a KEY and VALUE pair,
#   expanding ${VAR} references using the current environment and variables
#   already set by previous _assign calls.
#
# !USAGE:
#   _assign HOME /home/${USER}
#   _assign subt_SPACK ${SUBMIT_HOME}/${nome_SPACK}
#
# !BEHAVIOR:
#   • Joins VALUE arguments into a single string
#   • Expands variable references like ${USER}, ${SUBMIT_HOME}
#   • If `envsubst` is available, uses it for expansion
#   • Otherwise, uses a safe eval/printf fallback (disallows command substitution)
#   • Exports KEY=expanded_value to the shell environment
#
# !NOTES:
#   • Order matters: referenced variables must be defined earlier
#   • Does not allow backticks, $(), or arithmetic $(( )) substitutions
#EOP
#BOC
_assign() {
  local key="${1:?KEY required}"; shift
  # Join VALUE... preserving internal spaces
  local raw="$*"

  # Safe expansion using envsubst, if available
  if command -v envsubst >/dev/null 2>&1; then
    local expanded
    if ! expanded="$(printf '%s' "$raw" | envsubst)"; then
      _log_err "_assign: envsubst failed for %s" "$key"; return 1
    fi
    export "$key=$expanded"
    _log_debug "_assign: %s=%q (len=%d)" "$key" "$expanded" "${#expanded}"
    return 0
  fi

  # Fallback without envsubst: block command substitution
  if printf '%s' "$raw" | grep -Eq '(`|\$\(|\$\(\()'; then
    _log_err "_assign: forbidden command substitution in value for $key" >&2
    return 1
  fi

  # Perform only variable expansion ${VAR} / $VAR using eval+printf
  # shellcheck disable=SC2086
  local expanded
  expanded="$(eval "printf '%s' \"$raw\"")" || { _log_err "_assign: eval failed for %s" "$key"; return 1; }
  export "$key=$expanded"
  _log_debug "_assign: %s=%q (len=%d)" "$key" "$expanded" "${#expanded}"
}
#EOC


#BOP
# !FUNCTION: _resolve_script_dir
# !INTERFACE: _resolve_script_dir <out_var> [bash_source]
# !DESCRIPTION:
#   Resolve the canonical absolute directory of a script, following symlinks.
#   Writes the directory path into <out_var>.
#
# !USAGE:
#   # from inside a script
#   _resolve_script_dir RUN_GSI_DIR "${BASH_SOURCE[0]}"
#   echo "Script dir is $RUN_GSI_DIR"
#
# !ARGUMENTS:
#   <out_var>     Name of variable to receive the resolved directory path.
#   [bash_source] Path to the script (default: "${BASH_SOURCE[0]}").
#
# !NOTES:
#   • Follows symlinks recursively until the real file is found.
#   • Uses pwd -P to resolve .. and symlinked dirs as well.
#   • Safe under set -euo pipefail.
#EOP
#BOC
_resolve_script_dir() {
  local __out="${1:?out var required}"
  local __src="${2:-${BASH_SOURCE[0]}}"
  local __orig="$__src"

  # Follow symlinks
  while [[ -L "$__src" ]]; do
    local __link; __link="$(readlink -- "$__src")"
    if [[ "$__link" = /* ]]; then
      __src="$__link"
    else
      __src="$(cd -- "$(dirname -- "$__src")" && cd -- "$(dirname -- "$__link")" && pwd)/$(basename -- "$__link")"
    fi
  done

  # Assign result = directory of resolved file
  local __dir
  __dir="$(cd -- "$(dirname -- "$__src")" && pwd -P)"
  printf -v "$__out" '%s' "$__dir"

  _log_debug "resolve_script_dir: input=%s resolved_dir=%s" "$__orig" "$__dir"
}
#EOC

###############################################################################
#BOP
# !FUNCTION: project_root_of
#
# !INTERFACE:
#   project_root_of [<start_path>]
#
# !DESCRIPTION:
#   Find the project root directory by walking up from <start_path> until any
#   known marker is found. If <start_path> is omitted, the function starts from
#   the caller script (BASH_SOURCE[1]) or $PWD as a last resort.
#
# !USAGE:
#   root="$(project_root_of)"                  # auto-detect from caller
#   root="$(project_root_of /some/path)"       # start from explicit path
#
# !BEHAVIOR:
#   • Markers (OR logic) from ${PROJECT_MARKERS}, colon-separated; default:
#       ".git:pyproject.toml:setup.py:config_SPACK.ksh:etc/mach"
#   • If markers are not found and Git is available, tries:
#       git rev-parse --show-toplevel
#
# !RETURNS:
#   Prints the detected root to stdout and returns 0; returns 1 on failure.
#
# !NOTES:
#   - Pure function (no exports). Uses _with_strict_mode and your loggers.
#   - Portable: avoids GNU readlink -f; relies on cd -P / pwd -P.
#
#EOP
###############################################################################
#BOC
project_root_of() {
  _with_strict_mode   # enable strict mode only for this function

  # Determine a sensible starting point:
  # prefer the *caller* file (BASH_SOURCE[1]) over this helpers file (BASH_SOURCE[0])
  local start="${1:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]:-$PWD}}}"
  local dir
  if [[ -d "$start" ]]; then
    dir="$(cd -P -- "$start" && pwd -P)" || { _log_err "Invalid start dir: %s" "$start"; return 1; }
  else
    dir="$(cd -P -- "$(dirname -- "$start")" && pwd -P)" || { _log_err "Invalid start path: %s" "$start"; return 1; }
  fi

  # Configure markers (colon-separated)
  local default_markers=".SPACK_root:config_SPACK.ksh:.git"
  local markers_str="${PROJECT_MARKERS:-$default_markers}"
  local IFS=':' markers=()
  read -r -a markers <<< "$markers_str"
  _log_debug "Searching project root from: %s (markers: %s)" "$dir" "$markers_str"

  # Walk up looking for any marker
  while : ; do
    for m in "${markers[@]}"; do
      if [[ -e "$dir/$m" ]]; then
        _log_debug "Marker matched: %s at %s" "$m" "$dir"
        _log_info "Project root found at: %s (marker: %s)" "$dir" "$m"
        printf '%s\n' "$dir"
        return 0
      fi
    done
    local parent
    parent="$(dirname -- "$dir")"
    [[ "$parent" == "$dir" ]] && break
    dir="$parent"
  done

  # Fallback to Git (optional)
  if command -v git >/dev/null 2>&1; then
    local gtop
    gtop="$(cd -P -- "${start%/*:-$PWD}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || true
    if [[ -n "$gtop" ]]; then
      _log_warn "Markers not found; using Git top-level: %s" "$gtop"
      printf '%s\n' "$gtop"
      return 0
    fi
  fi

  _log_err "Unable to locate project root from: %s" "$start"
  return 1
}
#EOC

#BOP
# !FUNCTION: _bootstrap_env_root
# !INTERFACE: _bootstrap_env_root <ENV_VAR> <ANCHOR_FILE>
# !DESCRIPTION:
#   Ensure that environment variable <ENV_VAR> points to the project root.
#   If <ENV_VAR> is already set (non-empty), the function is idempotent and
#   does nothing. Otherwise, it discovers the root by walking upward from the
#   *caller* script (BASH_SOURCE[1]; falls back to $PWD) using `project_root_of`.
#
# !BEHAVIOR:
#   • Idempotent: if <ENV_VAR> is already set, returns 0 without changes.
#   • Honors PROJECT_MARKERS when already defined; if unset, temporarily uses
#     a default of ".SPACK_root:<ANCHOR_FILE>" during discovery.
#   • No dry-run simulation (this function configures process environment).
#   • On failure to detect the root, returns non-zero and logs the context.
#
# !USAGE:
#   # Typical auto-init in a helpers file:
#   _bootstrap_env_root SPACK_ROOT ".SPACK_root" || exit $?
#
# !RETURNS:
#   0  success (ENV_VAR exported, or already set)
#   1  failure to detect the root (project_root_of did not find markers)
#
# !NOTES:
#   • Requires Bash 4+.
#   • Default markers are only applied when PROJECT_MARKERS is unset; otherwise
#     the existing PROJECT_MARKERS are used as-is.
#   • Marker validation is delegated to `project_root_of`.
#
# !EXAMPLE:
#   # Use a custom anchor alongside .SPACK_root:
#   _bootstrap_env_root MY_ROOT ".project_root"
#   printf 'Root = %s\n' "$MY_ROOT"
#EOP
#BOC
_bootstrap_env_root() {
  _with_strict_mode   # enable strict mode only for this function

  local env_var="${1:-}"
  local anchor="${2:-}"

  # Argument validation
  if [[ -z "$env_var" || -z "$anchor" ]]; then
    _log_err "_bootstrap_env_root: missing arguments (ENV_VAR='%s' ANCHOR='%s')" \
             "${env_var:-<unset>}" "${anchor:-<unset>}"
    return 1
  fi

  # Already set? Be idempotent.
  # (Use indirect expansion rather than eval.)
  local current="${!env_var-}"
  if [[ -n "$current" ]]; then
    _log_debug "_bootstrap_env_root: %s already set → %s" "$env_var" "$current"
    return 0
  fi

  # Discovery start point (prefer the caller over this file)
  local start="${BASH_SOURCE[1]:-${PWD}}"
  _log_debug "_bootstrap_env_root: start=%s anchor=%s env_var=%s" "$start" "$anchor" "$env_var"

  # Prepare markers (preserve and restore PROJECT_MARKERS around discovery)
  local prev_markers="${PROJECT_MARKERS-}"
  local markers="${PROJECT_MARKERS:-.SPACK_root:$anchor}"
  PROJECT_MARKERS="$markers"
  _log_debug "_bootstrap_env_root: markers=%s (prev=%s)" "$markers" "${prev_markers:-<unset>}"

  # Root discovery
  local root rc=0
  if ! root="$(project_root_of "$start")"; then
    rc=$?
    # Restore previous PROJECT_MARKERS before returning
    if [[ -n "${prev_markers+x}" ]]; then
      PROJECT_MARKERS="$prev_markers"
    else
      unset PROJECT_MARKERS
    fi
    _log_err "_bootstrap_env_root: project_root_of failed (rc=%d) [start=%s, markers=%s]" \
             "$rc" "$start" "$markers"
    return 1
  fi

  # Restore PROJECT_MARKERS
  if [[ -n "${prev_markers+x}" ]]; then
    PROJECT_MARKERS="$prev_markers"
  else
    unset PROJECT_MARKERS
  fi

  # Export target env var
  printf -v "$env_var" '%s' "$root"
  export "$env_var"
  _log_info "Set %s → %s" "$env_var" "$root"

  return 0
}
#EOC

#BOP
# !FUNCTION: _run_project_config
# !INTERFACE: _run_project_config <ENV_VAR> <CONFIG_FILENAME> <TARGET_FN> [ARGS...]
# !DESCRIPTION:
#   Source a project config file located at "<$ENV_VAR>/<CONFIG_FILENAME>" and
#   invoke <TARGET_FN> (a function expected to be defined by that file),
#   forwarding any optional [ARGS...]. Designed to be fail-soft with clear logs:
#   it emits informative DEBUG/ERROR/WARN/OK messages and returns non-zero on
#   recoverable errors so the caller can decide what to do next.
#
# !PARAMETERS:
#   ENV_VAR         Name of an environment variable that holds the project root
#                   directory (e.g., "SPACK_ROOT").
#   CONFIG_FILENAME File name relative to the resolved root (e.g., "config_SPACK.sh").
#   TARGET_FN       Function symbol to call after sourcing the config
#                   (e.g., "_env_export").
#   ARGS...         Optional arguments forwarded to TARGET_FN.
#
# !BEHAVIOR:
#   • Strict scope: enables `set -euo pipefail` only within this function.
#   • Resolves the root from ENV_VAR; if unset/empty, logs an error advising
#     `_bootstrap_env_root` and returns 2.
#   • Builds "<root>/<CONFIG_FILENAME>" and verifies it exists; else returns 3.
#   • Sources the file via `_source_or_explain` (expected to log/handle details).
#   • Verifies <TARGET_FN> is defined after sourcing; else returns 4.
#   • Calls <TARGET_FN> with [ARGS...]; on non-zero exit, logs a warning and
#     returns 5; otherwise logs OK and returns 0.
#   • No dry-run simulation: this function intentionally performs real sourcing
#     and invocation (it configures live shell state).
#
# !RETURNS:
#   0  success (config sourced and TARGET_FN ran successfully)
#   2  ENV_VAR is unset/empty
#   3  config file not found at "<root>/<CONFIG_FILENAME>"
#   4  TARGET_FN is not defined after sourcing the config
#   5  TARGET_FN returned non-zero
#
# !NOTES:
#   • Requires Bash 4+.
#   • `_source_or_explain <path>` must exist; if you don’t have it, replace the
#     call with a plain `source "$path"` (and ensure you log appropriately).
#   • Security: sourcing executes code from the file; only source trusted paths.
#   • Side effects: any exports or definitions in the config persist in the
#     caller environment by design (since sourcing happens in the current shell).
#   • Logging: honors global `verbose`/`debug`; errors always print.
#
# !EXAMPLES:
#   # Minimal usage
#   _run_project_config SPACK_ROOT "SPACK_setup.sh" _env_export
#
#   # With arguments forwarded to the target function
#   _run_project_config SPACK_ROOT "SPACK_setup.sh" compile "--all" "--no-gsi"
#
#   # Handling failures explicitly
#   if ! _run_project_config SPACK_ROOT "SPACK_setup.sh" _env_export; then
#     _log_fail "Project environment could not be initialized"; exit 1
#   fi
#EOP
#BOC
_run_project_config() {
  _with_strict_mode   # enable strict mode only for this function

  local env_var="${1:?env var required}"                # e.g., SPACK_ROOT
  local cfg_file="${2:?config filename required}"       # e.g., SPACK_setup.sh
  local target="${3:?target function required}"         # e.g., _env_export
  shift 3 || true
  local -a target_args=( "$@" )

  # Resolve root from env_var
  local root
  eval "root=\"\${$env_var:-}\""
  if [[ -z "$root" ]]; then
    _log_err "%s is not set; call _bootstrap_env_root first" "$env_var"
    return 2
  fi

  local cfg_path="${root%/}/${cfg_file}"
  if [[ ! -f "$cfg_path" ]]; then
    _log_err "Config not found: %s" "$cfg_path"
    return 3
  fi

  _log_debug "run_project_config: cfg=%s target=%s args=[%s]" "$cfg_path" "$target" "${target_args[*]}"

  # Source defensively and then call the target if defined
  _source_or_explain "$cfg_path" || true
  if ! declare -F "$target" >/dev/null 2>&1; then
    _log_err "Target not defined after sourcing config: %s" "$target"
    return 4
  fi

  # Call target
  if ! "$target" "${target_args[@]}"; then
    _log_warn "Target %s returned non-zero" "$target"
    return 5
  fi

  _log_ok "Config %s executed: %s" "$cfg_file" "$target"
  return 0
}
#EOC

# -----------------------------------------------------------------------------
# Auto-init: resolve SPACK_ROOT when this helpers file is sourced
# Guard: __HELPERS_SH_LOADED avoids re-entrancy
#
# Behavior:
#   • Calls: _bootstrap_env_root SPACK_ROOT ".SPACK_root"
#   • Start path: handled inside _bootstrap_env_root (uses BASH_SOURCE[1] or $PWD)
#   • No-op when SPACK_ROOT is already set or the guard is true
#
# Notes:
#   • Do NOT use 'local' at top-level (invalid in Bash outside functions).
#   • Keep the anchor file customizable if needed (via the 'sentinel' var below).
# -----------------------------------------------------------------------------
if [[ "${__HELPERS_SH_LOADED:-false}" != true ]]; then
  # --- Default logging debugging (exported for downstream scripts) ---
  export debug=${debug:-false}

  # Determine the marker (anchor) used to locate the SPACK root. If $SPACK_ANCHOR is unset,
  # default to ".SPACK_root". _bootstrap_env_root will use this to bootstrap paths/env.
  anchor="${ANCHOR:-.spack_root}"
  _log_debug "Auto-init helpers: calling _bootstrap_env_root (anchor=%s)" "$anchor"

  # --- Absolute path to the directory where this helpers script resides ---
  export helpers_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  
  # Try to resolve and export SPACK_ROOT using the generic bootstrapper.
  # It is safe to proceed even if it returns non-zero (caller may handle later).
  _bootstrap_env_root SPACK_ROOT "$anchor" || \
    _log_warn "Auto-init: SPACK_ROOT autodetection failed; current=%s" "${SPACK_ROOT:-<unset>}"

  __HELPERS_SH_LOADED=true
  export __HELPERS_SH_LOADED
  _log_debug "Auto-init done; SPACK_ROOT=%s" "${SPACK_ROOT:-<unset>}"
fi



