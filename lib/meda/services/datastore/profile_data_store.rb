require_relative "mapdb/mapdb_store"
require_relative "hashdb/hashdb_store"
require_relative "redisdb/redisdb_store"
require_relative "h2db/h2db_store"
require "benchmark"

module Meda

  #ruby service wrapper for profile database
  class ProfileDataStore
	
   	def initialize(config)
      feature = Meda.features.get_feature_service("profile_store")

      case feature
      when "mapdb"
        @store = Meda::MapDbStore.new(config)
      when "hashdb"
        @store = Meda::HashDbStore.new(config)
      when "redisdb"
        @store = Meda::RedisDbStore.new(config)
      when "h2"
        @store = Meda::H2DbStore.new(config)
      else
        raise "feature #{feature} is not implemented"
      end 
    end


    def encode(key,value)
      Meda.logger.debug("starting encode")
      startBenchmark = Time.now.to_f
      @store.encode(key,value)
      endBenchmark = Time.now.to_f
      Meda.logger.debug("ending encode in #{diff_in_ms(startBenchmark,endBenchmark)}ms")
    end

    def key?(key)
      Meda.logger.debug("starting key check")
      startBenchmark = Time.now.to_f
      result = @store.key?(key)
      endBenchmark = Time.now.to_f
      Meda.logger.debug("ending key check  #{diff_in_ms(startBenchmark,endBenchmark)}ms")
      Meda.logger.debug("result #{result}")
      return result
    end

    def decode(key)
      Meda.logger.debug("starting decode")
      startBenchmark = Time.now.to_f
      result = @store.decode(key)
      endBenchmark = Time.now.to_f
      Meda.logger.debug("ending decode #{diff_in_ms(startBenchmark,endBenchmark)}ms")
      return result
    end

    #better ruby benchmark
    def delete(key)
      Meda.logger.debug("starting delete")
      startBenchmark = Time.now.to_f
      @store.delete(key)
      endBenchmark = Time.now.to_f
      Meda.logger.debug("ending delete in  #{diff_in_ms(startBenchmark,endBenchmark)}ms")
    end

    def diff_in_ms(startValue,endValue)
      diff = (endValue - startValue) * 1000
    end
  end
end

