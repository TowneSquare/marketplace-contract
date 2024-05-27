/*

    TODO: 
        - smart tables holding the tokens to mint must have size pre-defined?
        - create tokens ready for mint can be the same as in unveil
        - refactor module name; must be more accurate
        - Add a global storage for the tracking tokens supply per type
*/

module townespace::random_mint {

    use aptos_framework::aptos_coin::{AptosCoin as APT};
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_token_objects::collection;
    use aptos_std::simple_map;
    use aptos_std::smart_table::{Self, SmartTable};
    use std::option::{Self, Option};
    use std::signer;
    use std::string::{Self, String};
    use std::string_utils;
    use std::type_info;
    use std::vector;
    use composable_token::composable_token::{
        Self, 
        Composable, 
        DA, 
        Trait, 
        Indexed, 
        Collection
    };
    use townespace::common;
    use minter::transfer_token;

    // ------
    // Errors
    // ------

    /// Vector length mismatch
    const ELENGTH_MISMATCH: u64 = 1;
    /// Type not supported
    const ETYPE_NOT_SUPPORTED: u64 = 2;
    /// Insufficient funds
    const EINSUFFICIENT_FUNDS: u64 = 3;
    /// Type not recognized
    const ETYPE_NOT_RECOGNIZED: u64 = 4;

    // ---------
    // Resources
    // ---------

    /// Global storage for the minting metadata
    struct MintInfo<phantom T> has key {
        /// The address of the owner
        owner_addr: address,
        /// The collection associated with the tokens to be minted
        collection: Object<Collection>,
        /// Used for transferring objects
        extend_ref: ExtendRef,
        /// The list of all composables locked up in the contract along with their mint prices
        token_pool: SmartTable<Object<T>, u64>,
    }

    

    // ------
    // Events
    // ------

    #[event]
    struct MintInfoInitialized has drop, store {
        collection: address,
        mint_info_object_address: address,
        owner_addr: address
    }

    #[event]
    struct TokensForMintCreated has drop, store {
        tokens: vector<address>,
    }

    #[event]
    struct TokenMinted has drop, store {
        tokens: vector<address>,
        mint_prices: vector<u64>,
    }

    /// Entry Function to create tokens for minting
    public entry fun create_tokens_for_mint<T: key>(
        signer_ref: &signer,
        collection: Object<Collection>,
        description: String,
        type: String,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
        token_count: u64,
        folder_uri: String,
        mint_price: u64
    ) { 
        let (tokens, mint_info_obj, _) = create_tokens_for_mint_internal<T>(
            signer_ref,
            collection,
            description,
            type,
            royalty_numerator,
            royalty_denominator,
            property_keys,
            property_types,
            property_values,
            folder_uri,
            token_count,
            mint_price
        );

        // emit events
        event::emit(
            MintInfoInitialized {
                collection: object::object_address(&collection),
                mint_info_object_address: object::object_address(&mint_info_obj),
                owner_addr: signer::address_of(signer_ref)
            }
        );

        event::emit(TokensForMintCreated { tokens });
    }

    /// Entry Function to create composable tokens with soulbound traits for minting
    public entry fun create_composable_tokens_with_soulbound_traits_for_mint<T: key>(
        signer_ref: &signer,
        collection: Object<Collection>,
        description: String,
        trait_type: String,
        composable_type: String,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
        folder_uri: String,
        token_count: u64,
        mint_price: u64
    ) {
        let (composable_tokens, trait_tokens, mint_info_obj, _) = create_composable_tokens_with_soulbound_traits_for_mint_internal<T>(
            signer_ref,
            collection,
            description,
            trait_type,
            composable_type,
            royalty_numerator,
            royalty_denominator,
            property_keys,
            property_types,
            property_values,
            folder_uri,
            token_count,
            mint_price
        );

        // emit events
        event::emit(
            MintInfoInitialized {
                collection: object::object_address(&collection),
                mint_info_object_address: object::object_address(&mint_info_obj),
                owner_addr: signer::address_of(signer_ref)
            }
        );

        event::emit(TokensForMintCreated { tokens: composable_tokens });
        event::emit(TokensForMintCreated { tokens: trait_tokens });
    }

    /// Entry Function to mint tokens
    public entry fun mint_tokens<T: key>(
        signer_ref: &signer,
        mint_info_obj_addr: address,
        count: u64
    ) acquires MintInfo {
        let (minted_tokens, mint_prices) = mint_batch_tokens<T>(signer_ref, mint_info_obj_addr, count);
        event::emit(TokenMinted { tokens: minted_tokens, mint_prices });
    }

