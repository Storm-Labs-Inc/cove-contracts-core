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
Usage: $0 --network <mainnet|base>

Clean fork deployment folders by removing JSON files and copying from source.

Options:
    --network <mainnet|base>    Specify the network (required)
    -h, --help                  Display this help message

Examples:
    $0 --network mainnet
    $0 --network base
EOF
    exit 1
}

# Parse arguments
NETWORK=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --network)
            NETWORK="$2"
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

# Map network to chain ID
case "$NETWORK" in
    mainnet)
        CHAIN_ID="1"
        ;;
    base)
        CHAIN_ID="8453"
        ;;
    *)
        print_error "Invalid network: $NETWORK. Must be 'mainnet' or 'base'"
        exit 1
        ;;
esac

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOYMENTS_DIR="$PROJECT_ROOT/deployments"

SOURCE_DIR="$DEPLOYMENTS_DIR/$CHAIN_ID"
FORK_DIR="$DEPLOYMENTS_DIR/$CHAIN_ID-fork"

print_info "Cleaning fork deployments for $NETWORK (chain ID: $CHAIN_ID)"
print_info "Source directory: $SOURCE_DIR"
print_info "Fork directory: $FORK_DIR"

# Check if source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    print_error "Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

# Create fork directory if it doesn't exist
if [[ ! -d "$FORK_DIR" ]]; then
    print_warning "Fork directory does not exist. Creating: $FORK_DIR"
    mkdir -p "$FORK_DIR"
fi

# Count JSON files before cleanup
BEFORE_COUNT=$(find "$FORK_DIR" -type f -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
print_info "Found $BEFORE_COUNT JSON files in fork directory"

# Remove all JSON files from fork directory
print_info "Removing JSON files from fork directory..."
find "$FORK_DIR" -type f -name "*.json" -delete

# Count files in source directory
SOURCE_COUNT=$(find "$SOURCE_DIR" -type f -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
print_info "Found $SOURCE_COUNT JSON files in source directory"

# Copy JSON files from source to fork directory
print_info "Copying JSON files from source to fork directory..."
if [[ $SOURCE_COUNT -gt 0 ]]; then
    cp -v "$SOURCE_DIR"/*.json "$FORK_DIR/" 2>/dev/null || {
        # Try with find in case there are subdirectories
        find "$SOURCE_DIR" -type f -name "*.json" -exec cp {} "$FORK_DIR/" \;
    }
    AFTER_COUNT=$(find "$FORK_DIR" -type f -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    print_success "Copied $AFTER_COUNT JSON files to fork directory"
else
    print_warning "No JSON files found in source directory"
fi

print_success "Fork cleanup completed for $NETWORK"
