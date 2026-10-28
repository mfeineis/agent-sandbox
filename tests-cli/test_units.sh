#!/bin/sh
# Portable no-root/no-QEMU unit tests; test key fixture is deliberately invalid.
set -eu
HERE=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
FB=$HERE/firebreak
FIXTURE=$HERE/tests/fixtures
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
PATH="$FIXTURE:$PATH"; export PATH
cd "$T"
fail() { echo "FAIL: $*" >&2; exit 1; }
contains() { grep -Fq -e "$2" "$1" || fail "Expected '$2' in $1"; }
no_contains() { grep -Fq -e "$2" "$1" && fail "Unexpected '$2' in $1" || :; }

/bin/sh -n "$FB" || fail 'syntax invalid'
"$FB" config init >/dev/null
[ -f "$T/firebreak.conf" ] || fail 'missing config'
contains .gitignore '.devcontainer/firebreak/'
"$FB" config init >/dev/null
[ "$(grep -Fxc '.devcontainer/firebreak/' .gitignore)" -eq 1 ] || fail 'duplicate gitignore'

"$FB" demo __test-render >/dev/null
seed=.devcontainer/firebreak/seeds/demo
secret=.devcontainer/firebreak/secrets/demo
[ -f "$seed/reconcile.sh" ] || fail 'missing reconcile script'
/bin/sh -n "$seed/reconcile.sh" || fail 'guest reconcile syntax invalid'
contains "$seed/user-data" 'passwd: "*"'
no_contains "$seed/user-data" 'lock_passwd: true'
contains "$seed/user-data" 'ssh_pwauth: false'
contains "$seed/user-data" 'emit_keys_to_console: false'
[ -f "$seed/ssh-recovery.sh" ] || fail 'missing offline SSH rescue script on NoCloud seed'
/bin/sh -n "$seed/ssh-recovery.sh" || fail 'SSH rescue syntax invalid'
contains "$seed/ssh-recovery.sh" 'Include /etc/ssh/sshd_config.d/*.conf'
contains "$seed/ssh-recovery.sh" 'PermitRootLogin prohibit-password'
contains "$seed/ssh-recovery.sh" 'PasswordAuthentication no'
contains "$seed/ssh-recovery.sh" 'sshd -T -C user=root,host=localhost,addr=10.0.2.2'
contains "$seed/ssh-recovery.sh" 'sshd -t -f "$tmp"'
contains "$seed/ssh-recovery.sh" 'chmod 700 /root /root/.ssh'
contains "$seed/ssh-recovery.sh" 'chmod 600 /root/.ssh/authorized_keys'
contains "$seed/ssh-recovery.sh" "$(cat "$secret/id_ed25519_client.pub")"
# The one-time cloud-init and offline console repair paths must stay identical.
sed -n '/^  - path: \/var\/lib\/cloud\/scripts\/per-instance\/10-firebreak-ssh.sh$/,/^  - path: \/var\/lib\/cloud\/scripts\/per-instance\/12-firebreak-gvisor.sh$/p' "$seed/user-data" |
  sed '1,3d;$d;s/^      //' > "$T/from-cloud-ssh.sh"
cmp -s "$seed/ssh-recovery.sh" "$T/from-cloud-ssh.sh" || fail 'cloud-init SSH bootstrap diverged from offline recovery script'
contains "$seed/user-data" 'chpasswd:'
contains "$seed/user-data" 'type: text'
contains "$seed/user-data" 'lock_passwd: false'
[ -f "$secret/console-password" ] || fail 'missing generated console recovery password'
[ "$(wc -c < "$secret/console-password" | tr -d ' ')" -eq 32 ] || fail 'unexpected console password length'
pass=$(cat "$secret/console-password")
contains "$seed/user-data" "password: \"$pass\""
shown=$("$FB" demo console-password 2>/dev/null)
[ "$shown" = "$pass" ] || fail 'console password display mismatch'
old_pass=$pass
no_contains "$seed/user-data" 'password: alpine'
contains "$seed/user-data" 'forgejo-openrc'
contains "$seed/user-data" 'gvisor.tar.bz2.sha512'
# One source of truth for first-boot installation and explicit repair.
[ -f "$seed/gvisor-install.sh" ] || fail 'missing standalone repair bootstrap'
/bin/sh -n "$seed/gvisor-install.sh" || fail 'gVisor repair script syntax invalid'
contains "$seed/gvisor-install.sh" 'curl --fail --show-error --silent --location'
contains "$seed/gvisor-install.sh" '--proxy "$PROXY"'
contains "$seed/gvisor-install.sh" 'sha512sum -c gvisor.tar.bz2.sha512'
no_contains "$seed/gvisor-install.sh" 'wget ${URL}'
sed -n '/^  - path: \/var\/lib\/cloud\/scripts\/per-instance\/12-firebreak-gvisor.sh$/,/^  - path: \/var\/lib\/cloud\/scripts\/per-instance\/20-firebreak-services.sh$/p' "$seed/user-data" |
  sed '1,3d;$d;s/^      //' > "$T/from-cloud-gvisor.sh"
