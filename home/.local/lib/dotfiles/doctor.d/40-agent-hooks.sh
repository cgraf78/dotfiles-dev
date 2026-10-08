# shellcheck shell=bash
dot_doctor_source doctor.d/lib/compat.sh || return
dot_doctor_source doctor.d/lib/dev-common.sh || return
# The marker helper is shared with the merge hooks; the file defines only
# functions, so loading it outside a merge worker is safe.
dot_doctor_source merge-hooks.d/lib/agentguard.sh || return
dot_doctor_source doctor.d/lib/agent-hooks.sh || return
dot_doctor_source doctor.d/lib/hive-memory.sh || return

doctor() {
  _dr_check_agent_tooling
}
