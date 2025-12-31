use starknet::ContractAddress;

#[starknet::interface]
pub trait IWorker<TContractState> {
    fn get_vault(self: @TContractState) -> ContractAddress;
}