cmp -s "$seed/gvisor-install.sh" "$T/from-cloud-gvisor.sh" || fail 'cloud-init gVisor bootstrap diverged from repair bootstrap'
contains "$seed/reconcile.sh" 'HTTP_PORT = 3001'
contains "$seed/reconcile.sh" '--overlay2=all:memory'

# Seeds are stable on repeated rendering.
old=$(shasum -a 256 "$seed/network-config" "$seed/user-data" "$seed/reconcile.sh")
"$FB" demo __test-render >/dev/null
new=$(shasum -a 256 "$seed/network-config" "$seed/user-data" "$seed/reconcile.sh")
[ "$old" = "$new" ] || fail 'render not idempotent'
[ "$(cat "$secret/console-password")" = "$old_pass" ] || fail 'console password rotated on rerender'
# Serial output can be reviewed independently of cloud-init and SSH.
mkdir -p .devcontainer/firebreak/tmp
printf '%s\n' 'cloud-init: deliberate boot failure' > .devcontainer/firebreak/tmp/demo.serial.log
"$FB" demo logs > "$T/collected-serial.log"
contains "$T/collected-serial.log" 'cloud-init: deliberate boot failure'

printf '%s\n' 'custom_future_key=please_keep_me' >>firebreak.conf
"$FB" config update >/dev/null
contains firebreak.conf 'custom_future_key=please_keep_me'
[ "$(grep -c '^forgejo_port=' firebreak.conf)" -eq 1 ] || fail 'config was unexpectedly replaced'

# Existing VM seed gets regenerated without touching its fake disk contents.
touch .devcontainer/firebreak/vm/demo.qcow2
sed 's/^forgejo_port=.*/forgejo_port=3333/' firebreak.conf >changed.conf
mv changed.conf firebreak.conf
"$FB" config update >/dev/null
contains "$seed/reconcile.sh" 'HTTP_PORT = 3333'
[ -f .devcontainer/firebreak/vm/demo.qcow2 ] || fail 'config update destroyed disk'
mkdir .devcontainer/firebreak/vm/demo.qcow2.lock
if "$FB" demo snapshot ready create >/dev/null 2>&1; then fail 'snapshot allowed while disk locked'; fi
if "$FB" config update >/dev/null 2>&1; then fail 'config update modified running seed'; fi
rmdir .devcontainer/firebreak/vm/demo.qcow2.lock

# Homebrew keeps Squid in sbin, not necessarily on PATH. A fake executable
# exercises full foreground startup without installing Squid or opening ports.
# Include a space in the Homebrew prefix to catch unsafe word splitting.
mkdir -p "$T/Homebrew installation/squid/sbin" "$T/no-squid-bin"
cat > "$T/Homebrew installation/squid/sbin/squid" <<'EOF_SQUID'
#!/bin/sh
case $1 in
  -k)
    [ "$2" = parse ] && [ "$3" = -f ] || exit 40
    grep -Fxq 'pid_filename none' "$4" || { echo 'old PID policy found' >&2; exit 41; }
    grep -Fxq 'cache_log squid.log' "$4" || { echo 'incorrect cache_log destination' >&2; exit 47; }
    grep -Fxq 'access_log stdio:access.log' "$4" || { echo 'incorrect access_log destination' >&2; exit 48; }
    # Verify that Squid is launched in its log directory, not the project root.
    [ -f ./squid.conf ] || { echo 'working directory is not proxy directory' >&2; exit 49; }
    if [ "${MOCK_SQUID_FAIL_PARSE:-}" = yes ]; then echo 'mock parser failure' >&2; exit 42; fi
    printf '%s\n' 'parsed' >> "${MOCK_SQUID_LOG:?}"
    ;;
  -N)
    [ "$2" = -f ] || exit 43
    if [ "${MOCK_SQUID_FAIL_START:-}" = yes ]; then echo 'mock foreground failure' >&2; exit 44; fi
    [ -f ./squid.conf ] || { echo 'foreground working directory is not proxy directory' >&2; exit 50; }
    : > ./squid.log
    : > ./access.log
    printf '%s\n' 'started' >> "${MOCK_SQUID_LOG:?}"
    trap 'exit 0' TERM INT
    while :; do sleep 1; done
    ;;
  *) exit 45;;
