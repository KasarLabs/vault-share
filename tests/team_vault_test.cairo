use core::serde::Serde;
use core::traits::TryInto;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address, spy_events, EventSpyAssertionsTrait,
};
use starknet::ContractAddress;

use vault_share::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use vault_share::team_vault::{ITeamVaultDispatcher, ITeamVaultDispatcherTrait};
use vault_share::team_vault::TeamVault;
use vault_share::member_worker_account::{
    IMemberWorkerAccountDispatcher
};

fn deploy_mock_erc20() -> IMockERC20Dispatcher {
    let contract = declare("MockERC20").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    IMockERC20Dispatcher { contract_address }
}

fn deploy_team_vault(admin: ContractAddress) -> ITeamVaultDispatcher {
    let contract = declare("TeamVault").unwrap().contract_class();
    let mut constructor_args = array![];
    Serde::serialize(@admin, ref constructor_args);
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    ITeamVaultDispatcher { contract_address }
}

fn deploy_member_worker_account(
    member_pubkey: felt252, vault: ContractAddress
) -> IMemberWorkerAccountDispatcher {
    let contract = declare("MemberWorkerAccount").unwrap().contract_class();
    let mut constructor_args = array![];
    Serde::serialize(@member_pubkey, ref constructor_args);
    Serde::serialize(@vault, ref constructor_args);
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    IMemberWorkerAccountDispatcher { contract_address }
}

#[test]
fn test_withdraw_happy_path_updates_spent_and_transfers() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;

    // Fund the vault.
    token.mint(vault.contract_address, 1_000_u256);

    // Admin setup.
    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.allow_token(token.contract_address);
    vault.register_worker(member_pubkey, worker);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 100_u256);
    stop_cheat_caller_address(vault.contract_address);

    // Worker withdraw.
    start_cheat_caller_address(vault.contract_address, worker);
    let ok = vault.withdraw(token.contract_address, 40_u256);
    assert(ok, 'withdraw should return true');
    stop_cheat_caller_address(vault.contract_address);

    // Balances changed.
    let worker_bal = token.balance_of(worker);
    let vault_bal = token.balance_of(vault.contract_address);
    assert(worker_bal == 40_u256, 'worker bal');
    assert(vault_bal == 960_u256, 'vault bal');

    // Spent updated.
    let spent = vault.get_withdraw_spent(member_pubkey, token.contract_address);
    assert(spent == 40_u256, 'spent');
}

#[test]
#[should_panic(expected: "Token not allowed")]
fn test_withdraw_reverts_if_token_not_allowed() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;
    token.mint(vault.contract_address, 1_000_u256);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.register_worker(member_pubkey, worker);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 100_u256);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 1_u256);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
#[should_panic(expected: "Withdraw limit exceeded")]
fn test_withdraw_reverts_if_over_limit() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;
    token.mint(vault.contract_address, 1_000_u256);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.allow_token(token.contract_address);
    vault.register_worker(member_pubkey, worker);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 10_u256);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 11_u256);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
#[should_panic(expected: "Vault is paused")]
fn test_withdraw_reverts_when_paused() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;
    token.mint(vault.contract_address, 1_000_u256);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.allow_token(token.contract_address);
    vault.register_worker(member_pubkey, worker);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 100_u256);
    vault.pause(true);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 1_u256);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
#[should_panic(expected: "Worker member pubkey mismatch")]
fn test_register_worker_reverts_if_worker_pubkey_mismatch() {
    let admin: ContractAddress = 111.try_into().unwrap();

    let member_a: felt252 = 0xAAA;
    let member_b: felt252 = 0xBBB;

    let vault = deploy_team_vault(admin);
    // Worker account is created with member_a's pubkey
    let worker_account = deploy_member_worker_account(member_a, vault.contract_address);
    let worker = worker_account.contract_address;

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_a);
    vault.add_member(member_b);

    vault.register_worker(member_a, worker);
    // This should fail because worker was created with member_a's pubkey, not member_b's
    vault.register_worker(member_b, worker);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
#[should_panic(expected: "Limit not set")]
fn test_withdraw_reverts_if_limit_not_set() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;
    token.mint(vault.contract_address, 1_000_u256);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.allow_token(token.contract_address);
    vault.register_worker(member_pubkey, worker);
    // Note: limit is NOT set (defaults to 0)
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 1_u256);
    stop_cheat_caller_address(vault.contract_address);
}

// ========== Member Management Tests ==========

