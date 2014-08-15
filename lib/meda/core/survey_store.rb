require_relative 'mapdb'
require 'uuidtools'
require 'digest'

module Meda

  # Implements persistence of survey data into the MapDB
  class SurveyStore

    attr_reader :mapdb, :path, :tree

    def initialize(path)
      @path = path
      @mapdb = MapDB::DB.new(path.to_s)
      @tree = @mapdb.tree(:meda)
    end
    
    # Create a new survey with the identifying info in the given hash
    def create_survey(info)
      #creates the id for a new survey
      survey_id = UUIDTools::UUID.timestamp_create.hexdigest
      survey_values = {"id" => survey_id}
      
      # Creates the hash for a survey record
      info.each_pair do |k, v|
        survey_values=survey_values.merge({k => v})
      end
      #adds the record to mapdb with a survey key
      @tree.encode(survey_key(survey_id), survey_values)
      ActiveSupport::HashWithIndifferentAccess.new({"id" => survey_id})
    end
    
    # updates an existing survey or crates a new survey
    def set_survey(survey_info)
      survey_id=survey_info[:id]
      if @tree.key?(survey_key(survey_id)) # if the key exists, do an update
        existing_survey = @tree.decode(survey_key(survey_id))
        @tree.encode(survey_key(survey_id), existing_survey.merge(survey_info)) 
      else
        # if the key doesn't exist, create a new survey
        create_survey(survey_info)
      end
    end
    
     # Returns a specific or all surveys
    def get_survey(survey_id)
      if survey_id.nil? || survey_id.empty? #if survey id is null or blank
        get_all_surveys
      else #if survey id has a value
        get_survey_by_id(survey_id)
      end
    end
    
    #returns a hash array with all surveys
    def get_all_surveys()
      hash_array=Array.new
      #returns all survey keys
      surveyKeys=@tree.keys.select{|k| k.to_s.match("survey")}
      surveyKeys.each do |key|
        #retrieves a hash of the values
        hash=ActiveSupport::HashWithIndifferentAccess.new(@tree.decode(key))
        hash_array.push(hash)
      end
      return hash_array
    end
    
    # Return a hash with the survey info for the given survey_id
    def get_survey_by_id(survey_id)
      if @tree.key?(survey_key(survey_id))
        ActiveSupport::HashWithIndifferentAccess.new(@tree.decode(survey_key(survey_id)))
      else
        false # no survey
      end
    end
    
    # Deletes a specific survey
    def delete_survey(survey_id)
      if @tree.key?(survey_key(survey_id)) 
        @tree.remove(survey_key(survey_id))
      else
        false
      end
    end
    
    # TreeMap key for profile data
    def survey_key(id)
      "survey:#{id}"
    end

  end
end