    /// Entry function for adding more tokens for minting
    public entry fun add_tokens_for_mint<T: key>(
        signer_ref: &signer,
        collection: Object<Collection>,
        mint_info_obj_addr: address,
        description: String,
        type: String,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
        folder_uri: String,
        token_count: u64,
        mint_price: u64
    ) acquires MintInfo {
        add_tokens_for_mint_internal<T>(
            signer_ref,
            collection,
            mint_info_obj_addr,
            description,
            type,
            royalty_numerator,
            royalty_denominator,
            property_keys,
            property_types,
            property_values,
            folder_uri,
            token_count,
            mint_price
        );
    }
    

    // ----------------
    // Helper functions
    // ----------------

    /// Helper function for creating composable tokens for minting with trait tokens bound to them
    public fun create_composable_tokens_with_soulbound_traits_for_mint_internal<T>(
        signer_ref: &signer,
        collection: Object<Collection>,
        description: String,
        // trait token related fields
        trait_type: String,
        // composable token related fields
        composable_type: String,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
        folder_uri: String,
        token_count: u64,
        mint_price: u64
    ): (vector<address>, vector<address>, Object<MintInfo<T>>, vector<object::ConstructorRef>) {
        
        // prepare the vectors
        let (
            uri_with_index_prefix,
            name_with_index_prefix,
            name_with_index_suffix,
            vec_mint_price,
        ) = prepare_vecs(composable_type, mint_price, token_count);
        // Build the object to hold the liquid token
        // This must be a sticky object (a non-deleteable object) to be fungible
        let (
            _, 
            extend_ref, 
            object_signer, 
            obj_addr
        ) = common::create_sticky_object(signer::address_of(signer_ref));
        // create composable tokens
        let (tokens, tokens_addr, constructor_refs) = create_tokens_internal<Composable>(
            signer_ref,
            obj_addr,
            collection,
            description,
            composable_type,
            uri_with_index_prefix,
            name_with_index_prefix,
            name_with_index_suffix,
            royalty_numerator,
            royalty_denominator,
            property_keys,
            property_types,
            property_values,
            folder_uri,
            token_count,
        );
        // create trait tokens
        let (_, trait_tokens_addr, trait_constructor_refs) = create_tokens_without_mint_pool<Trait>(
            signer_ref,
            collection,
            description,
            trait_type,
            royalty_numerator,
            royalty_denominator,
            property_keys,
            property_types,
            property_values,
            folder_uri,
            token_count
        );
        // soulbind the trait tokens to the composable tokens
        vector::zip(tokens_addr, trait_constructor_refs, |composable_addr, trait_constructor_ref| {
            transfer_token::transfer_soulbound(composable_addr, &trait_constructor_ref);
        });
        let token_pool = smart_table::new<Object<Composable>, u64>();
        // add tokens and mint_price to the composable_token_pool
        smart_table::add_all(&mut token_pool, tokens, vec_mint_price);
        // Add the Metadata
        move_to(
            &object_signer, 
                MintInfo<Composable> {
                    owner_addr: signer::address_of(signer_ref),
                    collection, 
                    extend_ref,
                    token_pool,
                }
        );

        (tokens_addr, trait_tokens_addr, object::address_to_object(obj_addr), constructor_refs)
    }

    /// Helper function to prepare the vectors for naming the NFTs
    inline fun prepare_vecs(
        type: String, 
        mint_price: u64,
        count: u64
    ): (vector<String>, vector<String>, vector<String>, vector<u64>) {
        let mint_uri_with_index_prefix = type;
        let mint_name_with_index_prefix = type;

        // e.g: Panda%20
        string::append_utf8(&mut mint_uri_with_index_prefix, b"%20");

        // e.g: Panda #
        string::append_utf8(&mut mint_name_with_index_prefix, b" #");

        // prepare the vectors
        let vec_mint_uri_with_index_prefix = vector::empty<String>();
        let vec_mint_name_with_index_prefix = vector::empty<String>();
        let vec_mint_name_with_index_suffix = vector::empty<String>();
        let vec_mint_price = vector::empty<u64>();
        for (i in 0..count) {
            vector::push_back(&mut vec_mint_uri_with_index_prefix, mint_uri_with_index_prefix);
            vector::push_back(&mut vec_mint_name_with_index_prefix, mint_name_with_index_prefix);
            vector::push_back(&mut vec_mint_name_with_index_suffix, string::utf8(b""));
            vector::push_back(&mut vec_mint_price, mint_price);
        };

        (vec_mint_uri_with_index_prefix, vec_mint_name_with_index_prefix, vec_mint_name_with_index_suffix, vec_mint_price)
    }

