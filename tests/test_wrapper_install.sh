#!/usr/bin/env bash
set -euo pipefail

for launch_var in "${!AICODEBOX_HOST_@}"; do
    unset "$launch_var"
done
unset AICODEBOX_LAUNCH_CONTEXT_VERSION

unset AICODEBOX_HOST_HOME PIBOX_INSTALL_REF PIBOX_FULL PIBOX_IMAGE

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT
fake_bin="$tmp_root/bin"
mkdir -p "$fake_bin" "$tmp_root/home" "$tmp_root/install" "$tmp_root/wrappers" "$tmp_root/remote"

cat >"$fake_bin/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$tmp_root/docker.log"
exit 0
EOF
cat >"$fake_bin/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
cat >"$fake_bin/curl" <<EOF
#!/usr/bin/env bash
[[ "\${TEST_CURL_FAIL:-0}" == 1 ]] && exit 7
printf '%s\n' "\$*" >>"$tmp_root/curl.log"
while [[ "\$#" -gt 0 ]]; do
	if [[ "\$1" == -o ]]; then
		shift
		cp "$repo/wrapper.sh" "\$1"
		exit 0
	fi
	shift
done
exit 1
EOF
cat >"$fake_bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == -f ]]; then
        shift
        mkdir -p "$(dirname "$1")"
        : >"$1"
        : >"$1.pub"
        exit 0
    fi
    shift
done
EOF
chmod +x "$fake_bin/docker" "$fake_bin/sudo" "$fake_bin/ssh-keygen" "$fake_bin/curl"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

: >"$tmp_root/docker.log"
(
    cd "$tmp_root"
    HOME="$tmp_root/home" PATH="$fake_bin:$PATH" \
        PIBOX_DATA_DIR="$tmp_root/home/pi" \
        PIBOX_STATE_DIR="$tmp_root/home/state" \
        PIBOX_SSH_DIR="$tmp_root/home/ssh" \
        bash "$repo/wrapper.sh" -p test >/dev/null
)
standalone="$(cat "$tmp_root/docker.log")"
[[ "$standalone" == *"psyb0t/pibox:latest -p test"* ]] || fail "standalone image or arguments"
[[ "$standalone" == *"$tmp_root:$tmp_root"* ]] || fail "standalone workspace mount"

for name in codexbox claudebox pibox; do
    printf '#!/bin/sh\n' >"$tmp_root/wrappers/$name"
done
: >"$tmp_root/docker.log"
(
    cd "$tmp_root"
    HOME=/home/aicode PATH="$fake_bin:$PATH" \
        AICODEBOX_LAUNCH_CONTEXT_VERSION=1 \
        AICODEBOX_HOST_HOME="$tmp_root/home" \
        AICODEBOX_HOST_CODEX_HOME="$tmp_root/home/codex" \
        AICODEBOX_HOST_CLAUDE_HOME="$tmp_root/home/claude" \
        AICODEBOX_HOST_PI_HOME="$tmp_root/home/pi" \
        AICODEBOX_HOST_WRAPPER_DIR="$tmp_root/wrappers" \
        PIBOX_GIT_NAME="Example User" \
        PIBOX_GIT_EMAIL="example@example.invalid" \
        PIBOX_ENV_AGENT_VALUE=visible \
        AICODEBOX_ENV_SHARED_VALUE=shared \
        bash "$repo/wrapper.sh" -p nested >/dev/null
)
nested="$(cat "$tmp_root/docker.log")"
for name in codexbox claudebox pibox; do
    [[ "$nested" == *"dst=/usr/local/bin/$name,readonly"* ]] || fail "nested $name wrapper mount"
done
[[ "$nested" == *"AICODEBOX_HOST_HOME=$tmp_root/home"* ]] || fail "nested host context"
[[ "$nested" == *"AGENT_VALUE=visible"* ]] || fail "pibox environment"
[[ "$nested" == *"SHARED_VALUE=shared"* ]] || fail "common environment"
[[ "$nested" == *"PIBOX_GIT_NAME"* ]] || fail "missing Git name"
[[ "$nested" == *"PIBOX_GIT_EMAIL"* ]] || fail "missing Git email"

