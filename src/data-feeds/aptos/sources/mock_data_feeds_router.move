module chainlink_local::mock_data_feeds_router {
    use aptos_framework::object::{Self, ExtendRef, TransferRef};

    use chainlink_local::mock_data_feeds_registry::{Self, Benchmark, Report};

    const APP_OBJECT_SEED: vector<u8> = b"MOCK_ROUTER";

    struct MockRouter has key, store, drop {
        extend_ref: ExtendRef,
        transfer_ref: TransferRef
    }

    // ================================================================
    //                         Constructor                             
    // ================================================================

    #[test_only]
    public fun initialize(publisher: &signer) {
        let constructor_ref = object::create_named_object(publisher, APP_OBJECT_SEED);

        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);

        move_to(
            &object_signer,
            MockRouter {
                extend_ref,
                transfer_ref
            }
        );
    }

    inline fun get_state_addr(): address {
        object::create_object_address(&@chainlink_local, APP_OBJECT_SEED)
    }

    // ================================================================
    //                             Getters                             
    // ================================================================

    public fun get_benchmarks(
        _authority: &signer, feed_ids: vector<vector<u8>>, _billing_data: vector<u8>
    ): vector<Benchmark> acquires MockRouter {
        let _router = borrow_global<MockRouter>(get_state_addr());

        mock_data_feeds_registry::get_benchmarks(_authority, feed_ids)
    }

    public fun get_reports(
        _authority: &signer, feed_ids: vector<vector<u8>>, _billing_data: vector<u8>
    ): vector<Report> acquires MockRouter {
        let _router = borrow_global<MockRouter>(get_state_addr());

        mock_data_feeds_registry::get_reports(_authority, feed_ids)
    }
}