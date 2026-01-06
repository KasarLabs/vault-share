#!/usr/bin/env bash
set -e

# Script pour déployer un Worker Account
# Génère automatiquement une paire de clés pour le worker
# Usage: ./deploy_worker_account.sh <VAULT_ADDRESS>

# ---- INPUTS ----
VAULT_ADDRESS=$1
NETWORK=${2:-mainnet}

if [ -z "$VAULT_ADDRESS" ]; then
    echo "Error: VAULT_ADDRESS is required"
    echo "Usage: $0 <VAULT_ADDRESS>"
    exit 1
fi

# ---- GENERATE KEYPAIR ----
echo "==================================="
echo "  Worker Account Deployment"
echo "==================================="
echo ""
echo "Generating new keypair for worker..."

# Créer un nom temporaire unique pour le compte
TEMP_ACCOUNT_NAME="worker_$(date +%s)"

# Créer le compte avec sncast (génère automatiquement les clés)
echo "Creating account..."
sncast account create \
  --name $TEMP_ACCOUNT_NAME \
  --network $NETWORK

echo ""
echo "⚠️  IMPORTANT - SAVE THESE CREDENTIALS ⚠️"
echo "================================================"

# Afficher les credentials avec la clé privée
sncast account list --display-private-keys 2>&1 | grep -A 15 "$TEMP_ACCOUNT_NAME:"

echo "================================================"

# Extraire la clé publique
MEMBER_PUBKEY=$(sncast account list 2>&1 | grep -A 15 "$TEMP_ACCOUNT_NAME:" | grep -oP "public key: \K0x[0-9a-fA-F]+")

echo ""
echo "✓ Keypair generated successfully!"
echo "Public Key (for deployment): $MEMBER_PUBKEY"
echo ""
echo "⚠️  The PRIVATE KEY is shown above - SAVE IT NOW!"
echo "⚠️  You will need it to sign transactions with this worker"
echo "⚠️  This is the ONLY time it will be displayed!"
echo ""
echo ""

# ---- CONFIGURATION ----
CONTRACT_NAME="MemberWorkerAccount"

# ---- DEPLOY ----
echo ""
echo "Deploying Worker Account..."
echo "  Member PubKey: $MEMBER_PUBKEY"
echo ""

DEPLOY_OUTPUT=$(sncast deploy \
  --contract-name $CONTRACT_NAME \
  --network $NETWORK \
  --arguments $MEMBER_PUBKEY)

echo "$DEPLOY_OUTPUT"
# Extraire l'adresse du worker déployé
WORKER_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oP "Contract Address: \K0x[0-9a-fA-F]+")

if [ -z "$WORKER_ADDRESS" ]; then
    echo ""
    echo "❌ Failed to extract worker address from deployment output"
    exit 1
fi

echo ""
echo "✓ Worker deployed at: $WORKER_ADDRESS"

# ---- SET VAULT ----
echo ""
echo "Setting vault address on worker..."
echo "  Vault: $VAULT_ADDRESS"

sncast invoke \
  --contract-address $WORKER_ADDRESS \
  --function set_vault \
  --arguments $VAULT_ADDRESS \
  --network $NETWORK

echo ""
echo "✓ Vault address configured!"

echo ""
echo "==================================="
echo "  Deployment Complete"
echo "==================================="
echo ""
echo "Worker Address: $WORKER_ADDRESS"
echo "Public Key: $MEMBER_PUBKEY"
echo "Vault Address: $VAULT_ADDRESS"
echo ""
echo "⚠️  REMEMBER TO:"
echo "1. Save the private key shown above"
echo "2. Save the worker address: $WORKER_ADDRESS"
echo "3. Register worker in TeamVault: register_worker($MEMBER_PUBKEY, $WORKER_ADDRESS)"
echo ""
