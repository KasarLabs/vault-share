use starknet::ContractAddress;

#[starknet::interface]
pub trait IMockERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
}

#[starknet::contract]
pub mod MockERC20 {
    use starknet::storage::*;
    use starknet::ContractAddress;

    #[storage]
    pub struct Storage {
        balances: Map<ContractAddress, u256>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    pub impl MockERC20Impl of super::IMockERC20<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.entry(account).read()
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = starknet::get_caller_address();
            let sender_bal = self.balances.entry(sender).read();
            let zero: u256 = 0_u256;
            assert!(amount >= zero, "Amount underflow");
            assert!(sender_bal >= amount, "Insufficient balance");

            self.balances.entry(sender).write(sender_bal - amount);
            let rec_bal = self.balances.entry(recipient).read();
            self.balances.entry(recipient).write(rec_bal + amount);
            true
        }

        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let cur = self.balances.entry(recipient).read();
            self.balances.entry(recipient).write(cur + amount);
        }
    }
}