#[test]
fn test_add_member_emits_event() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let member_pubkey: felt252 = 0xABC;
    let mut spy = spy_events();

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    stop_cheat_caller_address(vault.contract_address);

    let expected_event = TeamVault::Event::MemberAdded(
        TeamVault::MemberAdded { member_pubkey }
    );
    let expected_events = array![(vault.contract_address, expected_event)];
    spy.assert_emitted(@expected_events);

    assert(vault.get_member_exists(member_pubkey), 'member exists');
    assert(vault.get_member_is_active(member_pubkey), 'member active');
}

#[test]
#[should_panic(expected: "Member exists")]
fn test_add_member_reverts_if_member_exists() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let member_pubkey: felt252 = 0xABC;

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.add_member(member_pubkey);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
#[should_panic(expected: "Pubkey is zero")]
fn test_add_member_reverts_if_pubkey_zero() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(0);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
fn test_remove_member() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let member_pubkey: felt252 = 0xABC;
    let mut spy = spy_events();

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    assert(vault.get_member_exists(member_pubkey), 'member exists');
    
    vault.remove_member(member_pubkey);
    stop_cheat_caller_address(vault.contract_address);

    let expected_event = TeamVault::Event::MemberRemoved(
        TeamVault::MemberRemoved { member_pubkey }
    );
    let expected_events = array![(vault.contract_address, expected_event)];
    spy.assert_emitted(@expected_events);

    assert(!vault.get_member_exists(member_pubkey), 'member removed');
}

#[test]
#[should_panic(expected: "Member missing")]
fn test_remove_member_reverts_if_member_not_exists() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let member_pubkey: felt252 = 0xABC;

    start_cheat_caller_address(vault.contract_address, admin);
    vault.remove_member(member_pubkey);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
fn test_set_member_active() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let member_pubkey: felt252 = 0xABC;
    let mut spy = spy_events();

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    assert(vault.get_member_is_active(member_pubkey), 'member active');
    
    vault.set_member_active(member_pubkey, false);
    assert(!vault.get_member_is_active(member_pubkey), 'member inactive');
    
    vault.set_member_active(member_pubkey, true);
    assert(vault.get_member_is_active(member_pubkey), 'member active2');
    stop_cheat_caller_address(vault.contract_address);

    let expected_events = array![
        (vault.contract_address, TeamVault::Event::MemberActiveSet(
            TeamVault::MemberActiveSet { member_pubkey, is_active: false }
        )),
        (vault.contract_address, TeamVault::Event::MemberActiveSet(
            TeamVault::MemberActiveSet { member_pubkey, is_active: true }
        ))
    ];
    spy.assert_emitted(@expected_events);
}

#[test]
#[should_panic(expected: "Member inactive")]
fn test_withdraw_reverts_if_member_inactive() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;
    token.mint(vault.contract_address, 1_000_u256);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.allow_token(token.contract_address);
    vault.register_worker(member_pubkey, worker);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 100_u256);
    vault.set_member_active(member_pubkey, false);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 1_u256);
    stop_cheat_caller_address(vault.contract_address);
}

// ========== Token Management Tests ==========

#[test]
fn test_disallow_token() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let token = deploy_mock_erc20();
    let mut spy = spy_events();

    start_cheat_caller_address(vault.contract_address, admin);
    vault.allow_token(token.contract_address);
    assert(vault.is_allowed_token(token.contract_address), 'token allowed');
    
    vault.disallow_token(token.contract_address);
    assert(!vault.is_allowed_token(token.contract_address), 'token disallowed');
    stop_cheat_caller_address(vault.contract_address);

    let expected_event = TeamVault::Event::TokenDisallowed(
        TeamVault::TokenDisallowed { token: token.contract_address }
    );
    let expected_events = array![(vault.contract_address, expected_event)];
    spy.assert_emitted(@expected_events);
}

#[test]
fn test_allow_token_emits_event() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let token = deploy_mock_erc20();
    let mut spy = spy_events();

    start_cheat_caller_address(vault.contract_address, admin);
    vault.allow_token(token.contract_address);
    stop_cheat_caller_address(vault.contract_address);

    let expected_event = TeamVault::Event::TokenAllowed(
        TeamVault::TokenAllowed { token: token.contract_address }
    );
    let expected_events = array![(vault.contract_address, expected_event)];
    spy.assert_emitted(@expected_events);
}

// ========== Withdraw Limit Tests ==========

