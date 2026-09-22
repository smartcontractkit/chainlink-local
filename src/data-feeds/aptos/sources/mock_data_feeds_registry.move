module chainlink_local::mock_data_feeds_registry {
    use std::error;
    use std::vector;
    use std::event;
    use std::simple_map::{Self, SimpleMap};
    use std::string::{String};

    use aptos_framework::object::{Self, ExtendRef, TransferRef};

    const APP_OBJECT_SEED: vector<u8> = b"MOCK_REGISTRY";

    struct MockRegistry has key, store, drop {
        extend_ref: ExtendRef,
        transfer_ref: TransferRef,
        feeds: SimpleMap<vector<u8>, Feed>,
    }

    struct Feed has key, store, drop, copy {
        description: String,
        config_id: vector<u8>,
        benchmark: u256,
        report: vector<u8>,
        observation_timestamp: u256
    }

    struct Benchmark has store, drop {
        benchmark: u256,
        observation_timestamp: u256
    }

    struct Report has store, drop {
        report: vector<u8>,
        observation_timestamp: u256
    }

    struct FeedMetadata has store, drop, key {
        description: String,
        config_id: vector<u8>
    }

    struct FeedConfig has drop {
        feed_id: vector<u8>,
        feed: Feed
    }

    // ================================================================
    //                             Events                              
    // ================================================================

    #[event]
    struct FeedSet has drop, store {
        feed_id: vector<u8>,
        description: String,
        config_id: vector<u8>
    }

    #[event]
    struct FeedRemoved has drop, store {
        feed_id: vector<u8>
    }

    #[event]
    struct FeedUpdated has drop, store {
        feed_id: vector<u8>,
        observation_timestamp: u256,
        benchmark: u256,
        report: vector<u8>
    }

    #[event]
    struct StaleReport has drop, store {
        feed_id: vector<u8>,
        latest_timestamp: u256,
        report_timestamp: u256
    }

    // ================================================================
    //                             Errors                              
    // ================================================================

    // Error codes from Mock mirrors the errors from the actual Registry contract
    const EDUPLICATE_ELEMENTS: u64 = 2;
    const EFEED_EXISTS: u64 = 3;
    const EFEED_NOT_CONFIGURED: u64 = 4;
    const EUNEQUAL_ARRAY_LENGTHS: u64 = 6;

    fun assert_no_duplicates<T>(a: &vector<T>) {
        let len = vector::length(a);
        for (i in 0..len) {
            for (j in (i + 1)..len) {
                assert!(
                    vector::borrow(a, i) != vector::borrow(a, j),
                    error::invalid_argument(EDUPLICATE_ELEMENTS)
                );
            }
        }
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
            MockRegistry {
                extend_ref,
                transfer_ref,
                feeds: simple_map::new(),
            }
        );
    }

    inline fun get_state_addr(): address {
        object::create_object_address(&@chainlink_local, APP_OBJECT_SEED)
    }

    // ================================================================
    //                        Add & Remove Feeds                       
    // ================================================================

    public entry fun add_feeds(
        feed_ids: vector<vector<u8>>,
        descriptions: vector<String>,
        config_id: vector<u8>
    ) acquires MockRegistry {
        let registry = borrow_global_mut<MockRegistry>(get_state_addr());
        
        assert_no_duplicates(&feed_ids);

        assert!(
            vector::length(&feed_ids) == vector::length(&descriptions),
            error::invalid_argument(EUNEQUAL_ARRAY_LENGTHS)
        );

        vector::zip_ref(
            &feed_ids,
            &descriptions,
            |feed_id, description| {
                assert!(
                    !simple_map::contains_key(&registry.feeds, feed_id),
                    error::invalid_argument(EFEED_EXISTS)
                );

                let feed = Feed {
                    description: *description,
                    config_id,
                    benchmark: 0,
                    report: vector::empty(),
                    observation_timestamp: 0
                };
                simple_map::add(&mut registry.feeds, *feed_id, feed);

                event::emit(
                    FeedSet { feed_id: *feed_id, description: *description, config_id }
                );
            }
        );
    }

    public entry fun remove_feeds(
        feed_ids: vector<vector<u8>>
    ) acquires MockRegistry {
        let registry = borrow_global_mut<MockRegistry>(get_state_addr());

        assert_no_duplicates(&feed_ids);

        vector::for_each(
            feed_ids,
            |feed_id| {
                assert!(
                    simple_map::contains_key(&registry.feeds, &feed_id),
                    error::invalid_argument(EFEED_NOT_CONFIGURED)
                );
                simple_map::remove(&mut registry.feeds, &feed_id);
            }
        );
    }

    // ================================================================
    //                        Set Mock Price                           
    // ================================================================

    public entry fun set_mock_price(
        feed_id: vector<u8>,
        benchmark: u256,
        observation_timestamp: u256,
        report: vector<u8>
    ) acquires MockRegistry {
        let registry = borrow_global_mut<MockRegistry>(get_state_addr());
        assert!(
            simple_map::contains_key(&registry.feeds, &feed_id),
            error::invalid_argument(EFEED_NOT_CONFIGURED)
        );

        let feed = simple_map::borrow_mut(&mut registry.feeds, &feed_id);

        if (feed.observation_timestamp >= observation_timestamp) {
            event::emit(
                StaleReport {
                    feed_id,
                    latest_timestamp: feed.observation_timestamp,
                    report_timestamp: observation_timestamp
                }
            );
        };

        feed.benchmark = benchmark;
        feed.observation_timestamp = observation_timestamp;
        feed.report = report;

        event::emit(
            FeedUpdated {
                feed_id,
                observation_timestamp,
                benchmark,
                report
            }
        );
    }

    // ================================================================
    //                             Getters                             
    // ================================================================

    #[view]
    public fun get_feeds(): vector<FeedConfig> acquires MockRegistry {
        let registry = borrow_global<MockRegistry>(get_state_addr());
        let feed_configs = vector[];
        let (feed_ids, feeds) = simple_map::to_vec_pair(registry.feeds);
        vector::zip_ref(
            &feed_ids,
            &feeds,
            |feed_id, feed| {
                vector::push_back(
                    &mut feed_configs,
                    FeedConfig { feed_id: *feed_id, feed: *feed }
                );
            }
        );
        feed_configs
    }

    #[view]
    public fun get_feed_metadata(
        feed_ids: vector<vector<u8>>
    ): vector<FeedMetadata> acquires MockRegistry {
        let registry = borrow_global<MockRegistry>(get_state_addr());

        vector::map(
            feed_ids,
            |feed_id| {
                assert!(
                    simple_map::contains_key(&registry.feeds, &feed_id),
                    error::invalid_argument(EFEED_NOT_CONFIGURED)
                );

                let feed = simple_map::borrow(&registry.feeds, &feed_id);

                FeedMetadata { description: feed.description, config_id: feed.config_id }
            }
        )
    }

    public fun get_benchmarks(
        _authority: &signer, feed_ids: vector<vector<u8>>
    ): vector<Benchmark> acquires MockRegistry {
        let registry = borrow_global<MockRegistry>(get_state_addr());
        
        vector::map(
            feed_ids,
            |feed_id| {
                assert!(
                    simple_map::contains_key(&registry.feeds, &feed_id),
                    error::invalid_argument(EFEED_NOT_CONFIGURED)
                );

                let feed = simple_map::borrow(&registry.feeds, &feed_id);

                Benchmark {
                    benchmark: feed.benchmark,
                    observation_timestamp: feed.observation_timestamp
                }
            }
        )
    }

    public fun get_reports(
        _authority: &signer, feed_ids: vector<vector<u8>>
    ): vector<Report> acquires MockRegistry {
        let registry = borrow_global<MockRegistry>(get_state_addr());
        
        vector::map(
            feed_ids,
            |feed_id| {
                assert!(
                    simple_map::contains_key(&registry.feeds, &feed_id),
                    error::invalid_argument(EFEED_NOT_CONFIGURED)
                );

                let feed = simple_map::borrow(&registry.feeds, &feed_id);

                Report {
                    report: feed.report,
                    observation_timestamp: feed.observation_timestamp
                }
            }
        )
    }

    // ================================================================
    //                        Struct accessors                         
    // ================================================================

    public fun get_benchmark_value(result: &Benchmark): u256 {
        result.benchmark
    }

    public fun get_benchmark_timestamp(result: &Benchmark): u256 {
        result.observation_timestamp
    }

    public fun get_report_value(result: &Report): vector<u8> {
        result.report
    }

    public fun get_report_timestamp(result: &Report): u256 {
        result.observation_timestamp
    }

    public fun get_feed_metadata_description(result: &FeedMetadata): String {
        result.description
    }

    public fun get_feed_metadata_config_id(result: &FeedMetadata): vector<u8> {
        result.config_id
    }

    // ================================================================
    //                              Tests                              
    // ================================================================
    
    // Test error codes
    const ETEST_WRONG_COUNT: u64 = 101;
    const ETEST_WRONG_DESCRIPTION: u64 = 102;
    const ETEST_WRONG_CONFIG: u64 = 103;
    const ETEST_WRONG_BENCHMARK: u64 = 104;
    const ETEST_WRONG_TIMESTAMP: u64 = 105;
    const ETEST_WRONG_REPORT: u64 = 106;

    #[test_only]
    fun set_up_test(publisher: &signer) {
        use std::signer;
        use aptos_framework::account::{Self};
        account::create_account_for_test(signer::address_of(publisher));

        initialize(publisher);
    }

    #[test_only]
    fun prepare_test_scenario(): (vector<vector<u8>>, vector<u8>) acquires MockRegistry {
        let feed_ids = vector[b"BTC/USD", b"ETH/USD"];
        let descriptions = vector[std::string::utf8(b"BTC/USD"), std::string::utf8(b"ETH/USD")];
        let config_id = b"MOCK_CONFIG";

        add_feeds(feed_ids, descriptions, config_id);

        (feed_ids, config_id)
    }

    #[test(publisher = @chainlink_local)]
    fun test_add_feeds(publisher: &signer) acquires MockRegistry {
        set_up_test(publisher);
        let (feed_ids, config_id) = prepare_test_scenario();

        let feeds = get_feeds();
        // std::debug::print(&feeds);
        assert!(vector::length(&feeds) == 2, ETEST_WRONG_COUNT);

        let feed_metadata = get_feed_metadata(feed_ids);
        assert!(vector::length(&feed_metadata) == 2, ETEST_WRONG_COUNT);

        let btc_usd_feed = vector::borrow(&feed_metadata, 0);
        assert!(get_feed_metadata_description(btc_usd_feed) == std::string::utf8(b"BTC/USD"), ETEST_WRONG_DESCRIPTION);
        assert!(get_feed_metadata_config_id(btc_usd_feed) == config_id, ETEST_WRONG_CONFIG);

        let eth_usd_feed = vector::borrow(&feed_metadata, 1);
        assert!(get_feed_metadata_description(eth_usd_feed) == std::string::utf8(b"ETH/USD"), ETEST_WRONG_DESCRIPTION);
        assert!(get_feed_metadata_config_id(eth_usd_feed) == config_id, ETEST_WRONG_CONFIG);
    }

    #[test(publisher = @chainlink_local)]
    #[expected_failure(abort_code = 65540, location = chainlink_local::mock_data_feeds_registry)]
    fun test_remove_feeds(publisher: &signer) acquires MockRegistry {
        set_up_test(publisher);
        let (_, _) = prepare_test_scenario();

        let feed_id_to_remove = vector[b"BTC/USD"];

        remove_feeds(feed_id_to_remove);

        let feeds = get_feeds();
        assert!(vector::length(&feeds) == 1, ETEST_WRONG_COUNT);

        let expected_feed = b"ETH/USD";
        let feed_metadata = get_feed_metadata(vector[expected_feed]);
        assert!(vector::length(&feed_metadata) == 1, ETEST_WRONG_COUNT);
        assert!(get_feed_metadata_description(vector::borrow(&feed_metadata, 0)) == std::string::utf8(expected_feed), ETEST_WRONG_DESCRIPTION);

        // This should revert with EFEED_NOT_CONFIGURED
        let _ = get_feed_metadata(feed_id_to_remove);
    }

    #[test(publisher = @chainlink_local, sender = @sender)]
    fun test_set_mock_price(publisher: &signer, sender: &signer) acquires MockRegistry {
        set_up_test(publisher);
        let (feed_ids, _) = prepare_test_scenario();

        let btc_usd_feed = *vector::borrow(&feed_ids, 0);

        let mock_benchmark = 100;
        let mock_observation_timestamp = 1000;
        let mock_report = x"00031111111111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000066b3a12c0000000000000000000000000000000000000000000000000000000066b3a12c00000000000000000000000000000000000000000000000000000000000494a800000000000000000000000000000000000000000000000000000000000494a80000000000000000000000000000000000000000000000000000000066c2e36c00000000000000000000000000000000000000000000000000000000000494a800000000000000000000000000000000000000000000000000000000000494a800000000000000000000000000000000000000000000000000000000000494a8";

        set_mock_price(btc_usd_feed, mock_benchmark, mock_observation_timestamp, mock_report);

        let benchmarks = get_benchmarks(sender, feed_ids);
        assert!(vector::length(&benchmarks) == 2, ETEST_WRONG_COUNT);

        let btc_usd_benchmark = vector::borrow(&benchmarks, 0);
        assert!(get_benchmark_value(btc_usd_benchmark) == mock_benchmark, ETEST_WRONG_BENCHMARK);
        assert!(get_benchmark_timestamp(btc_usd_benchmark) == mock_observation_timestamp, ETEST_WRONG_TIMESTAMP);

        // We haven't set the benchmark for ETH/USD, so it should have default values
        let eth_usd_benchmark = vector::borrow(&benchmarks, 1);
        assert!(get_benchmark_value(eth_usd_benchmark) == 0, ETEST_WRONG_BENCHMARK);
        assert!(get_benchmark_timestamp(eth_usd_benchmark) == 0, ETEST_WRONG_TIMESTAMP);

        let reports = get_reports(sender, feed_ids);
        assert!(vector::length(&reports) == 2, ETEST_WRONG_COUNT);

        let btc_usd_report = vector::borrow(&reports, 0);
        assert!(get_report_value(btc_usd_report) == mock_report, ETEST_WRONG_REPORT);
        assert!(get_report_timestamp(btc_usd_report) == mock_observation_timestamp, ETEST_WRONG_TIMESTAMP);
    }
}
