use starknet::ContractAddress;

#[starknet::interface]
pub trait ITeamVault<TContractState> {
    fn withdraw(ref self: TContractState, token: ContractAddress, amount: u256) -> bool;

    fn add_member(ref self: TContractState, member_pubkey: felt252);
    fn remove_member(ref self: TContractState, member_pubkey: felt252);
    fn set_member_active(ref self: TContractState, member_pubkey: felt252, is_active: bool);
    fn register_worker(
        ref self: TContractState, member_pubkey: felt252, worker: ContractAddress
    );

    fn allow_token(ref self: TContractState, token: ContractAddress);
    fn disallow_token(ref self: TContractState, token: ContractAddress);

    fn set_withdraw_limit(
        ref self: TContractState, member_pubkey: felt252, token: ContractAddress, limit: u256
    );
    fn reset_spent(ref self: TContractState, member_pubkey: felt252, token: ContractAddress);

    fn pause(ref self: TContractState, paused: bool);

    fn get_admin(self: @TContractState) -> ContractAddress;
    fn is_paused(self: @TContractState) -> bool;
    fn is_allowed_token(self: @TContractState, token: ContractAddress) -> bool;
    fn get_withdraw_limit(self: @TContractState, member_pubkey: felt252, token: ContractAddress) -> u256;
    fn get_withdraw_spent(self: @TContractState, member_pubkey: felt252, token: ContractAddress) -> u256;
    fn get_worker_for_member(self: @TContractState, member_pubkey: felt252) -> ContractAddress;
    fn get_member_for_worker(self: @TContractState, worker: ContractAddress) -> felt252;
    fn get_member_is_active(self: @TContractState, member_pubkey: felt252) -> bool;
    fn get_member_exists(self: @TContractState, member_pubkey: felt252) -> bool;

