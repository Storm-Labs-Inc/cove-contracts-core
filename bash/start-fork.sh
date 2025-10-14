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
Usage: $0 --network <mainnet|base> [--fork-block <number>]

Start an Anvil fork for local development and testing.

Options:
    --network <mainnet|base>    Specify the network (required)
    --fork-block <number>       Specify the fork block number (optional)
                                Default: latest for mainnet, 36368200 for base
    -h, --help                  Display this help message

Examples:
    $0 --network mainnet
    $0 --network base
    $0 --network mainnet --fork-block 19000000
    $0 --network base --fork-block 36368200

Environment Variables Required:
    MAINNET_RPC_URL            RPC URL for Ethereum mainnet
    BASE_RPC_URL               RPC URL for Base network
EOF
    exit 1
}

# Parse arguments
NETWORK=""
FORK_BLOCK=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --network)
            NETWORK="$2"
            shift 2
            ;;
        --fork-block)
            FORK_BLOCK="$2"
            shift 2
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

# Map network to RPC URL and set defaults
case "$NETWORK" in
    mainnet)
        RPC_URL="${MAINNET_RPC_URL}"
        RPC_VAR="MAINNET_RPC_URL"
        CHAIN_ID="1"
        # Use latest block if not specified for mainnet
        ;;
    base)
        RPC_URL="${BASE_RPC_URL}"
        RPC_VAR="BASE_RPC_URL"
        CHAIN_ID="8453"
        # Default fork block for base if not specified
        if [[ -z "$FORK_BLOCK" ]]; then
            FORK_BLOCK="36368200"
            print_info "Using default Base fork block: $FORK_BLOCK"
        fi
        ;;
    *)
        print_error "Invalid network: $NETWORK. Must be 'mainnet' or 'base'"
        exit 1
        ;;
esac

# Check if RPC URL is set
if [[ -z "$RPC_URL" ]]; then
    print_error "RPC URL not set. Please set $RPC_VAR environment variable"
    exit 1
fi

print_info "Starting Anvil fork for $NETWORK (chain ID: $CHAIN_ID)"
print_info "RPC URL: [REDACTED]"

# Build anvil command
ANVIL_CMD="anvil --fork-url $RPC_URL"

if [[ -n "$FORK_BLOCK" ]]; then
    ANVIL_CMD="$ANVIL_CMD --fork-block-number $FORK_BLOCK"
    print_info "Fork block: $FORK_BLOCK"
else
    print_info "Fork block: latest"
fi

# Add auto-impersonate flag for easier testing
ANVIL_CMD="$ANVIL_CMD --auto-impersonate"

print_success "Starting Anvil with command:"
# Censor the RPC URL in the printed command, but show all other params
CENSORED_CMD=$(echo "$ANVIL_CMD" | sed -E 's/(--fork-url )[^ ]+/\1[REDACTED]/')
echo -e "${GREEN}$CENSORED_CMD${NC}"
echo ""
print_info "Anvil will be available at: http://localhost:8545"
print_info "Press Ctrl+C to stop"
echo ""

# Start anvil
exec $ANVIL_CMD
