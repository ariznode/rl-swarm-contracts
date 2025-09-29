#!/bin/bash

# Source the environment variables
set -a
source .env
set +a

# Function to deploy a new proxy with a new implementation
new() {
    # Run the deployment script and capture its output
    echo "Deploying proxy..."
    DEPLOY_OUTPUT=$(forge script script/DeploySwarmCoordinatorProxy.s.sol --slow \
       --rpc-url=$ETH_RPC_URL \
       --private-key=$ETH_PRIVATE_KEY \
       --sig "run()" \
       --no-cache \
       --broadcast)

    # Extract the implementation address using grep and sed
    PROXY_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "SwarmCoordinator proxy deployed at:" | sed -E 's/.*: (0x[a-fA-F0-9]+)/\1/')
    IMPLEMENTATION_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "SwarmCoordinator implementation deployed at:" | sed -E 's/.*: (0x[a-fA-F0-9]+)/\1/')

    if [ -z "$PROXY_ADDRESS" ]; then
        echo "Failed to extract implementation address from deployment output"
        return 1
    fi

    if [ -z "$IMPLEMENTATION_ADDRESS" ]; then
        echo "Failed to extract implementation address from deployment output"
        return 1
    fi

    echo "Proxy address: $PROXY_ADDRESS"
    echo "Implementation address: $IMPLEMENTATION_ADDRESS"
}

# Function to deploy contract for a given proxy address
deploy() {
    local proxy_address=$1
    echo "Deploying for proxy: $proxy_address"
    
    # Set the proxy address for the deployment script
    export PROXY_ADDRESS="$proxy_address"
    
    # Run the deployment script and capture its output
    echo "Deploying implementation..."
    DEPLOY_OUTPUT=$(forge script script/DeploySwarmCoordinatorProxy.s.sol --slow \
       --rpc-url=$ETH_RPC_URL \
       --private-key=$ETH_PRIVATE_KEY \
       --sig "deployNewVersion()" \
       --no-cache \
       --broadcast)

    # Extract the implementation address using grep and sed
    IMPLEMENTATION_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "SwarmCoordinator implementation deployed at:" | sed -E 's/.*: (0x[a-fA-F0-9]+)/\1/')

    if [ -z "$IMPLEMENTATION_ADDRESS" ]; then
        echo "Failed to extract implementation address from deployment output"
        return 1
    fi

    echo "Implementation address: $IMPLEMENTATION_ADDRESS"
    # Store the implementation address in a file for later verification
    echo "$IMPLEMENTATION_ADDRESS" > ".implementation-${proxy_address}.addr"
}

# Function to verify contract for a given proxy address
verify() {
    local proxy_address=$1
    echo "Verifying for proxy: $proxy_address"

    # Read the implementation address from file
    if [ ! -f ".implementation-${proxy_address}.addr" ]; then
        echo "No implementation address found for proxy ${proxy_address}. Deploy first."
        return 1
    fi

    IMPLEMENTATION_ADDRESS=$(cat ".implementation-${proxy_address}.addr")
    
    # Verify the contract
    echo "Verifying contract..."
    forge verify-contract \
        --rpc-url "$ETH_RPC_URL" \
        --verifier blockscout \
        --verifier-url 'https://gensyn-testnet.explorer.alchemy.com/api/' \
        "$IMPLEMENTATION_ADDRESS" \
        src/SwarmCoordinator.sol:SwarmCoordinator

    # Clean up the temporary file
    rm ".implementation-${proxy_address}.addr"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --deploy-only    Only deploy the contracts"
    echo "  --verify-only    Only verify the contracts"
    echo "  --help           Show this help message"
    echo ""
    echo "If no options are provided, both deploy and verify will be performed."
}

# Parse command line arguments
NEW=false
DEPLOY=true
VERIFY=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --new)
            NEW=true
            shift
            ;;
        --deploy-only)
            VERIFY=false
            shift
            ;;
        --verify-only)
            DEPLOY=false
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# We don't need the proxy addresses if deploying a new proxy.
# Can verify seperately after.
if [ "$NEW" = true ]; then
    if ! new; then
        echo "Failed to deploy new proxy"
        exit 1
    fi
    exit 0
fi

# Read the proxy addresses array from environment
# The format in .env should be: PROXY_ADDRESSES=("0x123..." "0x456...")
if [ -z "$PROXY_ADDRESSES" ]; then
    echo "No proxy addresses defined in PROXY_ADDRESSES array"
    exit 1
fi

# Process each proxy address
echo "Processing all proxies..."
for proxy in "${PROXY_ADDRESSES[@]}"; do
    if [ ! -z "$proxy" ]; then
        echo "----------------------------------------"
        echo "Processing proxy address: $proxy"
        echo "----------------------------------------"

        if [ "$DEPLOY" = true ]; then
            if ! deploy "$proxy"; then
                echo "Failed to deploy for proxy: $proxy"
                exit 1
            fi
        fi

        if [ "$VERIFY" = true ]; then
            if ! verify "$proxy"; then
                echo "Failed to verify for proxy: $proxy"
                exit 1
            fi
        fi
    fi
done

echo "All operations completed successfully!" 