    /// Helper function for creating tokens for minting
    public fun create_tokens_for_mint_internal<T: key>(
        signer_ref: &signer,
        collection: Object<Collection>,
        description: String,
        type: String,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
        folder_uri: String,
        token_count: u64,
        mint_price: u64,
    ): (vector<address>, Object<MintInfo<T>>, vector<object::ConstructorRef>) {

        // prepare the vectors
        let (
            uri_with_index_prefix,
            name_with_index_prefix,
            name_with_index_suffix,
            vec_mint_price,
        ) = prepare_vecs(type, mint_price, token_count);

        // Build the object to hold the liquid token
        // This must be a sticky object (a non-deleteable object) to be fungible
        let (
            _, 
            extend_ref, 
            object_signer, 
            obj_addr
        ) = common::create_sticky_object(signer::address_of(signer_ref));
        let (tokens_addr, constructor_ref) = if (type_info::type_of<T>() == type_info::type_of<Composable>()) {
            // create tokens
            let (tokens, tokens_addr, constructors_ref) = create_tokens_internal<Composable>(
                signer_ref,
                obj_addr,
                collection,
                description,
                type,
                uri_with_index_prefix,
                name_with_index_prefix,
                name_with_index_suffix,
                royalty_numerator,
                royalty_denominator,
                property_keys,
                property_types,
                property_values,
                folder_uri,
                token_count,
            );
            let composable_token_pool = smart_table::new<Object<Composable>, u64>();
            // add tokens and mint_price to the composable_token_pool
            smart_table::add_all(&mut composable_token_pool, tokens, vec_mint_price);
            // Add the Metadata
            move_to(
                &object_signer, 
                    MintInfo {
                        owner_addr: signer::address_of(signer_ref),
                        collection, 
                        extend_ref, 
                        token_pool: composable_token_pool,
                    }
            );

            (tokens_addr, constructors_ref)
        
        } else if (type_info::type_of<T>() == type_info::type_of<Trait>()) {
            let (tokens, tokens_addr, constructors_ref) = create_tokens_internal<Trait>(
                signer_ref,
                obj_addr,
                collection,
                description,
                type,
                uri_with_index_prefix,
                name_with_index_prefix,
                name_with_index_suffix,
                royalty_numerator,
                royalty_denominator,
                property_keys,
                property_types,
                property_values,
                folder_uri,
                token_count
            );
            let trait_token_pool = smart_table::new();
            // add tokens and mint_price to the trait_pool
            smart_table::add_all(&mut trait_token_pool, tokens, vec_mint_price);
            // Add the Metadata
            move_to(
                &object_signer, 
                    MintInfo<Trait> {
                        owner_addr: signer::address_of(signer_ref),
                        collection, 
                        extend_ref, 
                        token_pool: trait_token_pool,
                    }
            );

            (tokens_addr, constructors_ref)
        } else {
            let da_pool = smart_table::new<Object<DA>, u64>();
            let (tokens, tokens_addr, constructor_ref) = create_tokens_internal<DA>(
                signer_ref,
                obj_addr,
                collection,
                description,
                type,
                uri_with_index_prefix,
                name_with_index_prefix,
                name_with_index_suffix,
                royalty_numerator,
                royalty_denominator,
                property_keys,
                property_types,
                property_values,
                folder_uri,
                token_count
            );
            // add tokens and mint_price to the da_pool
            smart_table::add_all(&mut da_pool, tokens, vec_mint_price);
            // Add the Metadata
            move_to(
                &object_signer, 
                    MintInfo<DA> {
                        owner_addr: signer::address_of(signer_ref),
                        collection, 
                        extend_ref, 
                        token_pool: da_pool,
                    }
            );

            (tokens_addr, constructor_ref)
        };
        // tokens objects, tokens addresses, object address holding the mint info
        (tokens_addr, object::address_to_object(obj_addr), constructor_ref)
    }

    /// Helper function for creating tokens
    fun create_tokens_internal<T: key>(
        signer_ref: &signer,
        mint_info_obj_addr: address,
        collection: Object<Collection>,
        description: String,
        name: String,
        uri_with_index_prefix: vector<String>,
        name_with_index_prefix: vector<String>,
        name_with_index_suffix: vector<String>,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
        folder_uri: String,
        token_count: u64,
    ): (vector<Object<T>>, vector<address>, vector<object::ConstructorRef>) {
        let tokens = vector::empty<Object<T>>();
        let tokens_addr = vector::empty();
        let constructors = vector::empty<object::ConstructorRef>();

        // mint tokens
        for (i in 0..token_count) {
            let token_index = *option::borrow(&collection::count(collection)) + 1;
            let token_uri = folder_uri;
            // token uri: folder_uri + "/" + "prefix" + "%23" + i + ".png"
            string::append_utf8(&mut token_uri, b"/");
            let uri_prefix = *vector::borrow<String>(&uri_with_index_prefix, i);
            let prefix = *vector::borrow<String>(&name_with_index_prefix, i);
            let suffix = *vector::borrow<String>(&name_with_index_suffix, i);
            string::append(&mut token_uri, uri_prefix);
            string::append_utf8(&mut token_uri, b"%23");    // %23 is the ascii code for #
            string::append(&mut token_uri, string_utils::to_string(&token_index));
            string::append_utf8(&mut token_uri, b".png");

            let (constructor) = composable_token::create_token<T, Indexed>(
                signer_ref,
                collection,
                description,
                name,
                prefix,
                suffix,
                token_uri,
                royalty_numerator,
                royalty_denominator,
                property_keys,
                property_types,
                property_values
            );

            // transfer the token to mint info object
            composable_token::transfer_token<T>(
                signer_ref,
                object::object_from_constructor_ref(&constructor), 
                mint_info_obj_addr
            );

            // update the vectors
            vector::push_back(&mut tokens, object::object_from_constructor_ref<T>(&constructor));
            vector::push_back(&mut tokens_addr, object::address_from_constructor_ref(&constructor));
            vector::push_back(&mut constructors, constructor);
        };

        (tokens, tokens_addr, constructors)
    }

