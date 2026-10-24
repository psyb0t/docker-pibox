#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
# shellcheck source=test-common.sh
source "$REPO/tests/test-common.sh"
trap 'log ERROR "Provider stdout regression failed at line $LINENO"' ERR
readonly LOG_FILE="${LOG_FILE:-/tmp/pibox-action-provider-output.log}"
exec > >(tee -a "$LOG_FILE") 2>&1
output="$(docker run --rm --name "pibox-action-provider-output-$$" --network none \
    --entrypoint bash \
    --mount "type=bind,src=$REPO/pibox/scripts/setup-provider-env.sh,dst=/provider.sh,readonly" \
    -e PIBOX_PROVIDER_API_KEY=EXAMPLE-DO-NOT-USE \
    -e PIBOX_PROVIDER_BASE_URL=https://example.invalid/v1 \
    -e PIBOX_PROVIDER_MODEL=example-model psyb0t/aicodebox:latest /provider.sh)"
[[ -z "$output" ]] || fail "Provider setup polluted native stdout"
log INFO "Provider setup leaves stdout clean"
