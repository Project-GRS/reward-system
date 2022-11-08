//! Contract to pay tokens as reward in Aptos
//! Created by Project-grs
module rewardsystem::tokenrewardsystem
{
    use std::signer;
    use std::string::{String,append};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_token::token::{Self,balance_of,direct_transfer};
    use aptos_std::type_info;
    use aptos_std::simple_map::{Self, SimpleMap};
    use std::bcs::to_bytes;

    struct Rewardsystem has key {
        game:String,
        //reward paid per point
        rewardperpoint:u64,
        //the statust of the rewardsystem can be turned of by the creator to stop payments
        state:bool,
        //the amount stored in the vault to distribute for token rewardsystem
        amount:u64,
        //the coin_type in which the rewardsystem rewards are paid
        coin_type:address, 
        //treasury_cap
        treasury_cap:account::SignerCapability,
    }

    struct ResourceInfo has key {
        resource_map: SimpleMap< String,address>,
    }
    const ENO_NO_GAME:u64=0;
    const ENO_REWARDSYSTEM_EXISTS:u64=1;
    const ENO_NO_REWARDSYSTEM:u64=2;
    const ENO_STOPPED:u64=3;
    const ENO_COINTYPE_MISMATCH:u64=4;
    const ENO_INSUFFICIENT_FUND:u64=5;


