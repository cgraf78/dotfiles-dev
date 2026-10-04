# shellcheck shell=bash
# dot doctor: helpers shared by the development overlay's checks.

# Run CMD... with a deadline of SECS seconds and return its status: 124
# when the deadline passed, or 137 when the command also ignored SIGTERM and
# had to be killed (see _dr_dev_deadline_status). Base's _dr_run_bounded is
# preferred: it is portable (a builtin watchdog where no coreutils timeout
# exists, as on stock macOS) and kills the command's whole process group. It
# is newer than base's compat module and base updates independently of this
# overlay, so on a base without it a coreutils timeout(1) or gtimeout bounds
# the run when one is installed, and otherwise the command runs unbounded,
# as every probe here did before deadlines; a current Dot still stops the
# whole extension at its own deadline. BusyBox's timeout is passed over, as
# base does: older ones reject -k. Call it as `_dr_dev_bounded ... ||
# status=$?`: doctor workers run under `set -e`.
_dr_dev_bounded() {
  local secs=$1 bin version
  shift
  if declare -F _dr_run_bounded >/dev/null; then
    _dr_run_bounded "$secs" "$@"
    return
  fi
  if [[ -z ${_DR_DEV_TIMEOUT_BIN+x} ]]; then
    _DR_DEV_TIMEOUT_BIN=
    for bin in timeout gtimeout; do
      bin=$(type -P "$bin" 2>/dev/null) || continue
      version=$("$bin" --version 2>/dev/null </dev/null) || continue
      [[ $version == *coreutils* ]] || continue
      _DR_DEV_TIMEOUT_BIN=$bin
      break
    done
  fi
  if [[ -n $_DR_DEV_TIMEOUT_BIN ]]; then
    "$_DR_DEV_TIMEOUT_BIN" -k 1 "$secs" "$@"
    return
  fi
  "$@"
}

# File one verdict row with its next step: LEVEL (ok, warn, fail, skip, or
# info), MESSAGE, DETAIL (may be empty), and HINT (may be empty). Base's
# _dr_hint_row does this; it is newer than base's compat module and base
# updates independently of this overlay, so on a base without it the same
# rule applies here: the hint is its own next-step line when the running
# Dot has dot_doctor_hint, and is appended to the detail after "; " (how
# every row carried its step before) when it does not.
_dr_dev_row() {
  if declare -F _dr_hint_row >/dev/null 2>&1; then
    _dr_hint_row "$@"
    return
  fi
  local level=$1 message=$2 detail=${3-} hint=${4-}
  # The same argument contract as base's helper, so a call that would fail
  # on a newer base fails here too.
  case $level in
    ok | warn | fail | skip | info) ;;
    *) return 2 ;;
  esac
  (($# == 4)) || return 2
  detail=${detail//[$'\t\r\n']/ }
  hint=${hint//[$'\t\r\n']/ }
  if [[ -n $hint ]] && declare -F dot_doctor_hint >/dev/null 2>&1; then
    "_dr_$level" "$message" "$detail" || return
    dot_doctor_hint "$hint"
    return
  fi
  "_dr_$level" "$message" "$detail${detail:+${hint:+; }}$hint"
}

# Next step for a probe that could not create its temporary directory:
# base's wording when the base has it.
_DR_DEV_TMPDIR_HINT=${_DR_TMPDIR_HINT:-"check that the temporary directory (TMPDIR, else /tmp) exists, is writable, and has free space, then rerun 'dot doctor'"}

# Succeed when status $1 from _dr_dev_bounded means the deadline passed:
# 124, or 137 when the command ignored SIGTERM and the runner killed it.
_dr_dev_deadline_status() {
  (($1 == 124 || $1 == 137))
}
