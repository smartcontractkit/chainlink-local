## Chainlink Local Data Feeds on Aptos Testnet

This repository contains two mock contracts that simulate the behavior of the
Chainlink Local Data Feeds on the Aptos testnet:

- `mock_data_feeds_registry.move`
- `mock_data_feeds_router.move`

The `ChainlinkLocal` package is deployed on the Aptos testnet at the following
address:

- `0xf22a4370fa80c7f3cd6815fe976d4b00e7b4c228d7c4b4f310b330b08eca5dea`

To download it, run the following command:

```
aptos move download --account 0xf22a4370fa80c7f3cd6815fe976d4b00e7b4c228d7c4b4f310b330b08eca5dea --package ChainlinkLocal
```

### Tutorial

This guide explains how to use Chainlink Data Feeds with your Move smart
contracts on Aptos testnet and test them locally using Chainlink Local. You will
use the [Aptos CLI](https://aptos.dev/en/build/cli) to compile, publish, and
interact with your contract.

#### Requirements

Make sure you have the Aptos CLI installed. You can run `aptos help` in your
terminal to verify if the CLI is correctly installed.

#### Step 1: Create a new project

Create a new directory for your project and navigate to it in your terminal

```
mkdir aptos-data-feeds-local && cd aptos-data-feeds-local
```

#### Step 2: Create a new testnet account

Run the following command in your terminal to create a new account on testnet:

```
aptos init --network=testnet --assume-yes
```

#### Step 3: Create a new Move project

Run the following command in your terminal to create a new Move project:

```
aptos move init --name aptos-data-feeds-local
```

#### Step 4: Update Move.toml file

Update your Move.toml file to include the required dependencies and addresses:

```toml
[package]
name = "my-app"
version = "1.0.0"
authors = []

[addresses]
sender = "<YOUR_ACCOUNT_ADDRESS>"
chainlink_local = "0xf22a4370fa80c7f3cd6815fe976d4b00e7b4c228d7c4b4f310b330b08eca5dea"
move_stdlib = "0x1"
aptos_std = "0x1"

[dev-addresses]

[dependencies]
AptosFramework = { git = "https://github.com/aptos-labs/aptos-core.git", subdir = "aptos-move/framework/aptos-framework", rev = "main" }
MoveStdlib = { git = "https://github.com/aptos-labs/aptos-core.git", subdir = "aptos-move/framework/move-stdlib", rev = "main" }
ChainlinkLocal = { local = "./ChainlinkLocal" }
```

#### Step 5: Download the ChainlinkLocal package

Run the following command in your terminal to download the ChainlinkLocal
package:

```
aptos move download --account 0xf22a4370fa80c7f3cd6815fe976d4b00e7b4c228d7c4b4f310b330b08eca5dea --package ChainlinkLocal
```

#### Step 6: Create a consumer smart contract

Create a new file named `MyOracleContractTest.move` in the `sources` directory
with the following content:

```rust
module sender::MyOracleContractTest {
   use std::vector;
   use std::signer;

   // use data_feeds::router::get_benchmarks;
   // use data_feeds::registry::{Benchmark, get_benchmark_value, get_benchmark_timestamp};
   use chainlink_local::mock_data_feeds_router::get_benchmarks;
   use chainlink_local::mock_data_feeds_registry::{Benchmark, get_benchmark_value, get_benchmark_timestamp};

   use move_stdlib::option::{Option, some, none};

   struct PriceData has copy, key, store, drop {
      /// The price value with 18 decimal places of precision
      price: u256,
      /// Unix timestamp in seconds
      timestamp: u256,
   }

   // Function to fetch and store the price data for a given feed ID
   public entry fun fetch_price(account: &signer, feed_id: vector<u8>) acquires PriceData {
      let feed_ids = vector[feed_id]; // Use the passed feed_id
      let billing_data = vector[];
      let benchmarks: vector<Benchmark> = get_benchmarks(account, feed_ids, billing_data);
      let benchmark = vector::pop_back(&mut benchmarks);
      let price: u256 = get_benchmark_value(&benchmark);
      let timestamp: u256 = get_benchmark_timestamp(&benchmark);

      // Check if PriceData exists and update it
      if (exists<PriceData>(signer::address_of(account))) {
            let data = borrow_global_mut<PriceData>(signer::address_of(account));
            data.price = price;
            data.timestamp = timestamp;
      } else {
            // If PriceData does not exist, create a new one
            move_to(account, PriceData { price, timestamp });
      }
   }

   // View function to get the stored price data
   #[view]
   public fun get_price_data(account_address: address): Option<PriceData> acquires PriceData {
      if (exists<PriceData>(account_address)) {
            let data = borrow_global<PriceData>(account_address);
            some(*data)
      } else {
            none()
      }
   }

    // Added for testing purposes

    public fun get_price(data: &PriceData): u256 {
        data.price
    }

    public fun get_timestamp(data: &PriceData): u256 {
        data.timestamp
    }
}
```

#### Step 7: Compile the contract

Run the following command in your terminal to compile the contract:

```
aptos move compile
```

#### Step 8: Create a test

Create a new file named `MyOracleContractTest_tests.move` in the `tests`
directory with the following content:

```rust
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
```

#### Step 9: Run the test

Run the following command in your terminal to run the test:

```
aptos move test
```

You will see the similar test result in your terminal:

```
INCLUDING DEPENDENCY AptosFramework
INCLUDING DEPENDENCY AptosStdlib
INCLUDING DEPENDENCY ChainlinkLocal
INCLUDING DEPENDENCY MoveStdlib
BUILDING my-app
Running Move unit tests
[debug] 0x1d07336b83f427515ff6dae6fe79079cb67333795b480e1ce488d80f8c729f77::MyOracleContractTest::PriceData {
  price: 1800000000000000000000,
  timestamp: 1678912345
}
[ PASS    ] 0x1d07336b83f427515ff6dae6fe79079cb67333795b480e1ce488d80f8c729f77::MyOracleContractTest_tests::test_smoke
Test result: OK. Total tests: 1; passed: 1; failed: 0
{
  "Result": "Success"
}
```
