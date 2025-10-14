#!/usr/bin/env bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 --network <mainnet|base> [--env <staging|production>] [--skip-clean]

Deploy contracts to a local fork.

Options:
    --network <mainnet|base>         Specify the network (required)
    --env <staging|production>       Specify the environment (default: staging)
    --skip-clean                     Skip the fork cleanup step
    -h, --help                       Display this help message

Examples:
    $0 --network mainnet
    $0 --network base --env production
    $0 --network base --env staging --skip-clean

Prerequisites:
    - Anvil must be running on localhost:8545 with appropriate fork
    - Run './bash/start-fork.sh --network <network>' first to start the fork
EOF
    exit 1
}

# Parse arguments
NETWORK=""
ENVIRONMENT="staging"
SKIP_CLEAN=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --network)
            NETWORK="$2"
            shift 2
            ;;
        --env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --skip-clean)
            SKIP_CLEAN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate network parameter
if [[ -z "$NETWORK" ]]; then
    print_error "Network parameter is required"
    usage
fi

# Validate environment parameter
case "$ENVIRONMENT" in
    staging|production)
        ;;
    *)
        print_error "Invalid environment: $ENVIRONMENT. Must be 'staging' or 'production'"
        exit 1
        ;;
esac

# Map network to chain ID and deployment context
case "$NETWORK" in
    mainnet)
        CHAIN_ID="1"
        DEPLOYMENT_CONTEXT="1-fork"
        if [[ "$ENVIRONMENT" == "staging" ]]; then
            DEPLOY_SCRIPT="script/Deployments_Staging.s.sol"
        else
            DEPLOY_SCRIPT="script/Deployments_Production.s.sol"
        fi
        ;;
    base)
        CHAIN_ID="8453"
        DEPLOYMENT_CONTEXT="8453-fork"
        if [[ "$ENVIRONMENT" == "staging" ]]; then
            DEPLOY_SCRIPT="script/Deployments_Base_Staging.s.sol"
        else
            DEPLOY_SCRIPT="script/Deployments_Base_Production.s.sol"
        fi
        ;;
    *)
        print_error "Invalid network: $NETWORK. Must be 'mainnet' or 'base'"
        exit 1
        ;;
esac

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

print_info "Deploying to $NETWORK fork (chain ID: $CHAIN_ID)"
print_info "Environment: $ENVIRONMENT"
print_info "Deployment context: $DEPLOYMENT_CONTEXT"
print_info "Deploy script: $DEPLOY_SCRIPT"

# Run cleanup unless skipped
if [[ "$SKIP_CLEAN" == false ]]; then
    print_info "Running fork cleanup..."
    "$SCRIPT_DIR/clean-fork.sh" --network "$NETWORK"
else
    print_warning "Skipping fork cleanup"
fi

# Check if Anvil is running
if ! curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null 2>&1; then
    print_error "Anvil is not running on localhost:8545"
    print_error "Please start Anvil first with: ./bash/start-fork.sh --network $NETWORK"
    exit 1
fi

print_success "Anvil is running on localhost:8545"

# Run deployment
print_info "Starting deployment..."
DEPLOYMENT_CONTEXT="$DEPLOYMENT_CONTEXT" forge script "$DEPLOY_SCRIPT" \
    --rpc-url http://localhost:8545 \
    --broadcast \
    --sender 0x8842fe65A7Db9BB5De6d50e49aF19496da09F9b5 \
    -vvv \
    --unlocked

# Sync deployments
print_info "Syncing deployments..."
./forge-deploy sync

print_success "Deployment completed successfully!"
print_success "Deployment artifacts are in deployments/$DEPLOYMENT_CONTEXT/"
