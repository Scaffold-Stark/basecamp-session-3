#[starknet::interface]
trait ICounter<TContractState> {
    // all public functions

    // TODO: experiment for view and external

    // view, external
    fn get_counter(self: @TContractState) -> u256;
    // increment
    fn increment(ref self: TContractState);

    fn get_increment_but_inrease(
        self: @TContractState, invoke_counter_address: ContractAddress
    ) -> u256;
}


use core::starknet::{ContractAddress};

#[starknet::interface]
trait IInvokeCounter<TContractState> {
    fn invoke_counter(ref self: TContractState, counter_address: ContractAddress);
}

#[starknet::contract]
mod InvokeCounter {
    use super::{ICounterDispatcher, ICounterDispatcherTrait, IInvokeCounter};
    use core::starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl InvokeCounter of IInvokeCounter<ContractState> {
        fn invoke_counter(ref self: ContractState, counter_address: ContractAddress) {
            let counter_dispatcher = ICounterDispatcher { contract_address: counter_address };

            counter_dispatcher.increment();
        }
    }
}


#[starknet::contract]
mod Counter {
    use super::{IInvokeCounterDispatcher, IInvokeCounterDispatcherTrait};
    use super::ICounter;
    use core::starknet::{ContractAddress, get_contract_address};

    #[storage]
    struct Storage {
        counter: u256
    }
    // public functions?
    // increment counter
    // get counter

    #[constructor]
    fn constructor(ref self: ContractState, initial_counter: u256) {
        self.counter.write(initial_counter);
    }

    #[abi(embed_v0)]
    impl Counter of ICounter<ContractState> {
        fn get_counter(self: @ContractState) -> u256 {
            self.counter.read()
        }

        fn increment(ref self: ContractState) {
            self._increment(1);
        }

        fn get_increment_but_inrease(
            self: @ContractState, invoke_counter_address: ContractAddress
        ) -> u256 {
            // 在这里 我去跳动InvokeCounter.invoke_counter

            let invoke_counter_dispatcher = IInvokeCounterDispatcher {
                contract_address: invoke_counter_address
            };
            invoke_counter_dispatcher.invoke_counter(get_contract_address());

            self.counter.read()
        }
    }

    #[external(v0)]
    fn increment_five(ref self: ContractState) {
        self._increment(5);
    }

    // private functions?
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _increment(ref self: ContractState, amount: u256) {
            self.counter.write(self.counter.read() + amount)
        }
    }
}