    //Functions    
    //Function for creating and modifying rewardsystem
    public entry fun create_reward_system<CoinType>(
        creator: &signer,
        rewardperpoint:u64,//rate of payment,
        game_name:String, //the name of the game owned by Creator 
        total_amount:u64,
    ) acquires ResourceInfo{
        let creator_addr = signer::address_of(creator);
        //verify the creator has the game
        assert!(check_game_exists(creator_addr,game_name), ENO_NO_GAME);
        //
        let (rewardsystem_treasury, rewardsystem_treasury_cap) = account::create_resource_account(creator, to_bytes(&game_name)); //resource account to store funds and data
        let rewardsystem_treasur_signer_from_cap = account::create_signer_with_capability(&rewardsystem_treasury_cap);
        let rewardsystem_address = signer::address_of(&rewardsystem_treasury);
        assert!(!exists<Rewardsystem>(rewardsystem_address),ENO_REWARDSYSTEM_EXISTS);
        create_add_resource_info(creator,game_name,rewardsystem_address);
        managed_coin::register<CoinType>(&rewardsystem_treasur_signer_from_cap); 
        //the creator need to make sure the coins are sufficient otherwise the contract
        //turns off the state of the rewardsystem
        coin::transfer<CoinType>(creator,rewardsystem_address, total_amount);
        move_to<Rewardsystem>(&rewardsystem_treasur_signer_from_cap, Rewardsystem{
        game: game_name,
        rewardperpoint:rewardperpoint,
        state:true,
        amount:total_amount,
        coin_type:coin_address<CoinType>(), 
        treasury_cap:rewardsystem_treasury_cap,
        });
    }
    public entry fun update_rewardperpoint(
        creator: &signer,
        rewardperpoint:u64,//rate of payment,
        game_name:String, //the name of the game owned by Creator 
    )acquires Rewardsystem,ResourceInfo 
    {
        let creator_addr = signer::address_of(creator);
        //verify the creator has the game
        assert!(check_game_exists(creator_addr,game_name), ENO_NO_GAME);
        //get rewardsystem address
        let rewardsystem_address = get_resource_address(creator_addr,game_name);
        assert!(exists<Rewardsystem>(rewardsystem_address),ENO_NO_REWARDSYSTEM);// the rewardsystem doesn't exists
        let rewardsystem_data = borrow_global_mut<Rewardsystem>(rewardsystem_address);
        //let rewardsystem_treasur_signer_from_cap = account::create_signer_with_capability(&rewardsystem_data.treasury_cap);
        rewardsystem_data.rewardperpoint=rewardperpoint;
    }
    public entry fun creator_stop_rewardsystem(
        creator: &signer,
        game_name:String, //the name of the game owned by Creator 
    )acquires Rewardsystem,ResourceInfo
    {
        let creator_addr = signer::address_of(creator);
        //verify the creator has the game
        assert!(check_game_exists(creator_addr,game_name), ENO_NO_GAME);
        //
       //get rewardsystem address
        let rewardsystem_address = get_resource_address(creator_addr,game_name);
        assert!(exists<Rewardsystem>(rewardsystem_address),ENO_NO_REWARDSYSTEM);// the rewardsystem doesn't exists
        let rewardsystem_data = borrow_global_mut<Rewardsystem>(rewardsystem_address);
        rewardsystem_data.state=false;
    }
    public entry fun deposit_rewardsystem_rewards<CoinType>(
        creator: &signer,
        game_name:String, //the name of the game owned by Creator 
        amount:u64,
    )acquires Rewardsystem,ResourceInfo
    {
        let creator_addr = signer::address_of(creator);
        //verify the creator has the game
        assert!(check_game_exists(creator_addr,game_name), ENO_NO_GAME);
        //
         assert!(exists<ResourceInfo>(creator_addr), ENO_NO_REWARDSYSTEM);
        let rewardsystem_address = get_resource_address(creator_addr,game_name);        let rewardsystem_data = borrow_global_mut<Rewardsystem>(rewardsystem_address);
        //the creator need to make sure the coins are sufficient otherwise the contract
        //turns off the state of the rewardsystem
        assert!(coin_address<CoinType>()==rewardsystem_data.coin_type,ENO_COINTYPE_MISMATCH);
        coin::transfer<CoinType>(creator,rewardsystem_address, amount);
        rewardsystem_data.amount= rewardsystem_data.amount+amount;
        
    }
    //Function for getting reward
    public entry fun claim_reward<CoinType>(
        gamer:&signer, 
        game_name:String, //the name of the game owned by Creator 
        points:u64,
        creator:address,
    ) acquires Rewardsystem,ResourceInfo{
        let gamer_adr = signer::address_of(gamer);
        //verifying whether the creator has started the rewardsystem or not
        let rewardsystem_address = get_resource_address(creator,game_name);
        assert!(exists<Rewardsystem>(rewardsystem_address),ENO_NO_REWARDSYSTEM);// the rewardsystem doesn't exists
        let rewardsystem_data = borrow_global_mut<Rewardsystem>(rewardsystem_address);
        let rewardsystem_treasur_signer_from_cap = account::create_signer_with_capability(&rewardsystem_data.treasury_cap);
        assert!(rewardsystem_data.state,ENO_STOPPED);
        let rewardperpoint = rewardsystem_data.rewardperpoint;
        let release_amount = points * rewardsystem_data.rewardperpoint;
        assert!(coin_address<CoinType>()==rewardsystem_data.coin_type,ENO_COINTYPE_MISMATCH);
        if (rewardsystem_data.amount<release_amount)
        {
            rewardsystem_data.state=false;
            assert!(rewardsystem_data.amount>release_amount,ENO_INSUFFICIENT_FUND);
        };
        if (!coin::is_account_registered<CoinType>(gamer_adr))
        {managed_coin::register<CoinType>(gamer); 
        };
        coin::transfer<CoinType>(&rewardsystem_treasur_signer_from_cap,gamer_adr,release_amount);
        rewardsystem_data.amount=rewardsystem_data.amount-release_amount;
    }
     /// A helper functions
    fun coin_address<CoinType>(): address {
        let type_info = type_info::type_of<CoinType>();
        type_info::account_address(&type_info)
    }
    fun create_add_resource_info(account:&signer,string:String,resource:address) acquires ResourceInfo
    {
        let account_addr = signer::address_of(account);
        if (!exists<ResourceInfo>(account_addr)) {
            move_to(account, ResourceInfo { resource_map: simple_map::create() })
        };
        let maps = borrow_global_mut<ResourceInfo>(account_addr);
        simple_map::add(&mut maps.resource_map, string,resource);
    }
    fun get_resource_address(add1:address,string:String): address acquires ResourceInfo
    {
        assert!(exists<ResourceInfo>(add1), ENO_NO_REWARDSYSTEM);
        let maps = borrow_global<ResourceInfo>(add1);
        let rewardsystem_address = *simple_map::borrow(&maps.resource_map, &string);
        rewardsystem_address

    }



