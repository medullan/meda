require 'logger'

module Meda
  module Collector

    # Implements a connection to the meda database. The connection class can be used through the Sinatra app,
    # or standalone for ruby code that is driving a meda instance. Most of the logic for each operation is
    # delegated to an instance of Meda::Dataset.
    #
    # The connection implements thread pools for writing to disk and for transmission to Google Analytics.
    class Connection

      DISK_POOL_DEFAULT = 1
      GA_POOL_DEFAULT = 1

      attr_reader :disk_pool, :ga_pool

      def initialize(options={})
        @options = options
        @disk_pool = options[:disk_pool] || Meda::WorkerPool.new({
          :size => Meda.configuration.disk_pool
        })
        @ga_pool = options[:ga_pool] || Meda::WorkerPool.new({
          :size => Meda.configuration.google_analytics_pool
        })

        Meda.datasets # pre-fetch

        at_exit do
          @disk_pool.shutdown
          @ga_pool.shutdown
        end
      end

      def identify(params)
        process_request(params) do |dataset, user_params|
          dataset.identify_profile(user_params)
        end
      end

      def profile(params)
        process_request(params) do |dataset, profile_params|
          profile_id = profile_params.delete(:profile_id)
          dataset.set_profile(profile_id, profile_params)
        end
      end

      def get_profile_by_id(params)
        process_request(params) do |dataset, profile_params|
          profile_id = profile_params.delete(:profile_id)
          profile = dataset.get_profile(profile_id)
        end
      end

      def delete_profile(params)
        process_request(params) do |dataset, profile_params|
          profile_id = profile_params.delete(:profile_id)
          dataset.delete_profile(profile_id)
        end
      end

      def get_last_hit(params)
        process_request(params) do |dataset, extra_params|
          if dataset.enable_data_retrivals
            last_hit = dataset.last_hit
          else
          #  the default config is not have this enabled. do not log.
          #  logger.info("get_last_hit ==> Data retrieval was not enabled")
          end
        end
      end

      def track(params)

        process_request(params) do |dataset, track_params|
          hit = dataset.add_event(track_params)

          if(hit.is_invalid)
            logger.info("track ==> Invalid hit")
            return false
          end

          disk_pool.submit do
            dataset.stream_hit_to_disk(hit)
          end

          if dataset.stream_to_ga?
            ga_pool.submit do
              dataset.stream_hit_to_ga(hit)
            end
          else
            logger.info("track ==> Data did not stream to GA")
          end
        end
        true
      end

      def page(params)

        process_request(params) do |dataset, page_params|
          hit = dataset.add_pageview(page_params)
          hit.request_id = Thread.current[:request_uuid]

          if(hit.is_invalid)
            logger.info("page ==> Invalid hit")
            return false
          end

          disk_pool.submit do
            Thread.current[:request_uuid] = hit.request_id
            dataset.stream_hit_to_disk(hit)
          end

          if dataset.stream_to_ga?
            ga_pool.submit do
              Thread.current[:request_uuid] = hit.request_id
              dataset.stream_hit_to_ga(hit)
            end
          else
            logger.info("page ==> Data did not stream to GA")
          end
        end
        true
      end

      def join_threads(&block)
        while @disk_pool.active? || @ga_pool.active? do
        end
        yield if block_given?
      end

      protected

      def process_request(params, &block)
        begin
          dataset, other_params = extract_dataset_from_params(params)
          yield(dataset, other_params) if block_given?
        rescue StandardError => e
          puts Meda.logger
          Meda.logger.error(e) if Meda.logger
          puts e
          raise e
        end
      end

      def extract_dataset_from_params(params)
        if params[:dataset].blank?
          raise 'Cannot find dataset. Token param blank.'
        end

        extra_params = params.symbolize_keys
        extra_params[:user_ip] = mask_ip(extra_params[:user_ip]) if extra_params[:user_ip]
        token = extra_params.delete(:dataset)
        dataset = Meda.datasets[token]
        if dataset
          return dataset, extra_params
        else
          raise "No dataset found for token param #{token}"
        end
      end

      # De-identifies an IP address by zero-ing out the final octet
      def mask_ip(ip)
        subnet, match, hostname = ip.rpartition('.')
        return subnet + '.0'
      end

      def logger
        @logger ||= Meda.logger || Logger.new(STDOUT)
      end

    end
  end
end