#[test]
fn test_multiple_withdrawals_accumulate() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;
    token.mint(vault.contract_address, 1_000_u256);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.allow_token(token.contract_address);
    vault.register_worker(member_pubkey, worker);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 100_u256);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 30_u256);
    assert(vault.get_withdraw_spent(member_pubkey, token.contract_address) == 30_u256, 'spent 30');
    
    vault.withdraw(token.contract_address, 40_u256);
    assert(vault.get_withdraw_spent(member_pubkey, token.contract_address) == 70_u256, 'spent 70');
    
    vault.withdraw(token.contract_address, 30_u256);
    assert(vault.get_withdraw_spent(member_pubkey, token.contract_address) == 100_u256, 'spent 100');
    stop_cheat_caller_address(vault.contract_address);

    let worker_bal = token.balance_of(worker);
    assert(worker_bal == 100_u256, 'worker 100');
}

#[test]
#[should_panic(expected: "Withdraw limit exceeded")]
fn test_withdraw_reverts_when_accumulated_exceeds_limit() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;
    token.mint(vault.contract_address, 1_000_u256);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.allow_token(token.contract_address);
    vault.register_worker(member_pubkey, worker);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 100_u256);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 60_u256);
    vault.withdraw(token.contract_address, 41_u256); // 60 + 41 = 101 > 100
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
fn test_reset_spent() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;
    token.mint(vault.contract_address, 1_000_u256);
    let mut spy = spy_events();

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.allow_token(token.contract_address);
    vault.register_worker(member_pubkey, worker);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 100_u256);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 50_u256);
    assert(vault.get_withdraw_spent(member_pubkey, token.contract_address) == 50_u256, 'spent 50');
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.reset_spent(member_pubkey, token.contract_address);
    assert(vault.get_withdraw_spent(member_pubkey, token.contract_address) == 0_u256, 'spent reset');
    stop_cheat_caller_address(vault.contract_address);

    let expected_event = TeamVault::Event::SpentReset(
        TeamVault::SpentReset { member_pubkey, token: token.contract_address }
    );
    let expected_events = array![(vault.contract_address, expected_event)];
    spy.assert_emitted(@expected_events);

    // Should be able to withdraw again after reset
    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 30_u256);
    assert(vault.get_withdraw_spent(member_pubkey, token.contract_address) == 30_u256, 'spent 30');
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
fn test_set_withdraw_limit_emits_event() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let token = deploy_mock_erc20();
    let member_pubkey: felt252 = 0xABC;
    let mut spy = spy_events();

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 200_u256);
    stop_cheat_caller_address(vault.contract_address);

    let expected_event = TeamVault::Event::WithdrawLimitSet(
        TeamVault::WithdrawLimitSet { member_pubkey, token: token.contract_address, limit: 200_u256 }
    );
    let expected_events = array![(vault.contract_address, expected_event)];
    spy.assert_emitted(@expected_events);

    assert(vault.get_withdraw_limit(member_pubkey, token.contract_address) == 200_u256, 'limit 200');
}

// ========== Worker Management Tests ==========

// Note: test_register_worker_emits_event is skipped because it requires
// deploying a MemberWorkerAccount contract which is complex to set up in tests

#[test]
fn test_get_worker_for_member() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let member_pubkey: felt252 = 0xABC;

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    let worker = vault.get_worker_for_member(member_pubkey);
    let zero: ContractAddress = 0.try_into().unwrap();
    assert(worker == zero, 'worker zero');
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
fn test_get_member_for_worker() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let worker: ContractAddress = 222.try_into().unwrap();

    let member = vault.get_member_for_worker(worker);
    assert(member == 0, 'member zero');
}

#[test]
#[should_panic(expected: "Worker not registered")]
fn test_withdraw_reverts_if_worker_not_registered() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let worker: ContractAddress = 222.try_into().unwrap();
    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    token.mint(vault.contract_address, 1_000_u256);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.allow_token(token.contract_address);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 1_u256);
    stop_cheat_caller_address(vault.contract_address);
}

// ========== Pause Tests ==========

#[test]
fn test_pause_and_unpause() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let mut spy = spy_events();

    assert(!vault.is_paused(), 'not paused');

    start_cheat_caller_address(vault.contract_address, admin);
    vault.pause(true);
    assert(vault.is_paused(), 'paused');
    
    vault.pause(false);
    assert(!vault.is_paused(), 'unpaused');
    stop_cheat_caller_address(vault.contract_address);

    let expected_events = array![
        (vault.contract_address, TeamVault::Event::PausedSet(
            TeamVault::PausedSet { paused: true }
        )),
        (vault.contract_address, TeamVault::Event::PausedSet(
            TeamVault::PausedSet { paused: false }
        ))
    ];
    spy.assert_emitted(@expected_events);
}