esac
EOF_SQUID
cat > "$T/no-squid-bin/brew" <<'EOF_BREW'
#!/bin/sh
[ "$1" = --prefix ] && [ "$2" = squid ] || exit 46
printf '%s\n' "${MOCK_BREW_PREFIX:?}"
EOF_BREW
chmod +x "$T/Homebrew installation/squid/sbin/squid" "$T/no-squid-bin/brew"
# Build a PATH with basic POSIX tools and our fake brew, but no squid command.
# This guarantees coverage of the Homebrew sbin fallback on both macOS and Linux.
for tool in mkdir cat sed chmod tail sleep dirname mktemp cmp mv rm grep; do
  ln -s "$(command -v "$tool")" "$T/no-squid-bin/$tool"
done
MOCK_BREW_PREFIX="$T/Homebrew installation/squid"
MOCK_SQUID_LOG="$T/squid-mock.log"
export MOCK_BREW_PREFIX MOCK_SQUID_LOG
PATH="$T/no-squid-bin" "$FB" config proxy-check >/dev/null 2>"$T/proxy-check.stderr" || fail 'Homebrew Squid proxy-check failed'
contains "$MOCK_SQUID_LOG" 'parsed'
contains "$MOCK_SQUID_LOG" 'started'
# Exercise --online without network: the mock curl verifies both the
# requested destination and the absence of any direct connection fallback.
cat > "$T/no-squid-bin/curl" <<'EOF_CURL_PROBE'
#!/bin/sh
saw_proxy=no saw_url=no saw_head=no
while [ "$#" -gt 0 ]; do
  case $1 in
    --proxy) [ "${2:-}" = 'http://127.0.0.1:3128' ] || exit 41; saw_proxy=yes; shift 2;;
    --head) saw_head=yes; shift;;
    'https://storage.googleapis.com/gvisor/releases/release/latest/aarch64/gvisor.tar.bz2') saw_url=yes; shift;;
    *) shift;;
  esac
done
[ "$saw_proxy" = yes ] && [ "$saw_head" = yes ] && [ "$saw_url" = yes ] || exit 42
if [ "${MOCK_CURL_FAIL:-}" = yes ]; then echo 'curl: (22) The requested URL returned error: 403' >&2; exit 22; fi
printf 'HTTP/1.1 200 Connection established\nHTTP/2 200\n'
EOF_CURL_PROBE
chmod +x "$T/no-squid-bin/curl"
PATH="$T/no-squid-bin" "$FB" config proxy-check --online >/dev/null 2> "$T/online.err" || fail 'mock Squid online check failed'
contains "$T/online.err" 'gVisor endpoint reachable through Squid'
MOCK_CURL_FAIL=yes PATH="$T/no-squid-bin" "$FB" config proxy-check --online > "$T/online.out" 2> "$T/online.err" && fail 'online probe ignored HTTP denial'
contains "$T/online.err" 'curl: (22)'
contains "$T/online.err" 'Setup proxy cannot reach gVisor'
[ -f .devcontainer/firebreak/proxy/squid.log ] || fail 'Squid did not open its relative cache log'
[ -f .devcontainer/firebreak/proxy/access.log ] || fail 'Squid did not open its relative access log'
contains .devcontainer/firebreak/proxy/squid.conf 'pid_filename none'
contains .devcontainer/firebreak/proxy/squid.conf 'cache_log squid.log'
contains .devcontainer/firebreak/proxy/squid.conf 'access_log stdio:access.log'
no_contains .devcontainer/firebreak/proxy/squid.conf 'cache_log "'
no_contains .devcontainer/firebreak/proxy/squid.conf 'access_log stdio:"'
no_contains .devcontainer/firebreak/proxy/squid.conf 'pid_filename "'
MOCK_SQUID_FAIL_PARSE=yes PATH="$T/no-squid-bin" "$FB" config proxy-check >"$T/proxy.out" 2>"$T/proxy.err" && fail 'accepted bad Squid config'
contains "$T/proxy.err" 'mock parser failure'
contains .devcontainer/firebreak/proxy/parse.log 'mock parser failure'
MOCK_SQUID_FAIL_START=yes PATH="$T/no-squid-bin" "$FB" config proxy-check >"$T/proxy.out" 2>"$T/proxy.err" && fail 'ignored Squid foreground failure'
contains "$T/proxy.err" 'mock foreground failure'
contains .devcontainer/firebreak/proxy/foreground.log 'mock foreground failure'
# Config remains parseable even when the Squid executable is not available.
# Users may intentionally override discovery with an absolute path.
FIREBREAK_SQUID="$T/Homebrew installation/squid/sbin/squid" PATH="$T/no-squid-bin" "$FB" config proxy-check >/dev/null 2>"$T/proxy-check.stderr" || fail 'explicit Squid path failed'

