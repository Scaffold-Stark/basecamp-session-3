use core::starknet::{ContractAddress};

#[starknet::interface]
trait ICrowdFund<TContractState> {
    fn create_campaign(
        ref self: TContractState, end_at: u256, goal: u256
    ); // 创建一个众筹活动

    fn donate(ref self: TContractState, campaign_id: u256, amount: u256);
    fn claim(ref self: TContractState, campaign_id: u256);
    fn redeem(ref self: TContractState, campaign_id: u256);

    // getters
    fn get_campaign(self: @TContractState, campaign_id: u256) -> CrowdFund::Campaign;
    fn get_user_donations(
        self: @TContractState, campaign_id: u256, user_address: ContractAddress
    ) -> u256;
}

#[starknet::contract]
mod CrowdFund {
    use core::num::traits::Zero;
    use super::ICrowdFund;
    use core::starknet::{
        ContractAddress, get_caller_address, get_block_timestamp, get_contract_address
    };
    use starknet::storage::{Map, StoragePathEntry};
    use openzeppelin_token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
    use openzeppelin_access::ownable::OwnableComponent;


    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);


    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;

    // transfer_from
    // transferFrom

    #[storage]
    struct Storage {
        campaign_id: u256,
        campaigns: Map<u256, Campaign>,
        eth_dispatcher: IERC20CamelDispatcher,
        // user address -> campaign id -> amount
        user_donations: Map<ContractAddress, Map<u256, u256>>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CampaignDonated: CampaignDonated,
        #[flat]
        OwnableEvent: OwnableComponent::Event
    }

    // indexed

    #[derive(Drop, starknet::Event)]
    pub struct CampaignDonated {
        #[key]
        campaign_id: u256,
        #[key]
        creator: ContractAddress,
        goal: u256,
        end_at: u256
    }

    #[constructor]
    fn constructor(ref self: ContractState, eth_address: ContractAddress) {
        self.eth_dispatcher.write(IERC20CamelDispatcher { contract_address: eth_address });
    }


    // struct -> array [creator, goal, ..], [creator, goal, ..] -> struct
    #[derive(Drop, Serde, starknet::Store)]
    pub struct Campaign {
        creator: ContractAddress,
        goal: u256,
        amount_donated: u256,
        end_at: u256,
        claimed: bool
    }

    #[abi(embed_v0)]
    impl CroundFund of ICrowdFund<ContractState> {
        fn create_campaign(ref self: ContractState, end_at: u256, goal: u256) {
            assert!(end_at > 0, "End at must be greater than 0");
            // create campaign struct
            // insert to contract state

            let campaign_id = self.campaign_id.read() + 1; // 1
            self.campaign_id.write(campaign_id);

            // id -> campaign
            self
                .campaigns
                .entry(campaign_id)
                .write(
                    Campaign {
                        creator: get_caller_address(),
                        goal: goal,
                        amount_donated: 0,
                        end_at: get_block_timestamp().into() + end_at,
                        claimed: false
                    }
                );
            // todo: emit event
        }

        fn donate(ref self: ContractState, campaign_id: u256, amount: u256) {
            let mut campaign = self.get_campaign(campaign_id);
            assert!(amount > 0, "Amount must be greater than 0");

            // block.timestamp < campaign.endAt

            // campaign.creator != address(0)
            assert!(!campaign.creator.is_zero(), "Campaign not found");

            // caller transfer this contract

            // IERC20(token_address).transfer_from

            // bug
            let success = self
                .eth_dispatcher
                .read()
                .transferFrom(get_caller_address(), get_contract_address(), amount);

            assert!(success, "Transfer failed");
            // user -> campaign -> donate了多少钱

            // 用户透的钱
            let new_user_donations = self
                .user_donations
                .entry(get_caller_address())
                .entry(campaign_id)
                .read()
                + amount;
            self
                .user_donations
                .entry(get_caller_address())
                .entry(campaign_id)
                .write(new_user_donations);

            // 更新 campaign 的 amount_donated
            campaign.amount_donated += amount;

            let creator = campaign.creator;
            let goal = campaign.goal;
            let end_at = campaign.end_at;

            self.campaigns.entry(campaign_id).write(campaign);

            self
                .emit(
                    CampaignDonated {
                        campaign_id: campaign_id, creator: creator, goal: goal, end_at: end_at
                    }
                );
        }

        fn claim(ref self: ContractState, campaign_id: u256) {
            let mut campaign = self.get_campaign(campaign_id);
            assert!(campaign.claimed == false, "Campaign already claimed");
            assert!(campaign.amount_donated >= campaign.goal, "Goal not reached");
            assert!(get_block_timestamp().into() >= campaign.end_at, "Campaign not ended");

            campaign.claimed = true;

            let amount = campaign.amount_donated;
            let creator = campaign.creator;

            self.campaigns.entry(campaign_id).write(campaign);

            let result = self.eth_dispatcher.read().transfer(creator, amount);

            assert!(result, "Transfer failed");
            // emit event
        }

        fn redeem(ref self: ContractState, campaign_id: u256) {
            let mut campaign = self.get_campaign(campaign_id);
            assert!(campaign.claimed == false, "Campaign already claimed");
            assert!(get_block_timestamp().into() > campaign.end_at, "Campaign not ended");
            assert!(campaign.amount_donated < campaign.goal, "Goal already reached");

            // 退钱
            // user -> campaign -> amount
            let amount = self.user_donations.entry(get_caller_address()).entry(campaign_id).read();
            self.user_donations.entry(get_caller_address()).entry(campaign_id).write(0);

            let result = self.eth_dispatcher.read().transfer(get_caller_address(), amount);
            assert!(result)
        }

        fn get_campaign(self: @ContractState, campaign_id: u256) -> Campaign {
            self.campaigns.entry(campaign_id).read()
        }

        fn get_user_donations(
            self: @ContractState, campaign_id: u256, user_address: ContractAddress
        ) -> u256 {
            self.user_donations.entry(user_address).entry(campaign_id).read()
        }
    }
}
