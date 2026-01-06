# VaultShare - Shared Treasury Management for Starknet Teams

> A complete treasury solution enabling teams to manage shared funds with individual spending limits and automatic gas sponsorship.


## What is VaultShare?

VaultShare is a smart contract system that allows teams (DAOs, companies, guilds) to manage a shared treasury on Starknet while giving individual members controlled access to funds. Think of it as **corporate cards for your DAO**.

### Key Features
- **Shared Treasury** : Central vault holding team funds
- **Individual Limits** : Each member has customizable spending limits
- **Gas Sponsorship** :Vault automatically pays transaction fees for members
- **Multi-Token Support** : Manage any ERC-20 token (STRK, ETH, USDC, etc.)
- **Pause Mechanism**: Emergency stop for critical situations

## Use Cases

- **DAO Operations**: Give council members budgets without exposing the entire treasury
- **Web3 Teams**: Developers get spending limits for gas and services
- **Gaming Guilds**: Players access guild funds within their allowances
- **Investment Funds**: Traders operate with predefined risk limits

## How It Works

### The Two-Account System

```
TeamVault (Treasury)
    ├─ Admin: Full control
    └─ Members:
        ├─ Alice (Member)
        │   └─ Worker Account (0x123...) - Alice's smart wallet
        │       ├─ Spending limit: 1000 STRK
        │       ├─ Current spent: 350 STRK
        │       └─ Remaining: 650 STRK
        │
        └─ Bob (Member)
            └─ Worker Account (0x456...) - Bob's smart wallet
                ├─ Spending limit: 500 STRK
                └─ Gas fees paid by vault ✨
```

## Quick Start

### Prerequisites

```bash
# Install Scarb (Cairo package manager)
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh

# Install Starknet Foundry
curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh

# Clone the repository
git clone <your-repo>
cd vault-share

# Build contracts
scarb build

# Register a wallet to be able to deploy and read/write contracts
sncast account import \
  --network $NETWORK \
  --address 0x123456 \
  --private-key 0x789123 \
  --type argent
```

### 1. Deploy the Vault

```bash
./script/deploy_team_vault.sh <ADMIN_ADDRESS>
# Save the returned vault address: VAULT_ADDRESS=0x...
```

### 2. Initial Configuration

```bash
VAULT_ADDRESS="0x..."  # From step 1
STRK_TOKEN="0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"

# Set STRK as the gas token
sncast invoke \
  --contract-address $VAULT_ADDRESS \
  --function set_strk_token \
  --arguments $STRK_TOKEN \
  --network $NETWORK

# Allow STRK for withdrawals
sncast invoke \
  --contract-address $VAULT_ADDRESS \
  --function allow_token \
  --arguments $STRK_TOKEN \
  --network $NETWORK
```

### 3. Add Team Members

```bash
# Add Alice to the team
ALICE_PUBKEY="0xABC..."
sncast invoke \
  --contract-address $VAULT_ADDRESS \
  --function add_member \
  --arguments $ALICE_PUBKEY \
  --network $NETWORK

# Set Alice's spending limit to 1000 STRK
sncast invoke \
  --contract-address $VAULT_ADDRESS \
  --function set_withdraw_limit \
  --arguments $ALICE_PUBKEY $STRK_TOKEN 1000000000000000000000 0 \
  --network $NETWORK
```

### 4. Deploy Worker Accounts

```bash
# Deploy a worker for Alice
./script/deploy_worker_account.sh $VAULT_ADDRESS

# IMPORTANT: Save the displayed private key immediately!
# Example output:
# Worker deployed at: 0x789...
# Member public key: 0xABC...
# Private key: 0xDEF... (SAVE THIS!)
```

### 5. Register Workers

```bash
ALICE_WORKER="0x789..."  # From step 4

sncast invoke \
  --contract-address $VAULT_ADDRESS \
  --function register_worker \
  --arguments $ALICE_PUBKEY $ALICE_WORKER \
  --network $NETWORK
```

### 6. Fund the Vault

Transfer STRK tokens to your vault address using any wallet.

```bash
# Check vault balance
sncast call \
  --contract-address $STRK_TOKEN \
  --function balanceOf \
  --arguments $VAULT_ADDRESS \
  --network $NETWORK
```

## Usage Guide

### For Members: Making Withdrawals

Once your worker is registered, you can withdraw within your limit:

```bash
# Import your worker account
sncast account import \
  --name alice-worker \
  --address $ALICE_WORKER \
  --private-key $ALICE_PRIVATE_KEY \
  --type oz

# Withdraw 100 STRK
sncast invoke \
  --contract-address $VAULT_ADDRESS \
  --function withdraw \
  --arguments $STRK_TOKEN 100000000000000000000 0 \
  --account alice-worker \
  --network $NETWORK

```

### For Admins: Management Operations

```bash
# Add multiple members at once
sncast invoke \
  --contract-address $VAULT_ADDRESS \
  --function add_members \
  --arguments 3 $ALICE_PUBKEY $BOB_PUBKEY $CHARLIE_PUBKEY \
  --network $NETWORK

# Deactivate a member temporarily (without removing)
sncast invoke \
  --contract-address $VAULT_ADDRESS \
  --function set_member_active \
  --arguments $ALICE_PUBKEY 0 \
  --network $NETWORK

# Reset a member's spent amount (monthly reset)
sncast invoke \
  --contract-address $VAULT_ADDRESS \
  --function reset_spent \
  --arguments $ALICE_PUBKEY $STRK_TOKEN \
  --network $NETWORK

# Emergency pause
sncast invoke \
  --contract-address $VAULT_ADDRESS \
  --function pause \
  --arguments 1 \
  --network $NETWORK
```

### Querying State

```bash
# Check member's spending
sncast call \
  --contract-address $VAULT_ADDRESS \
  --function get_withdraw_spent \
  --arguments $ALICE_PUBKEY $STRK_TOKEN \
  --network $NETWORK

# Check member's limit
sncast call \
  --contract-address $VAULT_ADDRESS \
  --function get_withdraw_limit \
  --arguments $ALICE_PUBKEY $STRK_TOKEN \
  --network $NETWORK

# Get worker for a member
sncast call \
  --contract-address $VAULT_ADDRESS \
  --function get_worker_for_member \
  --arguments $ALICE_PUBKEY \
  --network $NETWORK
```

## Security Features

### Reentrancy Protection
Uses OpenZeppelin's `ReentrancyGuard` component to prevent reentrancy attacks.

### Two-Step Admin Transfer
Admin rights transfer requires acceptance from the new admin to prevent accidental transfers.

### Spending Limits
Withdrawals and gas fees **share the same limit** for STRK token, preventing abuse.

### Pause Mechanism
Admin can pause all operations in case of emergency.

### Worker Validation
Workers are cryptographically linked to members and verified on registration.


## 📊 Gas & Fees

### How Paymaster Works

1. Member initiates transaction from their worker
2. Vault's `__validate_paymaster__` checks:
   - Worker is registered
   - Member is active
   - Fees + spent ≤ limit
3. Transaction executes
4. Vault's `__post_dispatch_paymaster__` pays the sequencer
5. Member's `withdraw_spent` increases by fee amount

**Important**: Gas fees and withdrawals share the same STRK limit!

## 📚 Additional Resources

- [Starknet Documentation](https://docs.starknet.io)
- [Cairo Book](https://book.cairo-lang.org)
- [OpenZeppelin Cairo Contracts](https://github.com/OpenZeppelin/cairo-contracts)
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/)


## 📄 License

MIT License 


---

**Built with ❤️ for the Starknet ecosystem**
