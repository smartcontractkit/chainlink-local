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
