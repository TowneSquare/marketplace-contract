/*
    - This contract represents the core of the studio.
    - It allows to initialze studio, and correspondingly create collections and tokens.
    - tokens logic is built on top of aptos_token.move.
    - A user can create the following:
        - Collections.
        - Trait token (tNFT): A token V2 that represents a specific trait.
        - Composable token (cNFT): A token V2 that can hold tNFTs inside.
        - <name-token>: A token V2 that can hold tNFTs, cNFTs, and fungible assets.

    TODO: add reference to aptos_token.move
    TODO: add events.
    TODO: add asserts module. (one of the asserts: assert the inputed data is not empty - Input Sanitization?)
    TODO: add init_module? (to initialize the studio with example tokens)
    TODO: enforce #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    TODO: add function to transform a Composable nft into a trait token. (compress?)
    TODO: add functions to add/remove properties to a token.
    TODO: add tokens accessors.
    TODO: add tokens mutators.
    TODO: add tokens view functions.
    TODO: add rarity concept to trait tokens.
    TODO: complete fast compose function. (does this have to be implemented onchain?)
    TODO: in function description, mention whether it's customer or creator specific.
    TODO: REFARCTOR trait token -> object token.
    TODO: re-write create_composable_token_internal, check collection_object inline function.
*/
module townespace::core {

    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::object::{Self, ConstructorRef, Object};
    use aptos_framework::timestamp;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_token_objects::aptos_token;
    use aptos_token_objects::collection;
    use aptos_token_objects::property_map;
    use aptos_token_objects::royalty;
    use aptos_token_objects::token;
    use std::error;
    use std::features;
    use std::option::{Self, Option};
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use townespace::events::{
        CreateTokenCollectionEvent,
        CreateTraitTokenEvent,
        CreateComposableTokenEvent,
        ComposeTokenEvent,
        DecomposeTokenEvent
    };

    /// ------
    /// Errors
    /// ------
    
    /// ---------
    /// Constants
    /// ---------
    // TODO: constants for fast compose function

    /// -------
    /// Structs
    /// -------
    
    // Since the visibility is restricted to the module, we need to clone it.
    // Codebase is cloned from: https://github.com/aptos-labs/aptos-core/blob/1ab0c76609e6620ec972df0ab699c3131b9e610d/aptos-move/framework/aptos-token-objects/sources/aptos_token.move#L34C1-L57C6
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    // Storage state for managing the no-code Collection.
    struct AptosCollection has key {
        // Used to mutate collection fields
        mutator_ref: Option<collection::MutatorRef>,
        // Used to mutate royalties
        royalty_mutator_ref: Option<royalty::MutatorRef>,
        // Determines if the creator can mutate the collection's description
        mutable_description: bool,
        // Determines if the creator can mutate the collection's uri
        mutable_uri: bool,
        // Determines if the creator can mutate token descriptions
        mutable_token_description: bool,
        // Determines if the creator can mutate token names
        mutable_token_name: bool,
        // Determines if the creator can mutate token properties
        mutable_token_properties: bool,
        // Determines if the creator can mutate token uris
        mutable_token_uri: bool,
        // Determines if the creator can burn tokens
        tokens_burnable_by_creator: bool,
        // Determines if the creator can freeze tokens
        tokens_freezable_by_creator: bool,
    }

    // Storage state for managing Token Collection
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenCollection has key {
        name: String,
        symbol: String,
        // TODO: Timestamp?
        // TODO: mint_events
        // TODO: burn_events
    }

    // Storage state for managing Composable token
    // TODO: is property map needed?
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ComposableToken has key {
        collection: String,
        description: String,
        name: String,
        uri: String,
        // Token supply: Represents the number of composable tokens in circulation.
        token_supply: u64,
        // The trait tokens to store in the composable token.
        trait_tokens: vector<Object<TraitToken>>, // TODO: this must be extended to each trait type.
        // TODO: Timestamp
        // TODO: add events
        // Allows to burn the Composable token.
        burn_ref: Option<token::BurnRef>,
        // Controls the transfer of the Composable token.
        transfer_ref: Option<object::TransferRef>,
        // Allows to mutate fields of the Composable token.
        mutator_ref: Option<token::MutatorRef>,
        // Allows to mutate properties of the Composable token.
        property_mutator_ref: property_map::MutatorRef,
        
    }

