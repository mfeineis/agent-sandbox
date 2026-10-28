#!/bin/sh
# F and G regression checks, no QEMU, root privileges or Docker service.
set -eu
BASE=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d)
trap 'rm -rf "$T"' 0
fail() { echo "FAIL buildx/boot: $*" >&2; exit 1; }
mkdir -p "$T/bin" "$T/guest/etc/default" "$T/guest/boot/grub" "$T/docker"
cat > "$T/bin/docker" <<'MOCK'
#!/bin/sh
case "$1 $2" in
  'buildx inspect')
    [ -f "$MOCK_BUILDER_EXISTS" ] || exit 1
    printf '%s\n' 'Name: firebreak-sbx-unsafe' 'Driver: docker-container'
    ;;
  'buildx create')
    printf '%s\n' "$*" >> "$MOCK_DOCKER_CALLS"
    : > "$MOCK_BUILDER_EXISTS"
    ;;
  'buildx rm')
    printf '%s\n' "$*" >> "$MOCK_DOCKER_CALLS"
    rm -f "$MOCK_BUILDER_EXISTS"
    ;;
  *) echo "Unexpected docker $*" >&2; exit 4;;
esac
MOCK
chmod +x "$T/bin/docker"
MOCK_BUILDER_EXISTS=$T/docker/builder-created
MOCK_DOCKER_CALLS=$T/docker/log
export MOCK_BUILDER_EXISTS MOCK_DOCKER_CALLS
PATH=$T/bin:$BASE/tests/fixtures:$PATH; export PATH
# Extract functions from the single-file script without running main() or requiring macOS.
{
  printf '%s\n' 'say() { printf "%s\\n" "$*" >&2; }' 'die() { echo "$*" >&2; exit 1; }'
  for fn in firebreak_builder_name prepare_firebreak_builder cleanup_firebreak_builder; do
    awk -v fn="$fn" '$0 ~ "^" fn "\\(\\)" {emit=1} emit{print} emit && /^}$/ {exit}' "$BASE/firebreak"
  done
} > "$T/functions.sh"
# shellcheck disable=SC1090
. "$T/functions.sh"
NAME=sbx
cli_mode=unsafe
CURRENT_PROFILE=unsafe
STORE=$T/docker
VM_SOCKET=$T/fake-socket
: > "$VM_SOCKET"
prepare_firebreak_builder
[ "$BUILDX_BUILDER" = firebreak-sbx-unsafe ] || fail 'wrong builder name'
grep -Fq -e '--driver-opt default-load=true' "$MOCK_DOCKER_CALLS" || fail 'missing default image loading'
prepare_firebreak_builder
[ "$(wc -l < "$MOCK_DOCKER_CALLS" | tr -d ' ')" -eq 1 ] || fail 'builder recreated unnecessarily'
# In this mocked test, replace the socket existence predicate to support a regular file.
sed 's/\[ -S "${VM_SOCKET:-\/nonexistent}" \]/[ -e "${VM_SOCKET:-\/nonexistent}" ]/' "$T/functions.sh" > "$T/functions-test.sh"
. "$T/functions-test.sh"
cleanup_firebreak_builder
grep -Fxq 'buildx rm --keep-state firebreak-sbx-unsafe' "$MOCK_DOCKER_CALLS" || fail 'did not keep cache when removing builder'
[ ! -e "$MOCK_BUILDER_EXISTS" ] || fail 'builder not removed'
CURRENT_PROFILE=offline
: > "$MOCK_BUILDER_EXISTS"
cleanup_firebreak_builder
[ -e "$MOCK_BUILDER_EXISTS" ] || fail 'work mode cleaned unsafe builder unexpectedly'
# Build validation should reject invalid boot timeout and accept 0.
cd "$T"
"$BASE/firebreak" config init >/dev/null
printf '%s\n' boot_timeout=31 >> firebreak.conf
if "$BASE/firebreak" sbx __test-render >/dev/null 2>&1; then fail 'accepted timeout >30'; fi
sed '/^boot_timeout=31$/d' firebreak.conf > firebreak.conf.new && mv firebreak.conf.new firebreak.conf
"$BASE/firebreak" sbx __test-render >/dev/null
SEED=$T/.devcontainer/firebreak/seeds/sbx/reconcile.sh
sh -n "$SEED" || fail 'rendered reconcile is not POSIX shell'
# Extract just the GRUB snippet and redirect guest absolute paths into our fixture.
awk '/^# Only touch GRUB when the guest actually has a GRUB installation/{emit=1} emit && /^EOF_BOOT$/{exit} emit{print}' "$SEED" | \
  sed -e "s|/etc/default/grub|$T/guest/etc/default/grub|g" \
      -e "s|/boot/grub/grub.cfg|$T/guest/boot/grub/grub.cfg|g" > "$T/boot-snippet.sh"
cat > "$T/bin/grub-mkconfig" <<'MOCK'
#!/bin/sh
[ "$1" = -o ] || exit 2
[ "${MOCK_GRUB_FAIL:-0}" = 0 ] || exit 9
printf '%s\n' "set timeout=$(sed -n 's/^GRUB_TIMEOUT=//p' "$MOCK_GRUB_DEFAULTS")" > "$2"
printf x >> "$MOCK_GRUB_COUNT"
MOCK
chmod +x "$T/bin/grub-mkconfig"
MOCK_GRUB_DEFAULTS=$T/guest/etc/default/grub
MOCK_GRUB_COUNT=$T/grub.count
export MOCK_GRUB_DEFAULTS MOCK_GRUB_COUNT
printf '%s\n' GRUB_TIMEOUT=10 GRUB_DEFAULT=0 > "$MOCK_GRUB_DEFAULTS"
printf 'set timeout=10\n' > "$T/guest/boot/grub/grub.cfg"
boot_timeout=0
export boot_timeout
sh "$T/boot-snippet.sh"
grep -Fxq GRUB_TIMEOUT=0 "$MOCK_GRUB_DEFAULTS" || fail 'GRUB_TIMEOUT not updated'
grep -Fxq 'set timeout=0' "$T/guest/boot/grub/grub.cfg" || fail 'grub.cfg not regenerated'
sh "$T/boot-snippet.sh"
[ "$(wc -c < "$MOCK_GRUB_COUNT" | tr -d ' ')" -eq 1 ] || fail 'unnecessary grub regeneration'
boot_timeout=5 MOCK_GRUB_FAIL=1; export boot_timeout MOCK_GRUB_FAIL
if sh "$T/boot-snippet.sh" >/dev/null 2>&1; then fail 'accepted failed grub-mkconfig'; fi
grep -Fxq GRUB_TIMEOUT=0 "$MOCK_GRUB_DEFAULTS" || fail 'failed grub update did not roll back'
grep -Fxq 'set timeout=0' "$T/guest/boot/grub/grub.cfg" || fail 'failed grub update damaged boot config'
echo 'PASS: Buildx lifecycle and GRUB timeout tests'
