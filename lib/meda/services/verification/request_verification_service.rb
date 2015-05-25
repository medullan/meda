require_relative '../profile/profile_service.rb'
require_relative '../datastore/profile_data_store.rb'
require 'uuidtools'
require 'logger'
require 'meda'
require 'json'

module Meda

  #RequestVerificationService used for the Request Verification API (RVA)
  class RequestVerificationService
    @@prefix = "rva-" #used to differentiate qa logs from profile ids
    @@thread_key = "meda_rva_id" #key used to store RVA id in the thread
    # @@profile_service= Meda::ProfileService.new(Meda.configuration)
    def initialize(config)

      @config=config

      @@profile_data_store = Meda::ProfileDataStore.new(config)
    end
    ### public ###
    def start_rva_log (type, data, request, cookies, params = nil)
      if Meda.features.is_enabled("verification_api", false)
        rva_id = set_transaction_id()
        profile_id = data.key?(:profile_id) ? data[:profile_id] : cookies["_meda_profile_id"]
        client_id = cookies['__collector_client_id']
        # start_time
        rva_data = {
            :id => rva_id,
            :profile_id => profile_id, :client_id => client_id,
            :type => type,
            :http => {:start_time=> data[:start_time], :end_time=> nil,:url => request.url, :method => request.request_method, :request_input => nil || params, :response=>nil}
        }
        @@profile_data_store.encode_collection(@config.verification_api['collection_name'], rva_id, rva_data )
      end
    end

    def end_rva_log (response=nil)
      if Meda.features.is_enabled("verification_api", false)
        rva_id = get_rva_id()
        rva_data = @@profile_data_store.decode_collection_filter_by_key(@config.verification_api['collection_name'], rva_id )
        rva_data[:http][:end_time] = Time.now.to_s
        rva_data[:http][:response] = response
        @@profile_data_store.encode_collection(@config.verification_api['collection_name'], rva_id, rva_data )
      end
    end


    def add_json_ref(ref)
      rva_data =  @@profile_data_store.decode_collection_filter_by_key( @config.verification_api['collection_name'], get_rva_id() )
      data = add_data_source('transaction_ids',
                             rva_data,
                             'json',
                             ref)
      @@profile_data_store.encode_collection(@config.verification_api['collection_name'], get_rva_id(), data )
      return data
    end

    def add_ga_data(ref)
      rva_data =  @@profile_data_store.decode_collection_filter_by_key( @config.verification_api['collection_name'], get_rva_id() )
      data = add_data_source('data',
                             rva_data,
                             'ga',
                             ref)
      @@profile_data_store.encode_collection(@config.verification_api['collection_name'], get_rva_id(), data )
      return data
    end

    def get_rva_id()
      id =   Thread.current.thread_variable_get(@config.verification_api['thread_id_key'])
          #Thread.current["#{@config.verification_api['thread_id_key']}" ]
      # puts "the rva id: #{id} , #{@config.verification_api['thread_id_key']},  #{Thread.current.to_json}"
      return id
    end

    def build_rva_log
      built_list = []
      all_json = get_all_json_data(@config.data_path)
      all_rva_data =  @@profile_data_store.decode_collection(@config.verification_api['collection_name'])

      all_rva_data.each { |rva_data|
        json = get_related_json_data(all_json, rva_data, 'json')
        rva_data = add_data_source('data',
                               rva_data,
                               'json',
                               json)
        built_list.push(rva_data)
      }
      return built_list
    end

    #################
    ### private ###

    def add_data_source(operation_key, rva_data, type, ref)
      # puts "saving source with: #{operation_key} , #{type}, #{ref}"

      if rva_data != nil
        temp = {}
        if rva_data.has_key?(operation_key.to_sym)
          temp = temp.merge(rva_data[operation_key.to_sym])
        end
        ref_hash = {type.to_sym => ref}
        temp = temp.merge(ref_hash)
        rva_data = rva_data.merge!(operation_key.to_sym => temp)
      end
      return rva_data
    end


    def set_transaction_id(id = nil)
      uuid = id || generate_transaction_id()
      Thread.current.thread_variable_set(@config.verification_api['thread_id_key'], uuid)
      return uuid
    end



    def generate_transaction_id()
      uuid = UUIDTools::UUID.random_create.to_s #timestamp_create.hexdigest
      uuid = "#{@config.verification_api['id_prefix']}#{uuid}"
      return uuid
    end

    # This will parse a meda json file (syntax: one JSON object per line)
    #@param file_path - this is the file path of the meda JSON
    #@returns json_list::Array -list of json objects parsed
    def parse_meda_json(file_path)
      json_list = []
      File.open(file_path, "r").each_line do |line|
        json_list.push JSON.parse(line)
      end
      return json_list
    end

    # This retrieve a list of all json file paths within the meta data directory
    #@param base_path - this is the base path of the meda JSON directory
    #@returns json_files::Array - list of json file paths found
    def get_json_filepaths(base_path)
      glob = '**/*.json'
      file_path = "#{base_path}/#{@config.env}/#{glob}"
      json_files = Dir.glob(file_path)
      return json_files
    end

    # This will parse all meda json files within the meta data folder (syntax: one JSON object per line)
    #@param base_path - this is the file path of the meda JSON
    #@returns json_list::Array - list of json objects parsed
    def get_all_json_data(base_path)
      json_files = get_json_filepaths(base_path)
      json_list = []
      json_files.each  { |path|
        json_list.concat(parse_meda_json(path))
      }
      return json_list
    end


    def get_related_json_data(json_list, rva_data, source_type)
      match = {}
      found = false
      json_list.each { |json_data|
        if rva_data.has_key?(:transaction_ids)
          if json_data['id'].eql? rva_data[:transaction_ids][source_type.to_sym]
            match = json_data
            found = true
          end
        end
        break if found === true
      }
      if found
        return match
      else
        return nil
      end
    end

  end


end