    /// Helper function to create tokens without a mint pool
    fun create_tokens_without_mint_pool<T: key>(
        signer_ref: &signer,
        collection: Object<Collection>,
        description: String,
        type: String,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
        folder_uri: String,
        token_count: u64,
    ): (vector<Object<T>>, vector<address>, vector<object::ConstructorRef>) {
        let tokens = vector::empty<Object<T>>();
        let tokens_addr = vector::empty();
        let constructors = vector::empty<object::ConstructorRef>();

        // prepare the vectors
        let (
            uri_with_index_prefix,
            name_with_index_prefix,
            name_with_index_suffix,
            _,
        ) = prepare_vecs(type, 0, token_count);

        // mint tokens
        for (i in 0..token_count) {
            let token_uri = folder_uri;
            // token uri: folder_uri + "/" + "prefix" + "%23" + i + ".png"
            string::append_utf8(&mut token_uri, b"/");
            let uri_prefix = *vector::borrow<String>(&uri_with_index_prefix, i);
            let prefix = *vector::borrow<String>(&name_with_index_prefix, i);
            let suffix = *vector::borrow<String>(&name_with_index_suffix, i);
            string::append(&mut token_uri, uri_prefix);
            string::append_utf8(&mut token_uri, b"%23");    // %23 is the ascii code for #
            let token_index = *option::borrow(&collection::count(collection)) + 1;
            string::append(&mut token_uri, string_utils::to_string(&token_index));
            string::append_utf8(&mut token_uri, b".png");

            let (constructor) = composable_token::create_token<T, Indexed>(
                signer_ref,
                collection,
                description,
                type,
                prefix,
                suffix,
                token_uri,
                royalty_numerator,
                royalty_denominator,
                property_keys,
                property_types,
                property_values
            );

            // update the vectors
            vector::push_back(&mut tokens, object::object_from_constructor_ref<T>(&constructor));
            vector::push_back(&mut tokens_addr, object::address_from_constructor_ref(&constructor));
            vector::push_back(&mut constructors, constructor);
        };

        (tokens, tokens_addr, constructors)
    }

    /// Gets Keys from a smart table and returns a new smart table with with the pair <u64, address> and u64 is the index
    fun indexed_tokens<T: key> (
        smart_table: &SmartTable<Object<T>, u64>
    ): SmartTable<u64, address> {
        let indexed_tokens = smart_table::new<u64, address>();
        // create a simple map from the input smart table
        let simple_map = smart_table::to_simple_map(smart_table);
        // create a vector of keys
        let tokens = simple_map::keys(&simple_map);
        for (i in 0..smart_table::length(smart_table)) {
            // add the pair "i, tokens(i)" to the indexed_tokens
            let token_addr = object::object_address(vector::borrow(&tokens, i));
            smart_table::add(&mut indexed_tokens, i, token_addr);
        };

        indexed_tokens
    }
    

    /// Helper function for getting the mint_price of a token
    inline fun mint_price<T: key>(
        mint_info_obj_addr: address,
        token: Object<T>
    ): u64 acquires MintInfo {
        if (type_info::type_of<T>() == type_info::type_of<Composable>()) {
            let composable_token = object::convert<T, Composable>(token);
            let mint_info = borrow_global<MintInfo<Composable>>(mint_info_obj_addr);
            *smart_table::borrow<Object<Composable>, u64>(&mint_info.token_pool, composable_token)
        } else if (type_info::type_of<T>() == type_info::type_of<Trait>()) {
            let mint_info = borrow_global<MintInfo<Trait>>(mint_info_obj_addr);
            let trait = object::convert<T, Trait>(token);
            *smart_table::borrow<Object<Trait>, u64>(&mint_info.token_pool, trait)
        } else {
            let mint_info = borrow_global<MintInfo<DA>>(mint_info_obj_addr);
            let da = object::convert<T, DA>(token);
            *smart_table::borrow<Object<DA>, u64>(&mint_info.token_pool, da)
        }
    }

