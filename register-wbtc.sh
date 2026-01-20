#!/bin/bash

# Script to register WBTC in the MultiCollateralRegistry

echo "Registering WBTC in MultiCollateralRegistry..."

# Export required environment variables
export MC_REGISTRY_ADDRESS=0x63c8215a478f8F57C548a8700420Ac5Bd8Dc3749
export MC_STRATEGY_ADDRESS=0xe7Ced7592F323a798A3aF6Cb3E041A9a7179F9A4
export ACTION=add_collateral
export TOKEN_ADDRESS=0xc9FE3e6fF20fE4EB4F48B3993C947be51007D2C1
export RATE=1000000000000000000  # 1e18 = 1:1 with SovaBTC
export DECIMALS=8

# Make sure PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY environment variable not set"
    echo "Please export your private key: export PRIVATE_KEY=0x..."
    exit 1
fi

# Run the management script
forge script script/ManageMultiCollateral.s.sol:ManageMultiCollateralScript \
    --rpc-url optimism-sepolia \
    --broadcast \
    -vvv

echo "WBTC registration complete!"