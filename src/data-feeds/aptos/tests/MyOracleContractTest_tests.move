#[test_only]
module sender::MyOracleContractTest_tests {
    use sender::MyOracleContractTest;
    use std::string;
    use move_stdlib::option; 
    use aptos_framework::account;

    use chainlink_local::mock_data_feeds_registry;
    use chainlink_local::mock_data_feeds_router;

    const FEED_ID_ETH_USD: vector<u8> = b"ETH/USD";
    const MOCK_PRICE: u256 = 1800000000000000000000; // 1800 ETH/USD with 18 decimals
    const MOCK_TIMESTAMP: u256 = 1678912345;

    #[test(publisher = @chainlink_local, sender = @sender)]
    fun test_smoke(
        publisher: &signer,
        sender: &signer
    ) {
        // Initialize the publisher account
        account::create_account_for_test(@chainlink_local);
        
        // Initialize Chainlink Local
        mock_data_feeds_registry::initialize(publisher);
        mock_data_feeds_router::initialize(publisher);
        
        // Add ETH/USD feed
        let feed_ids = vector[FEED_ID_ETH_USD];
        let descriptions = vector[string::utf8(FEED_ID_ETH_USD)];
        let config_id = b"MOCK_CONFIG";
        mock_data_feeds_registry::add_feeds(feed_ids, descriptions, config_id);

        // Set mock price
        mock_data_feeds_registry::set_mock_price(
            FEED_ID_ETH_USD,
            MOCK_PRICE, 
            MOCK_TIMESTAMP,
            b"" // Empty report for this test
        );

        // Fetch price data from the mock data feed
        MyOracleContractTest::fetch_price(sender, FEED_ID_ETH_USD);

        // Asserts
        let price_data_opt = MyOracleContractTest::get_price_data(@sender);
        assert!(option::is_some(&price_data_opt), 1);
        
        let price_data = option::borrow(&price_data_opt);
        std::debug::print(price_data); // Visualize the PriceData struct
        assert!(MyOracleContractTest::get_price(price_data) == MOCK_PRICE, 2); 
        assert!(MyOracleContractTest::get_timestamp(price_data) == MOCK_TIMESTAMP, 3); 
    }
}