    /// Helper function for getting a random token from a smart table
    inline fun random_token<T: key>(
        mint_info_obj_addr: address
    ): address {
        if(type_info::type_of<T>() == type_info::type_of<Composable>()) {
            let mint_info = borrow_global_mut<MintInfo<Composable>>(mint_info_obj_addr);
            let pool = indexed_tokens<Composable>(&mint_info.token_pool);
            let i = common::pseudorandom_u64(smart_table::length<u64, address>(&pool));
            let token_addr = *smart_table::borrow<u64, address>(&pool, i);
            smart_table::destroy(pool);
            token_addr
        } else if (type_info::type_of<T>() == type_info::type_of<Trait>()) {
            let mint_info = borrow_global_mut<MintInfo<Trait>>(mint_info_obj_addr);
            let pool = indexed_tokens<Trait>(&mint_info.token_pool);
            let i = common::pseudorandom_u64(smart_table::length<u64, address>(&pool));
            let token_addr = *smart_table::borrow<u64, address>(&pool, i);
            smart_table::destroy(pool);
            token_addr
        } else {
            let mint_info = borrow_global_mut<MintInfo<DA>>(mint_info_obj_addr);
            let pool = indexed_tokens<DA>(&mint_info.token_pool);
            let i = common::pseudorandom_u64(smart_table::length<u64, address>(&pool));
            let token_addr = *smart_table::borrow<u64, address>(&pool, i);
            smart_table::destroy(pool);
            token_addr
        }
    }

    /// Helper function for minting a token
    /// Returns the address of the minted token and the mint price
    public fun mint_token<T: key>(signer_ref: &signer, mint_info_obj_addr: address): (address, u64) acquires MintInfo {
        let signer_addr = signer::address_of(signer_ref);
        assert!(
            type_info::type_of<T>() == type_info::type_of<Composable>()
            || type_info::type_of<T>() == type_info::type_of<Trait>()
            || type_info::type_of<T>() == type_info::type_of<DA>(), 
            ETYPE_NOT_RECOGNIZED
        );
        // remove the token from the mint info
        let (token_addr, mint_price) = if (type_info::type_of<T>() == type_info::type_of<Composable>()) {
            // get random token from the token_pool
            let token_addr = random_token<Composable>(mint_info_obj_addr);
            // get mint price
            let composable = object::address_to_object<Composable>(token_addr);
            let mint_price = mint_price<Composable>(mint_info_obj_addr, object::address_to_object<Composable>(token_addr));
            assert!(coin::balance<APT>(signer_addr) >= mint_price, EINSUFFICIENT_FUNDS);
            let mint_info = borrow_global_mut<MintInfo<Composable>>(mint_info_obj_addr);
            (token_addr, smart_table::remove(&mut mint_info.token_pool, composable))
        } else if (type_info::type_of<T>() == type_info::type_of<Trait>()) {
            // get random token from the trait_pool
            let token_addr = random_token<Trait>(mint_info_obj_addr);
            // get mint price
            let trait = object::address_to_object<Trait>(token_addr);
            let mint_price = mint_price<Trait>(mint_info_obj_addr, object::address_to_object<Trait>(token_addr));
            assert!(coin::balance<APT>(signer_addr) >= mint_price, EINSUFFICIENT_FUNDS);
            let mint_info = borrow_global_mut<MintInfo<Trait>>(mint_info_obj_addr);
            (token_addr, smart_table::remove(&mut mint_info.token_pool, trait))
        } else {
            // get random token from the da_pool
            let token_addr = random_token<DA>(mint_info_obj_addr);
            // get mint price
            let da = object::address_to_object<DA>(token_addr);
            let mint_price = mint_price<DA>(mint_info_obj_addr, object::address_to_object<DA>(token_addr));
            assert!(coin::balance<APT>(signer_addr) >= mint_price, EINSUFFICIENT_FUNDS);
            let mint_info = borrow_global_mut<MintInfo<DA>>(mint_info_obj_addr);
            (token_addr, smart_table::remove(&mut mint_info.token_pool, da))
        };
        // transfer composable from resource acc to the minter
        let mint_info = borrow_global<MintInfo<T>>(mint_info_obj_addr);
        let obj_signer = object::generate_signer_for_extending(&mint_info.extend_ref);
        composable_token::transfer_token<T>(
            &obj_signer, 
            object::address_to_object(token_addr), 
            signer_addr
        );
        // transfer mint price to the launchpad creator
        coin::transfer<APT>(signer_ref, mint_info.owner_addr, mint_price);

        (token_addr, mint_price)
    }

    /// Helper function for minting a batch of tokens
    public fun mint_batch_tokens<T: key>(
        signer_ref: &signer,
        mint_info_obj_addr: address,
        count: u64
    ): (vector<address>, vector<u64>) acquires MintInfo {
        let minted_tokens = vector::empty<address>();
        let mint_prices = vector::empty<u64>();
        for (i in 0..count) {
            let (token_addr, mint_price) = mint_token<T>(signer_ref, mint_info_obj_addr);
            vector::push_back(&mut minted_tokens, token_addr);
            vector::push_back(&mut mint_prices, mint_price);
        };

        (minted_tokens, mint_prices)
    }

