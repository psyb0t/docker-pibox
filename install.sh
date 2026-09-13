#!/usr/bin/env bash
set -euo pipefail

readonly PIBOX_RELEASE_REF="v0.18.0"
readonly WRAPPER_URL="https://raw.githubusercontent.com/psyb0t/docker-pibox/${PIBOX_INSTALL_REF:-$PIBOX_RELEASE_REF}/wrapper.sh"

log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","file":"install.sh","line":%d,"func":"%s","msg":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        "$level" \
        "${BASH_LINENO[0]}" \
        "${FUNCNAME[1]:-main}" \
        "$*" >&2
}

case "${PIBOX_FULL:-0}" in
    0) readonly IMAGE="psyb0t/pibox:latest" ;;
    1) readonly IMAGE="psyb0t/pibox:latest-full" ;;
    *)
        log ERROR "PIBOX_FULL must be 0 or 1"
        exit 1
        ;;
esac

case "${PIBOX_SRC_LOCAL:-false}" in
    true) readonly SOURCE_LOCAL=true ;;
    false | "") readonly SOURCE_LOCAL=false ;;
    *)
        log ERROR "PIBOX_SRC_LOCAL must be true or false"
        exit 1
        ;;
esac

case "${AICODEBOX_MANAGED_INSTALL:-${PIBOX_MANAGED_INSTALL:-0}}" in
    0) readonly MANAGED_INSTALL=false ;;
    1) readonly MANAGED_INSTALL=true ;;
    *)
        log ERROR "AICODEBOX_MANAGED_INSTALL must be 0 or 1"
        exit 1
        ;;
esac

bin_name="${1:-${PIBOX_BIN_NAME:-pibox}}"
install_dir="${PIBOX_INSTALL_DIR:-/usr/local/bin}"
bin_path="$install_dir/$bin_name"
host_home="${AICODEBOX_HOST_HOME:-$HOME}"

command -v docker >/dev/null 2>&1 || {
    log ERROR "Docker is not installed"
    exit 1
}

mkdir -p "$host_home/.pi" "$host_home/.aicodebox" "$host_home/.ssh/pibox"
if [[ ! -f "$host_home/.ssh/pibox/id_ed25519" ]]; then
    ssh-keygen -t ed25519 -C "pibox" -f "$host_home/.ssh/pibox/id_ed25519" -N ""
elif [[ "$MANAGED_INSTALL" == false ]]; then
    log INFO "keeping existing SSH key path=$host_home/.ssh/pibox/id_ed25519"
fi

if [[ "$SOURCE_LOCAL" == true ]]; then
    docker image inspect "$IMAGE" >/dev/null 2>&1 || {
        log ERROR "local image not found image=$IMAGE"
        exit 1
    }
else
    docker pull "$IMAGE"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd)"
wrapper_tmp="$(mktemp /tmp/pibox-wrapper-XXXXXX.sh)"
baked_tmp="$(mktemp /tmp/pibox-wrapper-baked-XXXXXX.sh)"
trap 'rm -f "$wrapper_tmp" "$baked_tmp"' EXIT

if [[ -f "$script_dir/wrapper.sh" ]]; then
    cp "$script_dir/wrapper.sh" "$wrapper_tmp"
else
    curl -fsSL "$WRAPPER_URL" -o "$wrapper_tmp"
fi

[[ -s "$wrapper_tmp" ]] || {
    log ERROR "wrapper is empty"
    exit 1
}
grep -q '^PIBOX_INSTALLED_IMAGE=' "$wrapper_tmp" || {
    log ERROR "wrapper has no PIBOX_INSTALLED_IMAGE declaration"
    exit 1
}
sed "s|^PIBOX_INSTALLED_IMAGE=.*|PIBOX_INSTALLED_IMAGE=\"$IMAGE\"|" \
    "$wrapper_tmp" >"$baked_tmp"

sudo install -d -m 755 "$install_dir"
sudo install -m 755 "$baked_tmp" "$bin_path"
printf 'Installed %s at %s using %s\n' "$bin_name" "$bin_path" "$IMAGE"
