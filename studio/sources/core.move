/*
    - This contract is the core of the studio.
    - It is built on top of aptos_token.move.
    - A user can mint the following:
        - Plain token: a token V2.
        - Dynamic token: composed of two or more plain tokens.
        - Composed token: TBA.
        - Collections.

    TODO: freeze transfer after minting.
    TODO: add events.
    TODO: add asserts.
*/
module studio_addr::token {

    use aptos_framework::object::{Self, ConstructorRef, Object};
    use aptos_token_objects::aptos_token;
    use aptos_token_objects::collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::token;

    use std::features;
    use std::option::{Self, Option};
    use std::signer;
    use std::string::{Self, String};

    /*
    Errors
    */

    /*
    Structs
    */ 

    // To manage collection name and symbol onchain.
    struct Config has key {
        name: String,
        symbol: String,
    }

    // Dynamic token
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct DynamicToken has key {
        name: String,
        // The elements of the dynamic token.
        object_one: Option<Object<aptos_token::AptosToken>>,
        object_two: Option<Object<aptos_token::AptosToken>>,
        object_three: Option<Object<aptos_token::AptosToken>>,
        object_four: Option<Object<aptos_token::AptosToken>>,
        // Allows to burn the dynamic token.
        burn_ref: Option<token::BurnRef>,
        // Controls the transfer of the dynamic token.
        transfer_ref: Option<object::TransferRef>,
        // Allows to mutate fields of the dynamic token.
        mutator_ref: Option<token::MutatorRef>,
        // Allows to mutate properties of the dynamic token.
        property_mutator_ref: property_map::MutatorRef,
    }

    /*
    Entry Functions
    */

    // Create a new collection
    // TODO: double check if encapsulation is really needed here.
    public entry fun create_collection(
        creator: &signer,
        description: String,
        max_supply: u64,
        name: String,
        symbol: String,
        uri: String,
        mutable_description: bool,
        mutable_royalty: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_freezable_by_creator: bool,
        royalty_numerator: u64,
        royalty_denominator: u64,
    ) {
        create_collection_internal(
            creator,
            description,
            max_supply,
            name,
            uri,
            mutable_description,
            mutable_royalty,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_freezable_by_creator,
            royalty_numerator,
            royalty_denominator,
        );

        // Move the created object to the resource account.
        let new_collection = Config {
            name,
            symbol,
        };
        move_to(creator, new_collection);
    }

    fun create_collection_internal(
        creator: &signer,
        description: String,
        max_supply: u64,
        name: String,
        uri: String,
        mutable_description: bool,
        mutable_royalty: bool,
        mutable_uri: bool,
        mutable_token_description: bool,
        mutable_token_name: bool,
        mutable_token_properties: bool,
        mutable_token_uri: bool,
        tokens_burnable_by_creator: bool,
        tokens_freezable_by_creator: bool,
        royalty_numerator: u64,
        royalty_denominator: u64,
    ) {
        // TODO assert the signer is the creator.
        aptos_token::create_collection(
            creator,
            description,
            max_supply,
            name,
            uri,
            mutable_description,
            mutable_royalty,
            mutable_uri,
            mutable_token_description,
            mutable_token_name,
            mutable_token_properties,
            mutable_token_uri,
            tokens_burnable_by_creator,
            tokens_freezable_by_creator,
            royalty_numerator,
            royalty_denominator,
        );
    }

    // Mint a plain token
    // TODO: double check if encapsulation is really needed here.
    public entry fun mint_plain_token(
        creator: &signer,
        collection: String,
        description: String,
        name: String,
        uri: String,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
    ) {
        // TODO asserts
        mint_plain_token_internal(
            creator,
            collection,
            description,
            name,
            uri,
            property_keys,
            property_types,
            property_values,
        )
    }

    fun mint_plain_token_internal(
        creator: &signer,
        collection: String,
        description: String,
        name: String,
        uri: String,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
    ) {
        aptos_token::mint(
            creator,
            collection,
            description,
            name,
            uri,
            property_keys,
            property_types,
            property_values,
        );
    }

    // Mint a dynamic token
    // TODO: should this be entry?
    public entry fun mint_dynamic_token(
        creator: &signer,
        collection: String,
        description: String,
        name: String,
        uri: String,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
    ) {
        mint_dynamic_token_internal(
            creator,
            collection,
            description,
            name,
            uri,
            property_keys,
            property_types,
            property_values,
        )
    }

    fun mint_dynamic_token_internal(
        creator: &signer,
        collection: String,
        description: String,
        name: String,
        uri: String,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,        
    ) {
        aptos_token::mint(
            creator,
            collection,
            description,
            name,
            uri,
            property_keys,
            property_types,
            property_values,
        );
    }

    // Combine object.
    // TODO: this should be used in both dynamic and composite tokens?
    public entry fun combine_object(
        creator: &signer, 
        dynamic_token: Object<DynamicToken>,
        object_one: Object<aptos_token::AptosToken>
    ) acquires DynamicToken {    
        let dynamic_token_obj = borrow_global_mut<DynamicToken>(object::object_address(&dynamic_token)); 
        
        // TODO: Wrap up in a transfer function
        // Unfreeze transfer
        aptos_token::unfreeze_transfer(creator, object_one);
        // Transfer
        option::fill(&mut dynamic_token_obj.object_one, object_one);
        object::transfer_to_object(creator, object_one, dynamic_token);
        // Freeze transfer
        aptos_token::freeze_transfer(creator, object_one);
    }

    // Uncombine tokens
    // TODO: this should be used in both dynamic and composite tokens?
    public entry fun uncombine_object(
        creator: &signer, 
        dynamic_token: Object<DynamicToken>,
        object_one: Object<aptos_token::AptosToken>
    ) acquires DynamicToken {    
        let dynamic_token_obj = borrow_global_mut<DynamicToken>(object::object_address(&dynamic_token)); 
        let stored_object_one = option::extract(&mut dynamic_token_obj.object_one);

        // TODO: Wrap up in a transfer function
        // Unfreeze transfer
        aptos_token::unfreeze_transfer(creator, stored_object_one);
        // Transfer
        object::transfer(creator, stored_object_one, signer::address_of(creator));
        // TODO: asserts
        // Freeze transfer
        aptos_token::freeze_transfer(creator, stored_object_one);
    }

    // TODO: Transfer functions

    /*
    View Functions
    */

    /*
    Mutators
    */
    
}