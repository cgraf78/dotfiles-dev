# shellcheck shell=bash
dot_doctor_source doctor.d/lib/compat.sh || return
dot_doctor_source doctor.d/lib/dev-common.sh || return
dot_doctor_source doctor.d/lib/agent-hooks.sh || return
dot_doctor_source doctor.d/lib/hive-memory.sh || return

doctor() {
  _dr_check_agent_tooling
}