    /// Helper function to create more tokens and add them to the mint_info
    public fun add_tokens_for_mint_internal<T: key>(
        signer_ref: &signer,
        collection: Object<Collection>,
        mint_info_obj_addr: address,
        description: String,
        type: String,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>,
        folder_uri: String,
        token_count: u64,
        mint_price: u64
    ): vector<address> acquires MintInfo {
        // prepare the vectors
        let (
            uri_with_index_prefix,
            name_with_index_prefix,
            name_with_index_suffix,
            vec_mint_price,
        ) = prepare_vecs(type, mint_price, token_count);
        // creates tokens
        let tokens_addr = if (type_info::type_of<T>() == type_info::type_of<Composable>()) {
            let mint_info = borrow_global_mut<MintInfo<Composable>>(mint_info_obj_addr);
            // create tokens
            let (tokens, tokens_addr, _) = create_tokens_internal<Composable>(
                signer_ref,
                mint_info_obj_addr,
                collection,
                description,
                type,
                uri_with_index_prefix,
                name_with_index_prefix,
                name_with_index_suffix,
                royalty_numerator,
                royalty_denominator,
                property_keys,
                property_types,
                property_values,
                folder_uri,
                token_count,
            );
            // add tokens and mint_price to the token_pool
            smart_table::add_all(&mut mint_info.token_pool, tokens, vec_mint_price);

            tokens_addr
        } else if (type_info::type_of<T>() == type_info::type_of<Trait>()) {
            let mint_info = borrow_global_mut<MintInfo<Trait>>(mint_info_obj_addr);
            // create tokens
            let (tokens, tokens_addr, _) = create_tokens_internal<Trait>(
                signer_ref,
                mint_info_obj_addr,
                collection,
                description,
                type,
                uri_with_index_prefix,
                name_with_index_prefix,
                name_with_index_suffix,
                royalty_numerator,
                royalty_denominator,
                property_keys,
                property_types,
                property_values,
                folder_uri,
                token_count
            );
            // add tokens and mint_price to the trait_pool
            smart_table::add_all(&mut mint_info.token_pool, tokens, vec_mint_price);

            tokens_addr
        } else {
            let mint_info = borrow_global_mut<MintInfo<DA>>(mint_info_obj_addr);
            // create tokens
            let (tokens, tokens_addr, _) = create_tokens_internal<DA>(
                signer_ref,
                mint_info_obj_addr,
                collection,
                description,
                type,
                uri_with_index_prefix,
                name_with_index_prefix,
                name_with_index_suffix,
                royalty_numerator,
                royalty_denominator,
                property_keys,
                property_types,
                property_values,
                folder_uri,
                token_count
            );

            // add tokens and mint_price to the da_pool
            smart_table::add_all(&mut mint_info.token_pool, tokens, vec_mint_price);

            tokens_addr
        };

        // transfer them to mint_info
        for (i in 0..token_count) {
            let token = object::address_to_object<T>(*vector::borrow(&tokens_addr, i));
            composable_token::transfer_token<T>(signer_ref, token, mint_info_obj_addr);
        };

        // emit event
        event::emit(TokensForMintCreated { tokens: tokens_addr });

        tokens_addr
    }
    
    
    // --------------
    // View Functions
    // --------------

    #[view]
    /// Get a list of tokens available for minting
    public fun tokens_for_mint<T: key>(
        mint_info_obj_addr: address
    ): vector<address> acquires MintInfo {
        let tokens = if (type_info::type_of<T>() == type_info::type_of<Composable>()) {
            let mint_info = borrow_global_mut<MintInfo<Composable>>(mint_info_obj_addr);
            indexed_tokens<Composable>(&mint_info.token_pool)
        } else if (type_info::type_of<T>() == type_info::type_of<Trait>()) {
            let mint_info = borrow_global_mut<MintInfo<Trait>>(mint_info_obj_addr);
            indexed_tokens<Trait>(&mint_info.token_pool)
        } else {
            let mint_info = borrow_global_mut<MintInfo<DA>>(mint_info_obj_addr);
            indexed_tokens<DA>(&mint_info.token_pool)
        };
        let token_addresses = vector::empty<address>();

        for (i in 0..smart_table::length<u64, address>(&tokens)) {
            let token_addr = smart_table::remove<u64, address>(&mut tokens, i);
            vector::push_back(&mut token_addresses, token_addr);
        };

        smart_table::destroy(tokens);
        token_addresses
    }
    

    // ------------
    // Unit Testing
    // ------------

    #[test_only]
    use std::debug;
    #[test_only]
    use aptos_token_objects::collection::{FixedSupply};
    #[test_only]
    use aptos_token_objects::token;
    #[test_only]
    const URI_PREFIX: vector<u8> = b"Token%20Name%20Prefix%20";
    #[test_only]
    const PREFIX: vector<u8> = b"Prefix #"; 
    #[test_only]
    const SUFFIX : vector<u8> = b" Suffix";

