#!/bin/sh
# Test the offline console rescue script with a fake guest filesystem and sshd.
# Root privileges, QEMU, SSH service, cloud-init, and network are NOT required.
set -eu
HERE=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
FB=$HERE/firebreak
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
fail() { printf 'FAIL: SSH recovery: %s\n' "$*" >&2; exit 1; }
export PATH="$HERE/tests/fixtures:$PATH"
cd "$T"
"$FB" config init >/dev/null
"$FB" demo __test-render >/dev/null
seed=$T/.devcontainer/firebreak/seeds/demo
mkdir -p "$T/guest-root" "$T/guest-etc/ssh" "$T/guest-bin"
printf '%s\n' 'PermitRootLogin no' 'PasswordAuthentication yes' > "$T/guest-etc/ssh/sshd_config"
cat > "$T/guest-bin/sshd" <<'EOF_SSHD'
#!/bin/sh
case $1 in
  -t)
    [ "${2:-}" = -f ] && config=$3 || config=$MOCK_GUEST_CONF
    [ "$(sed -n '1p' "$config")" = "Include $MOCK_GUEST_DIR/*.conf" ] || exit 42
    ;;
  -T)
    printf '%s\n' 'permitrootlogin prohibit-password' 'passwordauthentication no' \
      'pubkeyauthentication yes' 'authorizedkeysfile .ssh/authorized_keys'
    ;;
  *) exit 43;;
esac
EOF_SSHD
cat > "$T/guest-bin/rc-service" <<'EOF_RC'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_GUEST_ACTIONS"
EOF_RC
chmod +x "$T/guest-bin/sshd" "$T/guest-bin/rc-service"
MOCK_GUEST_CONF=$T/guest-etc/ssh/sshd_config
MOCK_GUEST_DIR=$T/guest-etc/ssh/sshd_config.d
MOCK_GUEST_ACTIONS=$T/actions
export MOCK_GUEST_CONF MOCK_GUEST_DIR MOCK_GUEST_ACTIONS
# Translate only fixed guest paths; no execution or mutation of host system SSH.
sed -e "s|/root|$T/guest-root|g" \
    -e "s|/etc/ssh|$T/guest-etc/ssh|g" \
    -e "s|/usr/sbin/sshd|$T/guest-bin/sshd|g" \
    "$seed/ssh-recovery.sh" > "$T/rescue-test.sh"
/bin/sh -n "$T/rescue-test.sh" || fail 'generated script invalid'
PATH="$T/guest-bin:$PATH" /bin/sh "$T/rescue-test.sh" >/dev/null || fail 'recovery did not run'
[ "$(sed -n '1p' "$MOCK_GUEST_CONF")" = "Include $MOCK_GUEST_DIR/*.conf" ] || fail 'include was not prepended'
grep -Fqx 'PermitRootLogin no' "$T/guest-etc/ssh/sshd_config.firebreak-backup" || fail 'old policy not backed up'
grep -Fqx 'PermitRootLogin prohibit-password' "$MOCK_GUEST_DIR/00-firebreak.conf" || fail 'new policy missing'
grep -Fqx 'PasswordAuthentication no' "$MOCK_GUEST_DIR/00-firebreak.conf" || fail 'password auth not disabled'
grep -Fqx "$(cat "$T/.devcontainer/firebreak/secrets/demo/id_ed25519_client.pub")" "$T/guest-root/.ssh/authorized_keys" || fail 'host key not installed'
grep -Fqx 'sshd restart' "$T/actions" || fail 'sshd not restarted'
# Running recovery twice must not append duplicate keys or include directives.
PATH="$T/guest-bin:$PATH" /bin/sh "$T/rescue-test.sh" >/dev/null || fail 'repeat recovery failed'
[ "$(grep -Fc 'Include ' "$MOCK_GUEST_CONF")" -eq 1 ] || fail 'duplicate include'
[ "$(wc -l < "$T/guest-root/.ssh/authorized_keys" | tr -d ' ')" -eq 1 ] || fail 'duplicate host key'
printf '%s\n' 'PASS: offline SSH recovery integration (mocked guest)'
