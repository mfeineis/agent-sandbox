#!/bin/sh
# Runtime policy tests: no QEMU, root, Podman, or actual network required.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
FB=$ROOT/firebreak
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
fail() { printf 'FAIL runtime: %s\n' "$*" >&2; exit 1; }
PATH="$ROOT/tests/fixtures:$PATH"; export PATH
cd "$T"
"$FB" config init >/dev/null
[ "$("$FB" sbx __test-runtime unsafe)" = crun ] || fail 'unsafe default wrong'
[ "$("$FB" sbx __test-runtime offline)" = runsc ] || fail 'offline default wrong'
[ "$("$FB" sbx __test-runtime models)" = runsc ] || fail 'models default wrong'
printf '%s\n' 'runtime_models=crun' 'runtime_offline=crun' >> firebreak.conf
[ "$("$FB" sbx __test-runtime offline)" = crun ] || fail 'offline override ignored'
[ "$("$FB" sbx __test-runtime models)" = crun ] || fail 'models override ignored'
printf '%s\n' 'runtime_unsafe=$(id)' >> firebreak.conf
if "$FB" sbx __test-runtime unsafe >/dev/null 2>&1; then fail 'invalid runtime accepted'; fi
# Mock the *generated guest* policy using a filesystem-local rewrite of paths.
sed '/^runtime_unsafe=\$(id)$/d' firebreak.conf > clean.conf
mv clean.conf firebreak.conf
"$FB" sbx __test-render >/dev/null
sed -n '1,25p' .devcontainer/firebreak/seeds/sbx/reconcile.sh | grep -Fq 'selected_runtime=${2:?Expected OCI runtime}' || fail 'missing runtime argument validation'
grep -Fq 'podman container inspect' .devcontainer/firebreak/seeds/sbx/reconcile.sh || fail 'missing existing container safety check'
grep -Fq "rc-update del podman default" .devcontainer/firebreak/seeds/sbx/reconcile.sh || fail 'boot-time premature Podman startup not disabled'
# Test derived guest portion (stop before Forgejo) without host paths or root.
# Rewrite the managed paths to our tmp root and mock service/podman tools.
# perl/python are not required for this test: static policy assertions plus
# the profile behavior below suffice; actual guest runtime requires macOS HVF.
"$FB" --self-test >/dev/null
printf '%s\n' 'PASS: OCI runtime policy tests'

# Exercise the generated reconciliation's policy section against mock OpenRC
# and Podman, with guest system paths rewritten into our temporary directory.
# The real VM launcher is never invoked.
mkdir -p "$T/mock-bin" "$T/rootfs/etc" "$T/rootfs/usr/local/bin"
cat > "$T/mock-bin/rc-update" <<'EOF_MOCK'
#!/bin/sh
exit 0
EOF_MOCK
cat > "$T/mock-bin/rc-service" <<'EOF_MOCK'
#!/bin/sh
case $2 in
  status) test -f "$MOCK_SERVICE_RUNNING" ;;
  start|restart)
    printf '%s\n' "$2" >> "$MOCK_SERVICE_ACTIONS"
    : > "$MOCK_SERVICE_RUNNING"
    ;;
  *) exit 20;;
esac
EOF_MOCK
cat > "$T/mock-bin/podman" <<'EOF_MOCK'
#!/bin/sh
case "$1 $2" in
  'ps -a')
    if [ -n "${MOCK_CONTAINERS:-}" ]; then printf '%s\n' "$MOCK_CONTAINERS"; fi ;;
  'container inspect') printf '%s\n' "${MOCK_CONTAINER_RUNTIME:-crun}" ;;
  'info --format')
    sed -n 's/^runtime = "\([^"]*\)"$/\1/p' "$MOCK_POLICY_FILE" ;;
  *) printf 'Unexpected podman mock call: %s\n' "$*" >&2; exit 45;;
esac
EOF_MOCK
cat > "$T/mock-bin/sha256sum" <<'EOF_MOCK'
#!/bin/sh
shasum -a 256 "$@"
EOF_MOCK
chmod +x "$T/mock-bin/"*
MOCK_SERVICE_ACTIONS=$T/service-actions
MOCK_SERVICE_RUNNING=$T/service-running
MOCK_POLICY_FILE=$T/rootfs/etc/containers/containers.conf.d/99-firebreak-runsc.conf
export MOCK_SERVICE_ACTIONS MOCK_SERVICE_RUNNING MOCK_POLICY_FILE
PATH="$T/mock-bin:$PATH"; export PATH
# Script generator emits POSIX shell, and we only execute its policy preamble.
sed '/^# The project is intentionally mounted read-only/,$d' .devcontainer/firebreak/seeds/sbx/reconcile.sh |
  sed -e "s|/etc/containers/|$T/rootfs/etc/containers/|g" \
      -e "s|/etc/firebreak|$T/rootfs/etc/firebreak|g" \
      -e "s|/usr/local/bin/|$T/rootfs/usr/local/bin/|g" > "$T/mock-guest-policy.sh"
sh -n "$T/mock-guest-policy.sh" || fail 'generated guest policy syntax failure'
sh "$T/mock-guest-policy.sh" unsafe crun
[ "$(grep -c '^start$' "$MOCK_SERVICE_ACTIONS")" -eq 1 ] || fail 'Podman service not started'
grep -Fxq 'runtime = "crun"' "$MOCK_POLICY_FILE" || fail 'crun not applied'
grep -Fxq 'pull_policy = "missing"' "$MOCK_POLICY_FILE" || fail 'unsafe pull policy not applied'
sh "$T/mock-guest-policy.sh" unsafe crun
[ "$(wc -l < "$MOCK_SERVICE_ACTIONS" | tr -d ' ')" -eq 1 ] || fail 'unnecessary Podman restart for same policy'
sh "$T/mock-guest-policy.sh" offline runsc
[ "$(grep -c '^restart$' "$MOCK_SERVICE_ACTIONS")" -eq 1 ] || fail 'Podman not restarted after runtime change'
grep -Fxq 'runtime = "runsc"' "$MOCK_POLICY_FILE" || fail 'runsc not applied'
grep -Fxq 'pull_policy = "never"' "$MOCK_POLICY_FILE" || fail 'work pull policy not applied'
MOCK_CONTAINERS=old-container MOCK_CONTAINER_RUNTIME=crun
export MOCK_CONTAINERS MOCK_CONTAINER_RUNTIME
if sh "$T/mock-guest-policy.sh" models runsc > "$T/work.out" 2> "$T/work.err"; then
  fail 'work mode accepted an existing crun container'
fi
grep -Fq 'expected runsc' "$T/work.err" || fail 'missing actionable runtime mismatch error'
printf '%s\n' 'PASS: mocked OCI runtime policy transitions'
