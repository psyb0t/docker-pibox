#!/usr/bin/env bash
set -euo pipefail

PIBOX_INSTALLED_IMAGE="psyb0t/pibox:latest"

log() {
    local level="$1"
    shift
    printf '{"time":"%s","level":"%s","file":"wrapper.sh","line":%d,"func":"%s","msg":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
        "$level" \
        "${BASH_LINENO[0]}" \
        "${FUNCNAME[1]:-main}" \
        "$*" >&2
}

case "${PIBOX_FULL:-}" in
    "") PIBOX_IMAGE="${PIBOX_IMAGE:-$PIBOX_INSTALLED_IMAGE}" ;;
    0) PIBOX_IMAGE="${PIBOX_IMAGE:-psyb0t/pibox:latest}" ;;
    1) PIBOX_IMAGE="${PIBOX_IMAGE:-psyb0t/pibox:latest-full}" ;;
    *)
        log ERROR "PIBOX_FULL must be 0 or 1"
        exit 1
        ;;
esac

case "${PIBOX_DETACH:-0}" in
    0 | 1) ;;
    *)
        log ERROR "PIBOX_DETACH must be 0 or 1"
        exit 1
        ;;
esac

case "${AICODEBOX_LAUNCH_CONTEXT_VERSION:-}" in
    "" | 1) ;;
    *)
        log ERROR "unsupported AICODEBOX_LAUNCH_CONTEXT_VERSION"
        exit 1
        ;;
esac

readonly CONTAINER_PI_HOME="/home/aicode/.pi"
readonly CONTAINER_STATE_HOME="/home/aicode/.aicodebox"

host_home="${AICODEBOX_HOST_HOME:-$HOME}"
host_workspace="$PWD"
pi_home="${PIBOX_DATA_DIR:-${AICODEBOX_HOST_PI_HOME:-$host_home/.pi}}"
state_home="${PIBOX_STATE_DIR:-$host_home/.aicodebox}"
ssh_home="${PIBOX_SSH_DIR:-$host_home/.ssh/pibox}"
wrapper_dir="${AICODEBOX_HOST_WRAPPER_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
container_name="${PIBOX_CONTAINER_NAME:-pibox-$(printf '%s' "$host_workspace" | sed 's/[^A-Za-z0-9_.-]/_/g')}"
max_mem="${PIBOX_MAX_MEM:-10g}"

if [[ -z "${AICODEBOX_LAUNCH_CONTEXT_VERSION:-}" ]]; then
    mkdir -p "$pi_home" "$state_home" "$ssh_home"
fi

docker_args=(
    --network host
    --memory "$max_mem"
    --memory-swap "$max_mem"
    -e "PIBOX_WORKSPACE=$host_workspace"
    -e "PIBOX_CONTAINER_NAME=$container_name"
    -e "AICODEBOX_LAUNCH_CONTEXT_VERSION=1"
    -e "AICODEBOX_HOST_HOME=$host_home"
    -e "AICODEBOX_HOST_WORKSPACE=$host_workspace"
    -e "AICODEBOX_HOST_CODEX_HOME=${AICODEBOX_HOST_CODEX_HOME:-$host_home/.codex}"
    -e "AICODEBOX_HOST_CLAUDE_HOME=${AICODEBOX_HOST_CLAUDE_HOME:-$host_home/.claude}"
    -e "AICODEBOX_HOST_PI_HOME=$pi_home"
    -e "AICODEBOX_HOST_WRAPPER_DIR=$wrapper_dir"
    -e "AICODEBOX_HOST_CODEX_WRAPPER=${AICODEBOX_HOST_CODEX_WRAPPER:-$wrapper_dir/codexbox}"
    -e "AICODEBOX_HOST_CLAUDE_WRAPPER=${AICODEBOX_HOST_CLAUDE_WRAPPER:-$wrapper_dir/claudebox}"
    -e "AICODEBOX_HOST_PI_WRAPPER=${AICODEBOX_HOST_PI_WRAPPER:-$wrapper_dir/pibox}"
    -v "$ssh_home:/home/aicode/.ssh"
    -v "$pi_home:$CONTAINER_PI_HOME"
    -v "$state_home:$CONTAINER_STATE_HOME"
    -v "$host_workspace:$host_workspace"
    -v /var/run/docker.sock:/var/run/docker.sock
)

for wrapper_name in codexbox claudebox pibox; do
    case "$wrapper_name" in
        codexbox) wrapper_path="${AICODEBOX_HOST_CODEX_WRAPPER:-$wrapper_dir/codexbox}" ;;
        claudebox) wrapper_path="${AICODEBOX_HOST_CLAUDE_WRAPPER:-$wrapper_dir/claudebox}" ;;
        pibox) wrapper_path="${AICODEBOX_HOST_PI_WRAPPER:-$wrapper_dir/pibox}" ;;
    esac
    [[ -f "$wrapper_path" ]] || continue
    docker_args+=(
        --mount "type=bind,src=$wrapper_path,dst=/usr/local/bin/$wrapper_name,readonly"
    )
done

while IFS='=' read -r name _value; do
    case "$name" in
        PIBOX_ENV_*)
            stripped="${name#PIBOX_ENV_}"
            docker_args+=(-e "$stripped=$_value")
            continue
            ;;
        PIBOX_IMAGE | PIBOX_FULL | PIBOX_DATA_DIR | PIBOX_STATE_DIR | PIBOX_SSH_DIR | \
            PIBOX_MAX_MEM | PIBOX_CONTAINER_NAME | PIBOX_INSTALL_DIR | PIBOX_BIN_NAME | \
            PIBOX_SRC_LOCAL | PIBOX_MANAGED_INSTALL | PIBOX_INSTALL_REF | PIBOX_DETACH)
            continue
            ;;
    esac
    docker_args+=(-e "$name")
done < <(env | grep -E '^PIBOX_[A-Za-z0-9_]+=' || true)

while IFS='=' read -r name _value; do
    stripped="${name#AICODEBOX_ENV_}"
    docker_args+=(-e "$stripped=$_value")
done < <(env | grep -E '^AICODEBOX_ENV_[A-Za-z0-9_]+=' || true)

for mount_prefix in AICODEBOX PIBOX; do
    while IFS='=' read -r _name value; do
        case "$value" in
            *:*) docker_args+=(-v "$value") ;;
            *) docker_args+=(-v "$value:$value") ;;
        esac
    done < <(env | grep -E "^${mount_prefix}_MOUNT_[A-Za-z0-9_]+=" || true)
done

if [[ -t 0 && -t 1 ]]; then
    tty_args=(-it)
else
    tty_args=(-i)
fi

if [[ "${PIBOX_DETACH:-0}" == "1" ]]; then
    exec docker run -d --name "$container_name" "${docker_args[@]}" "$PIBOX_IMAGE" "$@"
fi

exec docker run --rm "${tty_args[@]}" --name "$container_name" \
    "${docker_args[@]}" "$PIBOX_IMAGE" "$@"
