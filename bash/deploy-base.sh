#!/usr/bin/env bash

set -euo pipefail

DEFAULT_SENDER="0x8842fe65A7Db9BB5De6d50e49aF19496da09F9b5"

usage() {
    echo "Usage: $0 <staging|production> [additional forge args]" >&2
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

ENVIRONMENT="$1"
shift || true

case "$ENVIRONMENT" in
    staging)
        DEPLOY_SCRIPT="script/Deployments_Base_Staging.s.sol"
        ;;
    production|prod)
        DEPLOY_SCRIPT="script/Deployments_Base_Production.s.sol"
        ;;
    *)
        echo "Unsupported environment: $ENVIRONMENT" >&2
        usage
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

if [[ ! -f .env ]]; then
    echo ".env file is required but not found in the project root." >&2
    exit 1
fi

set -o allexport
# shellcheck disable=SC1091
source .env
set +o allexport

if [[ -z "${BASE_RPC_URL:-}" ]]; then
    echo "BASE_RPC_URL must be set in the .env file." >&2
    exit 1
fi

SENDER="${BASE_DEPLOY_SENDER:-$DEFAULT_SENDER}"

if [[ -z "$SENDER" ]]; then
    echo "Deployment sender address must be provided via BASE_DEPLOY_SENDER or DEFAULT_SENDER." >&2
    exit 1
fi

DEPLOYMENT_CONTEXT=8453 forge script "$DEPLOY_SCRIPT" \
    --rpc-url "$BASE_RPC_URL" \
    --broadcast \
    --sender "$SENDER" \
    --account deployer \
    -vvv \
    --verify \
    "$@"

./forge-deploy sync
