require File.dirname(File.absolute_path(__FILE__)) + '/meda/version.rb'
Dir.glob(File.dirname(File.absolute_path(__FILE__)) + '/meda/core/*.rb') {|file| require file}
require "active_support/all"
require 'psych'
require 'pathname'

module Meda

  MEDA_CONFIG_FILE = 'meda.yml'
  DATASETS_CONFIG_FILE = 'datasets.yml'

  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
    datasets
    logger
    true
  end

  def self.logger
    if @logger.nil? && Meda.configuration.log_path.present?
      FileUtils.mkdir_p(File.dirname(Meda.configuration.log_path))
      FileUtils.touch(Meda.configuration.log_path)
      @logger = Meda::LoggingService.new(Meda.configuration.log_path)
      @logger.level = Meda.configuration.log_level || Logger::INFO
    end
    @logger
  end

  def self.datasets
    if @datasets.nil?
      @datasets = {}
      begin
        config = Psych.load(File.open(Meda::DATASETS_CONFIG_FILE))
        config.each do |d_name, d_config|
          begin
            puts "#{d_name} dataset configuration started"
            d = Meda::Dataset.new(d_name, Meda.configuration)
            d_config.each_pair { |key, val| d.send("#{key}=", val) } 
     
            configure_custom_filter(d)
         
            @datasets[d.token] = d
            puts "#{d_name} dataset configuration completed"
          rescue Exception => e
            puts "Error: datasets.yml is incorrectly setup, please review - #{e.message}"
          end
        end
      rescue Errno::ENOENT => error
        puts "Error: datasets.yml is incorrect, please review - #{error.message}"
      end
    end
    @datasets
  end

  def self.configure_custom_filter(dataset)
    if(dataset.filter_file_name.nil? || dataset.filter_class_name.nil?)
      puts "no custom filters to configure"
      puts dataset.hit_filter
      return
    end


    
    custom_filter_file_path = Pathname.new dataset.filter_file_name
    require(custom_filter_file_path.realpath)
    filter = dataset.filter_class_name.constantize.new
    dataset.hit_filter = filter
  end  

  class Configuration

    DEFAULTS = {
      :mapdb_path => File.join(Dir.pwd, 'db'),
      :data_path => File.join(Dir.pwd, 'data'),
      :log_path => File.join(Dir.pwd, 'log/server.log'),
      :log_level => 1,
      :disk_pool => 2,
      :google_analytics_pool => 2
    }

    attr_accessor :mapdb_path, :data_path, :log_path, :log_level, :disk_pool, :google_analytics_pool

    def initialize
      DEFAULTS.each do |key,val|
        self[key] = val
      end
    end

    def []=(key, val)
      send("#{key}=", val)
    end
  end
end

Meda.configure do |config|
  begin
    app_config = Psych.load(File.open(Meda::MEDA_CONFIG_FILE))[ENV['RACK_ENV'] || 'development']
    app_config.each_pair { |key, val| config[key] = val }
  rescue Errno::ENOENT => error
    puts "Warning: Missing meda.yml, please configure manually #{error.message}"
  end
end

Meda

