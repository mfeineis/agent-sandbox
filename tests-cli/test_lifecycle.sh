#!/bin/sh
# Lifecycle regression tests: sourced individual function bodies, mocked SSH.
# No QEMU, root, cloud-init, proxy, or Python required.
set -eu
HERE=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
FB=$HERE/firebreak
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
fail() { printf 'FAIL lifecycle: %s\n' "$*" >&2; exit 1; }
extract() { sed -n "/^$1() {/,/^}/p" "$FB" > "$T/$1.sh"; [ -s "$T/$1.sh" ] || fail "missing function $1"; }
for name in wait_cloud finish_provisioning apply_guest install_gvisor_if_missing runtime_for_profile; do extract "$name"; done

# Regression: an old gVisor cloud-init failure is terminal but not a permanent
# provisioning veto; the subsequent checks must decide whether it is safe.
(
  set -eu
  NAME=testvm TMP=$T VM_PID=$$ CLOUD_STATE=unknown
  say() { :; }
  die() { fail "$*"; }
  boot_diagnostics() { :; }
  ssh_vm() {
    case "$1" in
      'cloud-init status 2>&1 || true') printf 'status: %s\n' "$MOCK_CLOUD_STATUS";;
      *) printf 'Historical gVisor installer failure\n';;
    esac
  }
  . "$T/wait_cloud.sh"
  MOCK_CLOUD_STATUS=error; wait_cloud
  [ "$CLOUD_STATE" = error ] || fail 'terminal cloud-init error blocked recovery'
  grep -Fq 'Historical gVisor installer failure' "$TMP/$NAME.cloud-init-status.log" || fail 'missing historical failure log'
  MOCK_CLOUD_STATUS=degraded; wait_cloud
  [ "$CLOUD_STATE" = error ] || fail 'degraded cloud-init blocked recovery'
  MOCK_CLOUD_STATUS=done; wait_cloud
  [ "$CLOUD_STATE" = done ] || fail 'normal successful cloud-init unrecognized'
)

# The transaction must run in order and only mark provisioned after the last
# guest readiness check passes. A failed reconciliation cannot mark it ready.
(
  set -eu
  NAME=testvm TMP=$T SECRET=$T/secret CLOUD_STATE=unknown ACTIONS=$T/actions
  mkdir -p "$SECRET"
  : > "$ACTIONS"
  say() { :; }
  die() { printf '%s\n' "$*" >&2; exit 1; }
  wait_cloud() { printf '%s\n' wait >> "$ACTIONS"; CLOUD_STATE=error; }
  check_guest_packages() { printf '%s\n' packages >> "$ACTIONS"; }
  install_gvisor_if_missing() { printf '%s\n' gvisor >> "$ACTIONS"; }
  apply_guest() { printf '%s\n' apply >> "$ACTIONS"; }
  verify_guest() { printf '%s\n' verify >> "$ACTIONS"; [ "${MOCK_FAIL_VERIFY:-no}" != yes ]; }
  . "$T/finish_provisioning.sh"
  finish_provisioning
  [ -f "$SECRET/provisioned" ] || fail 'successful recovery did not mark provisioned'
  printf 'wait\npackages\ngvisor\napply\nverify\n' > "$T/expected-actions"
  cmp "$ACTIONS" "$T/expected-actions" || fail 'provisioning steps out of order'
  rm "$SECRET/provisioned"
  MOCK_FAIL_VERIFY=yes
  if ( finish_provisioning ) > "$T/verify-stdout" 2> "$T/verify-stderr"; then
    fail 'failed guest readiness check was accepted'
  fi
  [ ! -e "$SECRET/provisioned" ] || fail 'failed readiness check marked provisioned'
)

# Reconciliation must retain and surface remote SSH/stdout/stderr failures.
(
  set -eu
  NAME=testvm TMP=$T SEED=$T/seed CURRENT_PROFILE=unsafe
  mkdir -p "$SEED"; printf '#!/bin/sh\nexit 0\n' > "$SEED/reconcile.sh"
  say() { printf '%s\n' "$*" >> "$T/apply-messages"; }
  die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
  ssh_vm() {
    case "$1" in
      "/bin/sh -s -- 'unsafe' 'crun'")
        cat > "$T/captured-guest-script"
        if [ "${MOCK_RECONCILE_FAIL:-no}" = yes ]; then
          printf 'Simulated guest service failure\n' >&2
          return 12
        fi;;
      *'firebreak-proxy.sh'*) printf '%s\n' "$1" > "$T/proxy-command";;
      *) fail "unexpected SSH command: $1";;
    esac
  }
  RUNTIME_UNSAFE=crun
  . "$T/runtime_for_profile.sh"
  . "$T/apply_guest.sh"
  apply_guest
  grep -Fq 'HTTP_PROXY=http://10.0.2.100:3128' "$T/proxy-command" || fail 'unsafe mode did not install proxy profile'
  MOCK_RECONCILE_FAIL=yes
  if ( apply_guest ) > "$T/reconcile.out" 2> "$T/reconcile.err"; then
    fail 'reconciliation failure ignored'
  fi
  grep -Fq 'Simulated guest service failure' "$TMP/$NAME.apply.log" || fail 'SSH stderr not retained'
  grep -Fq 'Simulated guest service failure' "$T/reconcile.err" || fail 'failure not reported to user'
)

# Skipping an already installed gVisor avoids unnecessary network work.
(
  set -eu
  say() { :; }
  check_gvisor() { return 0; }
  ssh_vm() { fail 'already-installed gVisor unexpectedly downloaded again'; }
  . "$T/install_gvisor_if_missing.sh"
  install_gvisor_if_missing
)

grep -Fq '    finish_provisioning' "$FB" || fail 'create does not use final readiness checks'
grep -Fq 'repair|provision)' "$FB" || fail 'resumable provisioning command missing'
printf '%s\n' 'PASS: lifecycle regression tests'