HOME="$tmp_root/home" PATH="$fake_bin:$PATH" PIBOX_SRC_LOCAL=true \
    PIBOX_INSTALL_DIR="$tmp_root/install" AICODEBOX_MANAGED_INSTALL=1 \
    bash "$repo/install.sh" >/dev/null
[[ -x "$tmp_root/install/pibox" ]] || fail "managed installer wrapper"
[[ -f "$tmp_root/home/.ssh/pibox/id_ed25519" ]] || fail "managed installer SSH key"

for full_value in 0 1; do
    expected_image=psyb0t/pibox:latest
    [[ "$full_value" == 1 ]] && expected_image=psyb0t/pibox:latest-full
    : >"$tmp_root/docker.log"
    HOME="$tmp_root/home" PATH="$fake_bin:$PATH" PIBOX_FULL="$full_value" \
        PIBOX_INSTALL_DIR="$tmp_root/install" AICODEBOX_MANAGED_INSTALL=1 \
        bash "$repo/install.sh" >/dev/null
    [[ "$(cat "$tmp_root/docker.log")" == *"pull $expected_image"* ]] || fail "installer selected wrong variant"
    : >"$tmp_root/docker.log"
    HOME="$tmp_root/home" PATH="$fake_bin:$PATH" env -u PIBOX_FULL \
        bash "$tmp_root/install/pibox" -p persisted >/dev/null
    [[ "$(cat "$tmp_root/docker.log")" == *"$expected_image -p persisted"* ]] || fail "installed variant was not preserved"
done
: >"$tmp_root/docker.log"
HOME="$tmp_root/home" PATH="$fake_bin:$PATH" PIBOX_FULL=0 \
    bash "$tmp_root/install/pibox" -p minimal >/dev/null
[[ "$(cat "$tmp_root/docker.log")" == *"psyb0t/pibox:latest -p minimal"* ]] || fail "runtime zero did not force minimal"
for command_path in "$repo/install.sh" "$repo/wrapper.sh"; do
    if PIBOX_FULL=2 bash "$command_path" >/dev/null 2>&1; then
        fail "invalid full selector was accepted"
    fi
done

cp "$repo/install.sh" "$tmp_root/remote/install.sh"
HOME="$tmp_root/home" PATH="$fake_bin:$PATH" \
    PIBOX_INSTALL_DIR="$tmp_root/install" PIBOX_BIN_NAME=pibox-remote \
    AICODEBOX_MANAGED_INSTALL=1 bash "$tmp_root/remote/install.sh" </dev/null >/dev/null
[[ -x "$tmp_root/install/pibox-remote" ]] || fail "remote managed installer wrapper"
curl_call="$(cat "$tmp_root/curl.log")"
expected_ref="$(make --no-print-directory -s -C "${repo}" version)"
[[ "$curl_call" == *"/$expected_ref/wrapper.sh"* ]] || fail "wrapper download is not release-pinned"

PIBOX_INSTALL_REF=reviewed-ref HOME="$tmp_root/home" PATH="$fake_bin:$PATH" \
    PIBOX_INSTALL_DIR="$tmp_root/install" \
    AICODEBOX_MANAGED_INSTALL=1 bash "$tmp_root/remote/install.sh" </dev/null >/dev/null
[[ "$(tail -n 1 "$tmp_root/curl.log")" == *"/reviewed-ref/wrapper.sh"* ]] || fail "custom wrapper ref ignored"
if TEST_CURL_FAIL=1 HOME="$tmp_root/home" PATH="$fake_bin:$PATH" \
    PIBOX_INSTALL_DIR="$tmp_root/install" AICODEBOX_MANAGED_INSTALL=1 \
    bash "$tmp_root/remote/install.sh" </dev/null >/dev/null 2>&1; then
    fail "installer accepted failed wrapper download"
fi

if AICODEBOX_LAUNCH_CONTEXT_VERSION=2 bash "$repo/wrapper.sh" --version >/dev/null 2>&1; then
    fail "unsupported nested-launch context was accepted"
fi
if PIBOX_DETACH=2 bash "$repo/wrapper.sh" --version >/dev/null 2>&1; then
    fail "invalid detach value was accepted"
fi

printf 'wrapper and installer tests passed\n'
