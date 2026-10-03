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

# Succeed when status $1 from _dr_dev_bounded means the deadline passed:
# 124, or 137 when the command ignored SIGTERM and the runner killed it.
_dr_dev_deadline_status() {
  (($1 == 124 || $1 == 137))
}