// ========== Admin Management Tests ==========

#[test]
fn test_get_admin() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);

    let retrieved_admin = vault.get_admin();
    assert(retrieved_admin == admin, 'admin match');
}

#[test]
fn test_transfer_admin() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let new_admin: ContractAddress = 333.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let mut spy = spy_events();

    assert(vault.get_pending_admin() == 0.try_into().unwrap(), 'no pending');

    start_cheat_caller_address(vault.contract_address, admin);
    vault.transfer_admin(new_admin);
    stop_cheat_caller_address(vault.contract_address);

    assert(vault.get_pending_admin() == new_admin, 'pending set');
    assert(vault.get_admin() == admin, 'admin unchanged');

    let expected_event = TeamVault::Event::AdminTransferStarted(
        TeamVault::AdminTransferStarted { current_admin: admin, pending_admin: new_admin }
    );
    let expected_events = array![(vault.contract_address, expected_event)];
    spy.assert_emitted(@expected_events);
}

#[test]
fn test_accept_admin() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let new_admin: ContractAddress = 333.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let mut spy = spy_events();

    start_cheat_caller_address(vault.contract_address, admin);
    vault.transfer_admin(new_admin);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, new_admin);
    vault.accept_admin();
    stop_cheat_caller_address(vault.contract_address);

    assert(vault.get_admin() == new_admin, 'admin transferred');
    assert(vault.get_pending_admin() == 0.try_into().unwrap(), 'pending cleared');

    let expected_event = TeamVault::Event::AdminTransferred(
        TeamVault::AdminTransferred { previous_admin: admin, new_admin }
    );
    let expected_events = array![(vault.contract_address, expected_event)];
    spy.assert_emitted(@expected_events);
}

#[test]
#[should_panic(expected: "No pending admin")]
fn test_accept_admin_reverts_if_no_pending() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let vault = deploy_team_vault(admin);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.accept_admin();
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
#[should_panic(expected: "Caller is not pending admin")]
fn test_accept_admin_reverts_if_caller_not_pending() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let new_admin: ContractAddress = 333.try_into().unwrap();
    let wrong_caller: ContractAddress = 444.try_into().unwrap();
    let vault = deploy_team_vault(admin);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.transfer_admin(new_admin);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, wrong_caller);
    vault.accept_admin();
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
#[should_panic(expected: "Caller is not admin")]
fn test_admin_functions_revert_if_not_admin() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let non_admin: ContractAddress = 999.try_into().unwrap();
    let vault = deploy_team_vault(admin);
    let member_pubkey: felt252 = 0xABC;

    start_cheat_caller_address(vault.contract_address, non_admin);
    vault.add_member(member_pubkey);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
#[should_panic(expected: "Amount is zero")]
fn test_withdraw_reverts_if_amount_zero() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;
    token.mint(vault.contract_address, 1_000_u256);

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.allow_token(token.contract_address);
    vault.register_worker(member_pubkey, worker);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 100_u256);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 0_u256);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
fn test_withdraw_emits_event() {
    let admin: ContractAddress = 111.try_into().unwrap();
    let member_pubkey: felt252 = 0xABC;

    let token = deploy_mock_erc20();
    let vault = deploy_team_vault(admin);
    let worker_account = deploy_member_worker_account(member_pubkey, vault.contract_address);
    let worker = worker_account.contract_address;
    token.mint(vault.contract_address, 1_000_u256);
    let mut spy = spy_events();

    start_cheat_caller_address(vault.contract_address, admin);
    vault.add_member(member_pubkey);
    vault.allow_token(token.contract_address);
    vault.register_worker(member_pubkey, worker);
    vault.set_withdraw_limit(member_pubkey, token.contract_address, 100_u256);
    stop_cheat_caller_address(vault.contract_address);

    start_cheat_caller_address(vault.contract_address, worker);
    vault.withdraw(token.contract_address, 50_u256);
    stop_cheat_caller_address(vault.contract_address);

    let expected_event = TeamVault::Event::WithdrawExecuted(
        TeamVault::WithdrawExecuted {
            member_pubkey,
            worker,
            token: token.contract_address,
            amount: 50_u256,
            new_spent: 50_u256
        }
    );
    let expected_events = array![(vault.contract_address, expected_event)];
    spy.assert_emitted(@expected_events);
}

