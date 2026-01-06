#[starknet::interface]
pub trait IMemberWorkerAccount<TContractState> {
    fn get_vault(self: @TContractState) -> starknet::ContractAddress;
    fn get_member_pubkey(self: @TContractState) -> felt252;
    fn set_vault(ref self: TContractState, vault: starknet::ContractAddress);
}

#[starknet::contract(account)]
pub mod MemberWorkerAccount {
    use core::traits::TryInto;
    use openzeppelin_account::AccountComponent;
    use openzeppelin_account::extensions::SRC9Component;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::*;

    component!(path: AccountComponent, storage: account, event: AccountEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: SRC9Component, storage: src9, event: SRC9Event);

    // External
    #[abi(embed_v0)]
    impl AccountMixinImpl = AccountComponent::AccountMixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl OutsideExecutionV2Impl = SRC9Component::OutsideExecutionV2Impl<ContractState>;

    // Internal
    impl AccountInternalImpl = AccountComponent::InternalImpl<ContractState>;
    impl OutsideExecutionInternalImpl = SRC9Component::InternalImpl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        account: AccountComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        src9: SRC9Component::Storage,
        // Custom fields for worker account
        vault: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccountEvent: AccountComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        SRC9Event: SRC9Component::Event,
    }

#[constructor]
fn constructor(ref self: ContractState, public_key: felt252) {
    assert!(public_key != 0, "Pubkey is zero");
    self.account.initializer(public_key);
    self.src9.initializer();
}

    #[abi(embed_v0)]
    pub impl MemberWorkerAccountImpl of super::IMemberWorkerAccount<ContractState> {
        fn get_vault(self: @ContractState) -> ContractAddress {
            self.vault.read()
        }

        fn get_member_pubkey(self: @ContractState) -> felt252 {
            AccountMixinImpl::get_public_key(self)
        }

        fn set_vault(ref self: ContractState, vault: ContractAddress) {
            let zero: ContractAddress = 0.try_into().unwrap();
            assert!(vault != zero, "Vault is zero");
            self.vault.write(vault);
        }
    }

    
}
