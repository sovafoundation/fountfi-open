#!/bin/bash

# Script to check the current status of collateral registration

echo "Checking MultiCollateral System Status..."

# Export required environment variables
export MC_REGISTRY_ADDRESS=0x63c8215a478f8F57C548a8700420Ac5Bd8Dc3749
export MC_STRATEGY_ADDRESS=0xe7Ced7592F323a798A3aF6Cb3E041A9a7179F9A4
export ACTION=view_status

# Run the management script
forge script script/ManageMultiCollateral.s.sol:ManageMultiCollateralScript \
    --rpc-url optimism-sepolia \
    -vvv