    // Storage state for managing trait Token
    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TraitToken has key {
        collection: String,
        description: String,
        name: String,
        uri: String,
        // TODO: rarity: u64,
        // TODO: Timestamp
        // TODO: add events
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    // Storage state for tracking composable token supply.
    struct TokenSupplyTracker has key {
        // TODO: supply -> max_supply || total_supply
        supply: u64,
        remaining_supply: u64,
        total_minted: u64,
        // burn_events: ,
        mint_events: EventHandle<CreateTraitTokenEvent>
    }

    // TODO: add rarity struct

    /// ---------------
    /// Entry Functions
    /// ---------------

    // Create a new collection
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
    ) acquires TokenCollection {
        // TODO: asserts here (to reduce gas fees)
        // TODO assert the signer is the creator.
        create_collection_internal(
            creator,
            description,
            max_supply,
            name,
            symbol,
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

    // Mint a composable token
    public entry fun mint_composable_token(
        creator: &signer,
        collection: String,
        description: String,
        name: String,
        uri: String,
        token_supply: u64,  // objects supply must be less or equal to token supply
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
    ) acquires TokenCollection, ComposableToken, AptosCollection {
        // TODO: Assert collection exists
        // TODO: Assert signer is the creator
        // TODO: Assert token supply >= 1
        mint_composable_token_internal(
            creator,
            collection,
            description,
            name,
            uri,
            token_supply,
            property_keys,
            property_types,
            property_values,
        );
    }

    // Mint a trait token
    public entry fun mint_trait_token(
        creator: &signer,
        collection: String,
        description: String,
        name: String,
        uri: String,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
        // composable_token_address: address,
    ) {
        // TODO: assert the token collection exists.
        // TODO: assert the composable token exists.
        // TODO: assert the token supply <= remaining supply
        mint_trait_token_internal(
            creator,
            collection,
            description,
            name,
            uri,
            property_keys,
            property_types,
            property_values,
            // composable_token_address
        )
    }

    // Compose trait in a cNFT.
    // TODO: this should be used in both composable and composite tokens?
    public entry fun compose_trait(
        creator: &signer, 
        composable_token: Object<ComposableToken>,
        object: Object<TraitToken>
    ) acquires ComposableToken {    
        // TODO asserts here.
        compose_trait_internal(creator, composable_token, object);
    }

    // Decompose tokens
    // TODO: this should be used in both composable and composite tokens?
    public entry fun decompose_trait(
        owner: &signer, 
        composable_token: Object<ComposableToken>,
        trait: Object<TraitToken>
    ) acquires ComposableToken {  
        decompose_trait_internal(owner, composable_token, trait);
        // TODO: event here (overal events here, explicit ones in internal)
    }

    // Fast compose function
    /*
        The user can choose two or more trait_tokens to compose,
        this will mint a composable token and transfer the trait_tokens to it.
        The user can later set the properties of the composable token.
    */
    public entry fun fast_compose(
        creator: &signer,
        collection_name: String,
        token_name: String,
        trait_tokens_to_compose: vector<Object<TraitToken>>
    ) acquires TokenCollection, AptosCollection {
        let property_keys = vector::empty<String>();
        let property_types = vector::empty<String>();
        let property_values = vector::empty<vector<u8>>();

        // TODO: Mint a composable token with constant properties.
        fast_compose_internal(
        creator,
        collection_name,
        string::utf8(b"Fast composed"), // description
        token_name,
        string::utf8(b"uri"), 
        10000,  // token supply
        trait_tokens_to_compose,
        property_keys,
        property_types,
        property_values,
        );
        let i = 0;
        while (i < vector::length(&trait_tokens_to_compose)) {
            // vector::borrow returns &Element, so we need to dereference it.
            let object = *vector::borrow(&trait_tokens_to_compose, i);
            // TODO assert token exists
            // TODO: Freeze transfer.
            aptos_token::freeze_transfer(creator, object);
            i = i + 1;
        }
    }
        
    // TODO: Delete a composable token
    /*
        steps:
        - Decomposes the composable token
        - Burns the composable token

        params:
    */
    public entry fun burn_composable_token(

    ) {
        // TODO assert token exists

    }

    // TODO: freeze transfer
    /*
        TODO: - should the user interact directly with aptos_token.move?
    */

    // Transfer function
    public entry fun raw_transfer(
        owner: &signer, 
        trait_address: address,
    ) {
        // TODO assert token exists
        // TODO: Assert transfer is unfreezed (trait not equiped to composable nft)
        // TODO: Assert the signer is the trait owner
        let owner_address = signer::address_of(owner);
        // Transfer
        let trait = object::address_to_object<TraitToken>(trait_address);
        object::transfer(owner, trait, owner_address);
        // TODO: event
    }

    // Transfer with a fee function
    public entry fun transfer_with_fee(
        owner: &signer, 
        trait_address: address,
    ) {
        // TODO assert token exists
        // TODO: Assert transfer is unfreezed (object not equiped to composable nft)
        // TODO: Assert the signer is the object owner
        let owner_address = signer::address_of(owner);
        // TODO: Include a small fee
        // Transfer
        let trait_token = object::address_to_object<TraitToken>(trait_address);
        object::transfer(owner, trait_token, owner_address);
        // TODO: event
    }

    /// ------------------
    /// Internal Functions
    /// ------------------
    
    // Collection 
    fun create_collection_internal(
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
    ) acquires TokenCollection {
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
        let creator_address = signer::address_of(creator);
        let collection = borrow_global_mut<TokenCollection>(creator_address);

        let collection_name = collection.name;
        // Move to resource account.
        let new_token_collection = TokenCollection {
            name: collection_name,
            symbol: symbol,
            // TODO: see what other attributes to include
        };
        move_to(creator, new_token_collection);

        // TODO Add events
    }

    // Mint a composable token
    // Cannot be entry as we are returning object.
    /*
        The user have two or more trait tokens and wants to compose them,
        to do so, the user has to use this function.
        This will mint a new composable token and compose the trait_tokens.
        - The user has to specify the composable token's attributes.
        - The user has to specify which trait_tokens to compose.
        - params:
        
    */
    fun mint_composable_token_internal(
        creator: &signer,
        collection: String,
        description: String,
        name: String,
        uri: String,
        token_supply: u64,  // objects supply must be less or equal to token supply
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
    ): Object<ComposableToken> acquires TokenCollection, ComposableToken, AptosCollection {  
        let constructor_ref = create_composable_token_internal(
            creator,
            collection,
            description,
            name,
            uri,
            token_supply,
            vector::empty(),
            property_keys,
            property_types,
            property_values,
        );

        let collection = collection_object(creator, &collection);
        // TODO: check if this function is not written.
        // Asserts the creator is the owner of the collection.
        
        // If tokens are freezable, add a transfer ref to be able to freeze transfers
        let freezable_by_creator = aptos_token::are_collection_tokens_freezable(collection);
        if (freezable_by_creator) {
            let composable_token_address = object::address_from_constructor_ref(&constructor_ref);
            let composable_token = borrow_global_mut<ComposableToken>(composable_token_address);
            let transfer_ref = object::generate_transfer_ref(&constructor_ref);
            option::fill(&mut composable_token.transfer_ref, transfer_ref);
        };

        object::object_from_constructor_ref(&constructor_ref)

        // TODO: event composable token minted
    }

    fun fast_compose_internal(
        creator: &signer,
        collection_name: String,
        description: String,
        name: String,
        uri: String,
        token_supply: u64,  // objects supply must be less or equal to token supply
        trait_tokens_to_compose: vector<Object<TraitToken>>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
    ): Object<ComposableToken> acquires TokenCollection, AptosCollection {
        // TODO: create composable token
        let constructor_ref = create_composable_token_internal(
            creator,
            collection_name,
            description,
            name,
            uri,
            token_supply,
            trait_tokens_to_compose,
            property_keys,
            property_types,
            property_values,
        );

        // Return the composable token object
        object::object_from_constructor_ref(&constructor_ref)
    }

    // Trait token
    fun mint_trait_token_internal(
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
        // TODO move to trait token resource
        let new_trait_token = TraitToken {
            collection: collection,
            description: description,
            name: name,
            uri: uri,
        };
        move_to(creator, new_trait_token);
        // TODO: event trait token minted
    }

    // Compose trait
    fun compose_trait_internal(
        creator: &signer, 
        composable_token: Object<ComposableToken>,
        object: Object<TraitToken>
    ) acquires ComposableToken {
        // TODO assert token exists
        let creator_address = signer::address_of(creator);
        let composable_token_trait = borrow_global_mut<ComposableToken>(object::object_address(&composable_token)); 
        
        // index = vector length
        let index = vector::length(&composable_token_trait.trait_tokens);
        // TODO: Assert transfer is not freezed (object not equiped to composable nft)
        // TODO: Assert the signer is the owner 
        // TODO: Assert the object does not exist in the composable token

        
        // TODO: add the object to the vector
        vector::insert<Object<TraitToken>>(&mut composable_token_trait.trait_tokens, index, object);
        // TODO: Transfer the object to the composable token
        object::transfer_to_object(creator, object, composable_token);
        // Freeze transfer
        aptos_token::freeze_transfer(creator, object);
        // TODO: event here (overall events here, explicit ones in internal) 
    }

    // Decompose trait
    fun decompose_trait_internal(
        owner: &signer,
        composable_token: Object<ComposableToken>,
        trait: Object<TraitToken>
    ) acquires ComposableToken {
        // TODO assert token exists
        let composable_token_trait = borrow_global_mut<ComposableToken>(object::object_address(&composable_token)); 
        // TODO: get the index "i" of the object. Prob use borrow and inline funcs
        // TODO: store it in i
        // pattern matching
        let (_, index) = vector::index_of(&composable_token_trait.trait_tokens, &trait);
        // TODO: assert the object exists in the composable token
        // Unfreeze transfer
        aptos_token::unfreeze_transfer(owner, trait);
        // Remove the object from the vector
        vector::remove<Object<TraitToken>>(&mut composable_token_trait.trait_tokens, index);
        // Transfer
        object::transfer(owner, trait, signer::address_of(owner));
        // TODO: events
    }
    
    // Composable token
    // TODO: fix link. Logic cloned from: https://github.com/aptos-labs/aptos-core/blob/3791dc07ec457496c96e5069c494d46c1ff49b41/aptos-move/framework/aptos-token-objects/sources/aptos_token.move#L36C1-L36C1
    fun create_composable_token_internal(
        creator: &signer,
        collection: String,
        description: String,
        name: String,
        uri: String,
        token_supply: u64,
        trait_tokens: vector<Object<TraitToken>>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
    ): ConstructorRef acquires AptosCollection, TokenCollection {
        let constructor_ref = if (features::auids_enabled()) {
            token::create(
                creator,
                collection,
                description,
                name,
                option::none(),
                uri,
            )
        } else {
            token::create_from_account(
                creator,
                collection,
                description,
                name,
                option::none(),
                uri,
            )
        };

        let object_signer = object::generate_signer(&constructor_ref);

        let collection_obj = collection_object(creator, &collection);
        let collection = borrow_collection(&collection_obj);

        let mutator_ref = if (
            collection.mutable_token_description
                || collection.mutable_token_name
                || collection.mutable_token_uri
        ) {
            option::some(token::generate_mutator_ref(&constructor_ref))
        } else {
            option::none()
        };

        let burn_ref = if (collection.tokens_burnable_by_creator) {
            option::some(token::generate_burn_ref(&constructor_ref))
        } else {
            option::none()
        };

        let creator_address = signer::address_of(creator);
        let collection = borrow_global_mut<TokenCollection>(creator_address);

        let collection_name = collection.name;

        // create send supply tracker to resource account
        let new_token_supply_tracker = TokenSupplyTracker {
            supply: token_supply,
            remaining_supply: token_supply,
            total_minted: 0,
            mint_events: object::new_event_handle(&object_signer),
        };
        move_to(&object_signer, new_token_supply_tracker);

        // Initialize it with trait_tokens vector if it exists. Empty otherwise.
        if (vector::length(&trait_tokens) == 0) {
            let new_composable_token = ComposableToken {
            collection: collection_name,
            description: description,
            name: name,
            uri: uri, 
            token_supply: token_supply, 
            trait_tokens: vector::empty(),
            burn_ref,
            transfer_ref: option::none(),
            mutator_ref,
            property_mutator_ref: property_map::generate_mutator_ref(&constructor_ref),
        };
        move_to(&object_signer, new_composable_token);
        } else {
            let new_composable_token = ComposableToken {
            collection: collection_name,
            description: description,
            name: name,
            uri: uri,
            token_supply: token_supply,  
            trait_tokens: trait_tokens,
            burn_ref,
            transfer_ref: option::none(),
            mutator_ref,
            property_mutator_ref: property_map::generate_mutator_ref(&constructor_ref),
        };
        move_to(&object_signer, new_composable_token);
        };

        let properties = property_map::prepare_input(property_keys, property_types, property_values);
        property_map::init(&constructor_ref, properties);

        constructor_ref
    }
     
    // Decrement the remaining supply on each trait token minted.
    fun decrement_supply(
        composable_token: &Object<ComposableToken>,
        trait_token: address
    ): u64 acquires TokenSupplyTracker {
        // TODO: assert the composable token exists.
        // TODO: assert the trait token exists.
        let composable_token_address = object::object_address(composable_token);
        let composable_token_supply_tracker = borrow_global_mut<TokenSupplyTracker>(composable_token_address);
        let remaining_supply = composable_token_supply_tracker.remaining_supply;
        // TODO: assert the remaining supply > 0.
        let new_remaining_supply = remaining_supply - 1;
        composable_token_supply_tracker.remaining_supply = new_remaining_supply;

        new_remaining_supply
    }

    // TODO: Increment the remaining supply on each trait token burned.
     
    // TODO: calculate rarity

    /// --------------
    /// View Functions
    /// --------------

    /// --------
    /// Mutators
    /// --------

    /// ---------
    /// Accessors
    /// ---------

    // Collection
    inline fun collection_object(creator: &signer, name: &String): Object<aptos_token::AptosCollection> {
        let collection_addr = collection::create_collection_address(&signer::address_of(creator), name);
        object::address_to_object<aptos_token::AptosCollection>(collection_addr)
    }

    inline fun borrow_collection<T: key>(token: &Object<T>): &AptosCollection {
        let collection_address = object::object_address(token);
        assert!(
            exists<AptosCollection>(collection_address),
            error::not_found(1), // ECOLLECTION_DOES_NOT_EXIST
        );
        borrow_global<AptosCollection>(collection_address)
    }
    
}