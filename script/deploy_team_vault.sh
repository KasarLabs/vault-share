#!/usr/bin/env bash
set -e

# Script pour déployer un TeamVault
# Usage: ./deploy_team_vault.sh <ADMIN_ADDRESS> [NETWORK]

# ---- INPUTS ----
ADMIN_ADDRESS=$1
NETWORK=${2:-mainnet}

if [ -z "$ADMIN_ADDRESS" ]; then
    echo "Error: ADMIN_ADDRESS is required"
    echo "Usage: $0 <ADMIN_ADDRESS> [NETWORK]"
    echo "NETWORK defaults to 'mainnet' if not specified"
    exit 1
fi

# ---- CONFIGURATION ----
CONTRACT_NAME="TeamVault"

# ---- DEPLOY ----
echo "Deploying TeamVault..."
echo "  Admin Address: $ADMIN_ADDRESS"
echo "  Network: $NETWORK"
echo ""

sncast deploy \
  --contract-name $CONTRACT_NAME \
  --arguments $ADMIN_ADDRESS \
  --network $NETWORK