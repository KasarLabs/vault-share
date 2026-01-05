#!/usr/bin/env bash
set -e

# Script pour déployer un TeamVault
# Usage: ./deploy_team_vault.sh <ADMIN_ADDRESS>

# ---- INPUTS ----
ADMIN_ADDRESS=$1

if [ -z "$ADMIN_ADDRESS" ]; then
    echo "Error: ADMIN_ADDRESS is required"
    echo "Usage: $0 <ADMIN_ADDRESS>"
    exit 1
fi

# ---- CONFIGURATION ----
CONTRACT_NAME="TeamVault"

# ---- DEPLOY ----
echo "Deploying TeamVault..."
echo "  Admin Address: $ADMIN_ADDRESS"
echo ""

sncast deploy \
  --contract-name $CONTRACT_NAME \
  --arguments $ADMIN_ADDRESS \
  --network mainnet