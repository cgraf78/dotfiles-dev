# shellcheck shell=bash
# Shared fixture for the development merge-hook suites. It lives apart from
# the suites so each one sources only the setup, not another suite's body.

# shellcheck source=helpers.sh
. "${BASH_SOURCE[0]%/*}/helpers.sh"

# Build the isolated home shared by the development merge-hook suites and
# load the public Dot hook API into it. The VS Code block runs as its own
# suite (vscode-merges.sh) so `dot test` can overlap it with the rest.
_dev_merges_setup() {
  set +e +u
  local owner_root
  owner_root=$(_dev_repo_root)
  REAL_HOME=$owner_root/home
  TEST_HOME=$(_tmpdir)
  DOT_TEST_SOURCE_HOME=$REAL_HOME
  export REAL_HOME TEST_HOME DOT_TEST_SOURCE_HOME
  mkdir -p "$TEST_HOME"
  HOME=$TEST_HOME
  DOT_QUIET=0
  export HOME DOT_QUIET
  unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME
  mkdir -p "$TEST_HOME/.config"
  cp -R "$REAL_HOME/.config/dot" "$TEST_HOME/.config/dot"
  DOT_TEST_SLEY_ROOT=$TEST_HOME/provider-sley
  mkdir -p "$DOT_TEST_SLEY_ROOT/share/sley/vscode/sley-tools-0.0.1"
  cat >"$DOT_TEST_SLEY_ROOT/share/sley/vscode/sley-tools-0.0.1/package.json" <<'JSON'
{"name":"sley-tools","displayName":"Sley Tools","publisher":"cgraf","version":"0.0.1","engines":{"vscode":"^1.80.0"},"main":"./extension.js"}
JSON
  printf '%s\n' 'module.exports = { activate() {}, deactivate() {} };' \
    >"$DOT_TEST_SLEY_ROOT/share/sley/vscode/sley-tools-0.0.1/extension.js"
  export DOT_TEST_SLEY_ROOT
  merge_support_bin=$(_mock_bin)
  cat >"$merge_support_bin/cmp" <<'CMP'
#!/usr/bin/env bash
[[ ${1:-} != -s ]] || shift
git diff --no-index --quiet -- "$1" "$2"
CMP
  chmod +x "$merge_support_bin/cmp"
  PATH="$merge_support_bin:$PATH"
  export PATH
  # shellcheck source=load-merge-api.sh
  . "$REAL_HOME/.local/lib/dotfiles/tests/dev/load-merge-api.sh" || {
    _fail 'Development merge tests load the public Dot hook API'
    return 1
  }
}