    #[test(std = @0x1, creator = @0x111, minter = @0x222)]
    fun test_e2e(std: &signer, creator: &signer, minter: &signer) acquires MintInfo {
        let input_mint_price = 1000;

        let (creator_addr, minter_addr) = common::setup_test(std, creator, minter);
        let creator_balance_before_mint = coin::balance<APT>(signer::address_of(creator));
        // debug::print<u64>(&coin::balance<APT>(creator_addr));
        // creator creates a collection
        let collection_constructor_ref = composable_token::create_collection<FixedSupply>(
            creator,
            string::utf8(b"Collection Description"),
            option::some(100),
            string::utf8(b"Collection Name"),
            string::utf8(b"Collection Symbol"),
            string::utf8(b"Collection URI"),
            true,
            true, 
            true,
            true,
            true, 
            true,
            true,
            true, 
            true,
            option::none(),
            option::none(),
        );

        // creator creates tokens for minting
        let (_, mint_info_obj, _) = create_tokens_for_mint_internal<Composable>(
            creator,
            object::object_from_constructor_ref(&collection_constructor_ref),
            string::utf8(b"Description"),
            string::utf8(b"Type"),
            option::none(),
            option::none(),
            vector[],
            vector[],
            vector[],
            string::utf8(b"Folder URI"),
            4,
            input_mint_price
        );

        // minter mints tokens
        let (minted_tokens, _) = mint_batch_tokens<Composable>(minter, object::object_address<MintInfo<Composable>>(&mint_info_obj), 4);

        // assert the owner is the minter
        let token_0 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 0));
        let token_1 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 1));
        let token_2 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 2));
        let token_3 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 3));

        assert!(object::is_owner(token_0, minter_addr), 1);
        assert!(object::is_owner(token_1, minter_addr), 1);
        assert!(object::is_owner(token_2, minter_addr), 1);
        assert!(object::is_owner(token_3, minter_addr), 1);

        // assert the mint price is sent to the owner
        let creator_balance_after_mint = creator_balance_before_mint + (input_mint_price * 4);
        // debug::print<u64>(&coin::balance<APT>(creator_addr));
        assert!(coin::balance<APT>(creator_addr) == creator_balance_after_mint, 2);

        // // get one token and print its name and uri
        // debug::print<String>(&token::name<Composable>(token_0));
        // debug::print<String>(&token::name<Composable>(token_1));
        // debug::print<String>(&token::name<Composable>(token_2));
        // debug::print<String>(&token::name<Composable>(token_3));

        // debug::print<String>(&token::uri<Composable>(token_0));
        // debug::print<String>(&token::uri<Composable>(token_1));
        // debug::print<String>(&token::uri<Composable>(token_2));
        // debug::print<String>(&token::uri<Composable>(token_3));

        // create more tokens for minting
        add_tokens_for_mint_internal<Composable>(
            creator,
            object::object_from_constructor_ref(&collection_constructor_ref),
            object::object_address<MintInfo<Composable>>(&mint_info_obj),
            string::utf8(b"Description"),
            string::utf8(b"Type"),
            option::none(),
            option::none(),
            vector[],
            vector[],
            vector[],
            string::utf8(b"Folder%20URI"),
            4,
            input_mint_price
        );

        // mint the newly created tokens
        let (minted_tokens, _) = mint_batch_tokens<Composable>(minter, object::object_address<MintInfo<Composable>>(&mint_info_obj), 4);

        // assert the owner is the minter
        let token_4 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 0));
        let token_5 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 1));
        let token_6 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 2));
        let token_7 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 3));

        assert!(object::is_owner(token_4, minter_addr), 3);
        assert!(object::is_owner(token_5, minter_addr), 3);
        assert!(object::is_owner(token_6, minter_addr), 3);
        assert!(object::is_owner(token_7, minter_addr), 3);

        // assert the mint price is sent to the owner
        let creator_balance_after_mint = creator_balance_after_mint + (input_mint_price * 4);
        assert!(coin::balance<APT>(creator_addr) == creator_balance_after_mint, 4);

        // get one token and print its name and uri
        debug::print<String>(&token::name<Composable>(token_4));
        debug::print<String>(&token::name<Composable>(token_5));
        debug::print<String>(&token::name<Composable>(token_6));
        debug::print<String>(&token::name<Composable>(token_7));
    }

    #[test_only]
    const TRAIT_URI_PREFIX: vector<u8> = b"Trait%20Name%20Prefix%20";
    #[test_only]
    const TRAIT_PREFIX: vector<u8> = b"Trait Prefix #";
    #[test_only]
    const TRAIT_SUFFIX : vector<u8> = b" Trait Suffix";
    #[test(std = @0x1, creator = @0x111, minter = @0x222)]
    /// Test the minting of composable tokens with soulbound traits
    fun test_composable_tokens_with_soulbound_traits(std: &signer, creator: &signer, minter: &signer) acquires MintInfo {
        let input_mint_price = 1000;

        let (creator_addr, minter_addr) = common::setup_test(std, creator, minter);
        let creator_balance_before_mint = coin::balance<APT>(signer::address_of(creator));

        // creator creates a collection
        let collection_constructor_ref = composable_token::create_collection<FixedSupply>(
            creator,
            string::utf8(b"Collection Description"),
            option::some(100),
            string::utf8(b"Collection Name"),
            string::utf8(b"Collection Symbol"),
            string::utf8(b"Collection URI"),
            true,
            true, 
            true,
            true,
            true, 
            true,
            true,
            true, 
            true,
            option::none(),
            option::none(),
        );

        // creator creates composable tokens with soulbound traits
        let (composable_tokens_addresses, trait_tokens_addresses, mint_info_obj, _) = create_composable_tokens_with_soulbound_traits_for_mint_internal(
            creator,
            object::object_from_constructor_ref(&collection_constructor_ref),
            string::utf8(b"Description"),
            // trait token related fields
            string::utf8(b"Trait type"),
            // composable token related fields
            string::utf8(b"Composable type"),
            option::none(),
            option::none(),
            vector[],
            vector[],
            vector[],
            string::utf8(b"Folder%20URI"),
            4,
            input_mint_price
        );

        // assert trait tokens are soulbound to the composable tokens
        let trait_token_0 = object::address_to_object<Trait>(*vector::borrow(&trait_tokens_addresses, 0));
        let trait_token_1 = object::address_to_object<Trait>(*vector::borrow(&trait_tokens_addresses, 1));
        let trait_token_2 = object::address_to_object<Trait>(*vector::borrow(&trait_tokens_addresses, 2));
        let trait_token_3 = object::address_to_object<Trait>(*vector::borrow(&trait_tokens_addresses, 3));

        let composable_token_0 = object::address_to_object<Composable>(*vector::borrow(&composable_tokens_addresses, 0));
        let composable_token_1 = object::address_to_object<Composable>(*vector::borrow(&composable_tokens_addresses, 1));
        let composable_token_2 = object::address_to_object<Composable>(*vector::borrow(&composable_tokens_addresses, 2));
        let composable_token_3 = object::address_to_object<Composable>(*vector::borrow(&composable_tokens_addresses, 3));

        assert!(object::is_owner(trait_token_0, *vector::borrow(&composable_tokens_addresses, 0)), 1);
        assert!(object::is_owner(trait_token_1, *vector::borrow(&composable_tokens_addresses, 1)), 1);
        assert!(object::is_owner(trait_token_2, *vector::borrow(&composable_tokens_addresses, 2)), 1);
        assert!(object::is_owner(trait_token_3, *vector::borrow(&composable_tokens_addresses, 3)), 1);

        // minter mints tokens
        let (minted_tokens, _) = mint_batch_tokens<Composable>(minter, object::object_address<MintInfo<Composable>>(&mint_info_obj), 4);

        // assert the owner is the minter
        let token_0 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 0));
        let token_1 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 1));
        let token_2 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 2));
        let token_3 = object::address_to_object<Composable>(*vector::borrow(&minted_tokens, 3));
        assert!(object::is_owner(token_0, minter_addr), 1);
        assert!(object::is_owner(token_1, minter_addr), 1);
        assert!(object::is_owner(token_2, minter_addr), 1);
        assert!(object::is_owner(token_3, minter_addr), 1);

        // assert the mint price is sent to the owner
        let creator_balance_after_mint = creator_balance_before_mint + (input_mint_price * 4);
        assert!(coin::balance<APT>(creator_addr) == creator_balance_after_mint, 2);

        // get tokens and print their names 
        debug::print<String>(&token::name<Trait>(trait_token_0));
        debug::print<String>(&token::name<Trait>(trait_token_1));
        debug::print<String>(&token::name<Trait>(trait_token_2));
        debug::print<String>(&token::name<Trait>(trait_token_3));

        debug::print<String>(&token::name<Composable>(composable_token_0));
        debug::print<String>(&token::name<Composable>(composable_token_1));
        debug::print<String>(&token::name<Composable>(composable_token_2));
        debug::print<String>(&token::name<Composable>(composable_token_3));

        // print uris
        debug::print<String>(&token::uri<Trait>(trait_token_0));
        debug::print<String>(&token::uri<Trait>(trait_token_1));
        debug::print<String>(&token::uri<Trait>(trait_token_2));
        debug::print<String>(&token::uri<Trait>(trait_token_3));

        debug::print<String>(&token::uri<Composable>(composable_token_0));
        debug::print<String>(&token::uri<Composable>(composable_token_1));
        debug::print<String>(&token::uri<Composable>(composable_token_2));
        debug::print<String>(&token::uri<Composable>(composable_token_3));
    }
}