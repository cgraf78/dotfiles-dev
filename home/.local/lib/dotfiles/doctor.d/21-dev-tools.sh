# shellcheck shell=bash
dot_doctor_source doctor.d/lib/compat.sh || return
dot_doctor_source doctor.d/lib/dev-tools.sh || return

doctor() {
  _dr_check_dev_tools
}
