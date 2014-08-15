require 'ostruct'
require 'uuidtools'
require 'digest'
require 'csv'
require 'securerandom'
require 'staccato'
require 'logger'

module Meda

  # Dataset manages a single "bucket" of data in a meda instance.
  # Each Dataset has its own configuration, and its data is stored in a separate DB.
  # This class implements most of the logic for each operation (identify, track, etc),
  # and also the logic for writing to disk and Google Analytics.
  class Dataset

    attr_reader :data_uuid, :name, :meda_config
    attr_accessor :google_analytics, :token

    # Readers primarily used for tests, not especially thread-safe :p
    attr_reader :last_hit, :last_disk_hit, :last_ga_hit

    def initialize(name, meda_config={})
      @name = name
      @meda_config = meda_config
      @data_uuid = UUIDTools::UUID.timestamp_create.hexdigest
      @data_paths = {}
      @after_identify = lambda {|dataset, user| }
    end

    def identify_profile(info)
      profile = store.find_or_create_profile(info)
      @after_identify.call(self, profile)
      return profile
    end

    def add_event(event_props)
      event_props[:time] ||= DateTime.now.to_s
      event_props[:category] ||= 'none'
      event = Meda::Event.new(event_props)
      add_hit(event)
    end

    def add_pageview(page_props)
      page_props[:time] ||= DateTime.now.to_s
      pageview = Meda::Pageview.new(page_props)
      add_hit(pageview)
    end

    def add_hit(hit)
      hit.id = UUIDTools::UUID.timestamp_create.hexdigest
      hit.dataset = self
      if hit.profile_id
        profile = store.get_profile_by_id(hit.profile_id)
        if profile
          profile.delete('id')
          hit.profile_props = profile
        end
      else
        # Hit has no profile
        # Leave it anonymous-ish for now. Figure out what to do later.
      end
      @last_hit = hit
      hit.validate! # blows up if missing attrs
      hit
    end

    def set_profile(profile_id, profile_info)
      store.set_profile(profile_id, profile_info)
    end
    
    #Adds a new survey or updates an existing survey
    def set_survey(survey_info)
      surveyStore.set_survey(survey_info)
    end
    
    #returns surveys
    def return_survey(survey_id)
      survey=surveyStore.get_survey(survey_id)
      return survey
    end
    
    #removes an existing survey
    def remove_survey(survey_id)
      surveyStore.delete_survey(survey_id)
    end

    def get_profile(profile_id)
      store.get_profile_by_id(profile_id)
    end

    def stream_to_ga?
      !!google_analytics && !!google_analytics['record']
    end

    def stream_hit_to_disk(hit)
      directory = File.join(meda_config.data_path, path_name, hit.hit_type_plural, hit.day) # i.e. 'meda_data/name/events/2014-04-01'
      unless @data_paths[directory]
        # create the data directory if it does not exist
        @data_paths[directory] = FileUtils.mkdir_p(directory)
      end
      filename = "#{hit.hour}-#{self.data_uuid}.json"
      path = File.join(directory, filename)
      begin
        File.open(path, 'a') do |f|
          f.puts(hit.to_json)
        end
        @last_disk_hit = {
          :hit => hit, :path => path, :data => hit.to_json
        }
        logger.debug("Writing hit #{hit.id} to #{path}")
      rescue StandardError => e
        logger.error("Failure writing hit #{hit.id} to #{path}")
        logger.error(e)
        raise e
      end
      true
    end

    def stream_hit_to_ga(hit)
      @last_ga_hit = {:hit => hit, :staccato_hit => nil, :response => nil}
      return unless stream_to_ga?
      tracker = Staccato.tracker(google_analytics['tracking_id'], hit.profile_id)
      begin
        if hit.hit_type == 'pageview'
          ga_hit = Staccato::Pageview.new(tracker, hit.as_ga)
        elsif hit.hit_type == 'event'
          ga_hit = Staccato::Event.new(tracker, hit.as_ga)
        end
        google_analytics['custom_dimensions'].each_pair do |dim, val|
          #The naming of profile fields in the json request to fields in the dataset.yml must be identical 
          #The index of cust. dim fields in the datasets.yml must be the same for the index of custom dimensions in GA 
          #puts("Dimension: #{dim} - Index #{val['index']} - Mapped Value: #{hit.profile_props[dim]}")
          ga_hit.add_custom_dimension(val['index'], hit.profile_props[dim])
        end
        @last_ga_hit[:staccato_hit] = ga_hit
        @last_ga_hit[:response] = ga_hit.track!
        logger.debug("Writing hit #{hit.id} to Google Analytics")
        logger.debug(ga_hit.inspect)
      rescue StandardError => e
        logger.error("Failure writing hit #{hit.id} to GA")
        logger.error(e)
        raise e
      end
      true
    end

    def after_identify(&block)
      @after_identify = block
    end

    def path_name
      name.downcase.gsub(' ', '_')
    end

    def store
      if @profile_store.nil?
        FileUtils.mkdir_p(meda_config.mapdb_path)
        mapdb_path = File.join(meda_config.mapdb_path, path_name)
        @profile_store = Meda::ProfileStore.new(mapdb_path)
      end
      @profile_store
    end
    
    def surveyStore
      if @survey_store.nil?
        FileUtils.mkdir_p(meda_config.mapdb_path)
        mapdb_path = File.join(meda_config.mapdb_path, path_name)
        @survey_store = Meda::SurveyStore.new(mapdb_path)
      end
      @survey_store
    end

    protected

    def logger
      @logger ||= Meda.logger || Logger.new(STDOUT)
    end

  end
end