# Host project paths may contain spaces: relative logfile destinations still work.
mkdir -p "$T/project with spaces"
(
  cd "$T/project with spaces"
  "$FB" config init >/dev/null
  PATH="$T/no-squid-bin" "$FB" config proxy-check >/dev/null 2>"$T/proxy-spaces.stderr"
  [ -f .devcontainer/firebreak/proxy/squid.log ] || fail 'missing cache log for spaced project path'
  [ -f .devcontainer/firebreak/proxy/access.log ] || fail 'missing access log for spaced project path'
) || fail 'Squid proxy-check failed for project path containing spaces'

# A mocked HTTP image index demonstrates version/revision selection offline.
mkdir -p "$T/mockbin"
cat > "$T/mockbin/curl" <<'EOF_CURL'
#!/bin/sh
printf '%s\n' '<a href="generic_alpine-3.24.1-aarch64-uefi-cloudinit-r2.qcow2">r2</a>' \
  '<a href="generic_alpine-3.24.1-aarch64-uefi-cloudinit-r11.qcow2">r11</a>'
EOF_CURL
chmod +x "$T/mockbin/curl"
PATH="$T/mockbin:$PATH" "$FB" config update --refresh-image >/dev/null
contains firebreak.conf 'alpine_revision=r11'

for mode in unsafe offline models; do
  args=$("$FB" demo __test-net "$mode")
  printf '%s' "$args" | grep -Fq 'restrict=on' || fail "unrestricted QEMU profile $mode"
  case $mode in
    unsafe) printf '%s' "$args" | grep -Fq 'TCP:127.0.0.1:3128' || fail 'unsafe proxy missing';;
    models) printf '%s' "$args" | grep -Fq 'TCP:127.0.0.1:3129' || fail 'model proxy missing';;
    offline) printf '%s' "$args" | grep -Fq '10.0.2.100:3128' && fail 'offline profile has proxy' || :;;
  esac
done

# QEMU argument construction is exercised with a stub; no QEMU, privileges, or VM.
cat > "$T/mockbin/qemu-system-aarch64" <<'EOF_QEMU'
#!/bin/sh
printf '%s\n' "$@"
EOF_QEMU
chmod +x "$T/mockbin/qemu-system-aarch64"
PATH="$T/mockbin:$PATH" "$FB" demo __test-qemu log > "$T/qemu-log.args"
PATH="$T/mockbin:$PATH" "$FB" demo __test-qemu interactive > "$T/qemu-debug.args"
contains "$T/qemu-log.args" '-machine'
contains "$T/qemu-log.args" 'virt-11.0'
contains "$T/qemu-log.args" 'restrict=on'
contains "$T/qemu-log.args" 'file,id=fbserial,path='
contains "$T/qemu-debug.args" 'stdio,id=fbserial,signal=on,logfile='
contains "$T/qemu-debug.args" 'logappend=on'
contains "$T/qemu-debug.args" 'restrict=on'
no_contains "$T/qemu-log.args" 'stdio,id=fbserial'
# None of the debug machinery enables guest SSH password auth.
no_contains "$seed/user-data" 'ssh_pwauth: true'

# Guest defaults are immutable per sandbox even if global default changes.
printf '%s\n' persistent > "$secret/storage"
"$FB" demo __test-render >/dev/null
contains "$seed/reconcile.sh" '--overlay2=none'
contains "$seed/network-config" 'macaddress: "52:54:00:'

# Reject invalid identifiers and risky configuration rather than running a VM.
if "$FB" '../escape' __test-render >/dev/null 2>&1; then fail 'traversal accepted'; fi
if "$FB" '.hidden' __test-render >/dev/null 2>&1; then fail 'hidden identifier accepted'; fi
sed 's/^network_work=.*/network_work=unrestricted/' firebreak.conf > bad.conf
mv bad.conf firebreak.conf
if "$FB" demo __test-net offline >/dev/null 2>&1; then fail 'invalid networking config accepted'; fi

# Additional isolated lifecycle tests exercise historical cloud-init errors.
/bin/sh "$HERE/tests/test_lifecycle.sh"
echo 'PASS: shell unit tests'