    fn transfer_admin(ref self: TContractState, new_admin: ContractAddress);
    fn accept_admin(ref self: TContractState);
    fn get_pending_admin(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod TeamVault {
    use core::traits::TryInto;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::storage::*;

    use openzeppelin_security::ReentrancyGuardComponent;

    use vault_share::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use vault_share::member_worker_account::{
        IMemberWorkerAccountDispatcher, IMemberWorkerAccountDispatcherTrait
    };

    component!(
        path: ReentrancyGuardComponent,
        storage: reentrancy_guard,
        event: ReentrancyGuardEvent
    );

    #[derive(Copy, Drop, Serde, starknet::Store)]
    pub struct MemberInfo {
        pub is_member: bool,
        pub is_active: bool,
        pub registered_worker: ContractAddress,
    }

    #[storage]
    pub struct Storage {
        admin: ContractAddress,
        pending_admin: ContractAddress,
        paused: bool,
        members: Map<felt252, MemberInfo>,
        worker_to_member: Map<ContractAddress, felt252>,
        allowed_token: Map<ContractAddress, bool>,
        withdraw_limit: Map<felt252, Map<ContractAddress, u256>>,
        withdraw_spent: Map<felt252, Map<ContractAddress, u256>>,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        MemberAdded: MemberAdded,
        MemberRemoved: MemberRemoved,
        MemberActiveSet: MemberActiveSet,
        WorkerRegistered: WorkerRegistered,
        WorkerRotated: WorkerRotated,
        TokenAllowed: TokenAllowed,
        TokenDisallowed: TokenDisallowed,
        WithdrawLimitSet: WithdrawLimitSet,
        WithdrawExecuted: WithdrawExecuted,
        SpentReset: SpentReset,
        PausedSet: PausedSet,
        AdminTransferStarted: AdminTransferStarted,
        AdminTransferCancelled: AdminTransferCancelled,
        AdminTransferred: AdminTransferred,
        WorkerUnregistered: WorkerUnregistered,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MemberAdded {
        #[key]
        pub member_pubkey: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MemberRemoved {
        #[key]
        pub member_pubkey: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct MemberActiveSet {
        #[key]
        pub member_pubkey: felt252,
        pub is_active: bool,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WorkerRegistered {
        #[key]
        pub member_pubkey: felt252,
        #[key]
        pub worker: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WorkerRotated {
        #[key]
        pub member_pubkey: felt252,
        pub old_worker: ContractAddress,
        pub new_worker: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenAllowed {
        #[key]
        pub token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenDisallowed {
        #[key]
        pub token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WithdrawLimitSet {
        #[key]
        pub member_pubkey: felt252,
        #[key]
        pub token: ContractAddress,
        pub limit: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WithdrawExecuted {
        #[key]
        pub member_pubkey: felt252,
        #[key]
        pub worker: ContractAddress,
        #[key]
        pub token: ContractAddress,
        pub amount: u256,
        pub new_spent: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SpentReset {
        #[key]
        pub member_pubkey: felt252,
        #[key]
        pub token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PausedSet {
        pub paused: bool,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AdminTransferStarted {
        #[key]
        pub current_admin: ContractAddress,
        #[key]
        pub pending_admin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AdminTransferCancelled {
        #[key]
        pub cancelled_admin: ContractAddress,
        #[key]
        pub new_pending_admin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AdminTransferred {
        #[key]
        pub previous_admin: ContractAddress,
        #[key]
        pub new_admin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WorkerUnregistered {
        #[key]
        pub member_pubkey: felt252,
        #[key]
        pub worker: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        let zero_admin = zero_address();
        assert!(admin != zero_admin, "Admin cannot be zero address");
        self.admin.write(admin);
        self.pending_admin.write(zero_admin);
        self.paused.write(false);
    }

    #[abi(embed_v0)]
    pub impl TeamVaultImpl of super::ITeamVault<ContractState> {
        fn withdraw(ref self: ContractState, token: ContractAddress, amount: u256) -> bool {
            self.reentrancy_guard.start();

            assert!(!self.paused.read(), "Vault is paused");

            let worker = get_caller_address();
            let member_pubkey = self.worker_to_member.entry(worker).read();
            assert!(member_pubkey != 0, "Worker not registered");

            let member = self.members.entry(member_pubkey).read();
            assert!(member.is_member, "Member missing");
            assert!(member.is_active, "Member inactive");
            assert!(member.registered_worker == worker, "Worker mismatch");

            assert!(self.allowed_token.entry(token).read(), "Token not allowed");

            assert!(amount > 0_u256, "Amount is zero");

            let spent = self.withdraw_spent.entry(member_pubkey).entry(token).read();
            let limit = self.withdraw_limit.entry(member_pubkey).entry(token).read();
            assert!(limit > 0_u256, "Limit not set");
            
            let new_spent = spent + amount;
            assert!(new_spent >= spent, "Withdraw amount overflow");
            assert!(new_spent <= limit, "Withdraw limit exceeded");

            // checks-effects-interactions
            self.withdraw_spent.entry(member_pubkey).entry(token).write(new_spent);

            let ok = IERC20Dispatcher { contract_address: token }.transfer(worker, amount);
            assert!(ok, "ERC20 transfer failed");

            self.emit(Event::WithdrawExecuted(
                WithdrawExecuted { member_pubkey, worker, token, amount, new_spent }
            ));

            self.reentrancy_guard.end();
            true
        }

        fn add_member(ref self: ContractState, member_pubkey: felt252) {
            self.assert_only_admin();
            assert!(member_pubkey != 0, "Pubkey is zero");

            let current = self.members.entry(member_pubkey).read();
            assert!(!current.is_member, "Member exists");

            let empty_worker = zero_address();
            self.members.entry(member_pubkey).write(
                MemberInfo { is_member: true, is_active: true, registered_worker: empty_worker }
            );
            self.emit(Event::MemberAdded(MemberAdded { member_pubkey }));
        }

        fn remove_member(ref self: ContractState, member_pubkey: felt252) {
            self.assert_only_admin();
            let current = self.members.entry(member_pubkey).read();
            assert!(current.is_member, "Member missing");

            let old_worker = current.registered_worker;
            let empty_worker = zero_address();
            if old_worker != empty_worker {
                self.worker_to_member.entry(old_worker).write(0);
                self.emit(Event::WorkerUnregistered(WorkerUnregistered {
                    member_pubkey, worker: old_worker
                }));
            }

            self.members.entry(member_pubkey).write(
                MemberInfo { is_member: false, is_active: false, registered_worker: empty_worker }
            );
            self.emit(Event::MemberRemoved(MemberRemoved { member_pubkey }));
        }

        fn set_member_active(ref self: ContractState, member_pubkey: felt252, is_active: bool) {
            self.assert_only_admin();
            let mut current = self.members.entry(member_pubkey).read();
            assert!(current.is_member, "Member missing");
            current.is_active = is_active;
            self.members.entry(member_pubkey).write(current);
            self.emit(Event::MemberActiveSet(MemberActiveSet { member_pubkey, is_active }));
        }

        fn register_worker(
            ref self: ContractState, member_pubkey: felt252, worker: ContractAddress
        ) {
            self.assert_only_admin();
            let empty_worker = zero_address();
            assert!(worker != empty_worker, "Worker is zero");

            let worker_vault = IMemberWorkerAccountDispatcher { contract_address: worker }
                .get_vault();
            assert!(worker_vault == get_contract_address(), "Worker vault mismatch");

            let worker_member_pubkey = IMemberWorkerAccountDispatcher { contract_address: worker }
                .get_member_pubkey();
            assert!(worker_member_pubkey == member_pubkey, "Worker member pubkey mismatch");

            let mut current = self.members.entry(member_pubkey).read();
            assert!(current.is_member, "Member missing");

            let existing = self.worker_to_member.entry(worker).read();
            assert!(
                existing == 0 || existing == member_pubkey,
                "Worker already assigned"
            );

            let old_worker = current.registered_worker;
            if old_worker != empty_worker && old_worker != worker {
                self.worker_to_member.entry(old_worker).write(0);
                self.emit(Event::WorkerUnregistered(WorkerUnregistered {
                    member_pubkey, worker: old_worker
                }));
                self.emit(Event::WorkerRotated(
                    WorkerRotated { member_pubkey, old_worker, new_worker: worker }
                ));
            }

            current.registered_worker = worker;
            self.members.entry(member_pubkey).write(current);
            self.worker_to_member.entry(worker).write(member_pubkey);
            self.emit(Event::WorkerRegistered(WorkerRegistered { member_pubkey, worker }));
        }

        fn allow_token(ref self: ContractState, token: ContractAddress) {
            self.assert_only_admin();
            self.allowed_token.entry(token).write(true);
            self.emit(Event::TokenAllowed(TokenAllowed { token }));
        }

        fn disallow_token(ref self: ContractState, token: ContractAddress) {
            self.assert_only_admin();
            self.allowed_token.entry(token).write(false);
            self.emit(Event::TokenDisallowed(TokenDisallowed { token }));
        }

        fn set_withdraw_limit(
            ref self: ContractState, member_pubkey: felt252, token: ContractAddress, limit: u256
        ) {
            self.assert_only_admin();
            let member = self.members.entry(member_pubkey).read();
            assert!(member.is_member, "Member missing");
            self.withdraw_limit.entry(member_pubkey).entry(token).write(limit);
            self.emit(Event::WithdrawLimitSet(WithdrawLimitSet { member_pubkey, token, limit }));
        }

        fn reset_spent(ref self: ContractState, member_pubkey: felt252, token: ContractAddress) {
            self.assert_only_admin();
            let member = self.members.entry(member_pubkey).read();
            assert!(member.is_member, "Member missing");
            self.withdraw_spent.entry(member_pubkey).entry(token).write(0_u256);
            self.emit(Event::SpentReset(SpentReset { member_pubkey, token }));
        }

        fn pause(ref self: ContractState, paused: bool) {
            self.assert_only_admin();
            self.paused.write(paused);
            self.emit(Event::PausedSet(PausedSet { paused }));
        }

        fn get_admin(self: @ContractState) -> ContractAddress {
            self.admin.read()
        }

        fn is_paused(self: @ContractState) -> bool {
            self.paused.read()
        }

        fn is_allowed_token(self: @ContractState, token: ContractAddress) -> bool {
            self.allowed_token.entry(token).read()
        }

        fn get_withdraw_limit(self: @ContractState, member_pubkey: felt252, token: ContractAddress) -> u256 {
            self.withdraw_limit.entry(member_pubkey).entry(token).read()
        }

        fn get_withdraw_spent(self: @ContractState, member_pubkey: felt252, token: ContractAddress) -> u256 {
            self.withdraw_spent.entry(member_pubkey).entry(token).read()
        }

        fn get_worker_for_member(self: @ContractState, member_pubkey: felt252) -> ContractAddress {
            let member = self.members.entry(member_pubkey).read();
            member.registered_worker
        }

        fn get_member_for_worker(self: @ContractState, worker: ContractAddress) -> felt252 {
            self.worker_to_member.entry(worker).read()
        }

        fn get_member_is_active(self: @ContractState, member_pubkey: felt252) -> bool {
            self.members.entry(member_pubkey).read().is_active
        }

        fn get_member_exists(self: @ContractState, member_pubkey: felt252) -> bool {
            self.members.entry(member_pubkey).read().is_member
        }

        fn transfer_admin(ref self: ContractState, new_admin: ContractAddress) {
            self.assert_only_admin();
            let zero_admin = zero_address();
            assert!(new_admin != zero_admin, "New admin cannot be zero address");
            
            let current_pending = self.pending_admin.read();
            if current_pending != zero_admin {
                self.emit(Event::AdminTransferCancelled(AdminTransferCancelled {
                    cancelled_admin: current_pending,
                    new_pending_admin: new_admin
                }));
            }
            
            self.pending_admin.write(new_admin);
            self.emit(Event::AdminTransferStarted(AdminTransferStarted {
                current_admin: self.admin.read(),
                pending_admin: new_admin
            }));
        }

        fn accept_admin(ref self: ContractState) {
            let pending = self.pending_admin.read();
            let zero_admin = zero_address();
            assert!(pending != zero_admin, "No pending admin");
            assert!(get_caller_address() == pending, "Caller is not pending admin");
            
            let old_admin = self.admin.read();
            self.admin.write(pending);
            self.pending_admin.write(zero_admin);
            self.emit(Event::AdminTransferred(AdminTransferred {
                previous_admin: old_admin,
                new_admin: pending
            }));
        }

        fn get_pending_admin(self: @ContractState) -> ContractAddress {
            self.pending_admin.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_only_admin(self: @ContractState) {
            assert!(get_caller_address() == self.admin.read(), "Caller is not admin");
        }
    }

    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    fn zero_address() -> ContractAddress {
        0.try_into().unwrap()
    }
}


