require 'logger'
require 'logging'
require 'json'
require 'logstash-logger'
require_relative './email_logging_service.rb'
module Meda

  class LoggingService
	
	  def features
      @features ||= Meda.features
    end

   	def initialize(config)
      @loggers = []
      @level = config.log_level || Logger::INFO

      FileUtils.mkdir_p(File.dirname(config.log_path))
      FileUtils.touch(config.log_path)

      setup_file_logger(config)
      setup_additional_error_logger(config)
      setup_console_logger(config)
      setup_logstash_logger(config)
      puts "#{@loggers.length.to_s} loggers have been setup"
    end

    def setup_file_logger(config)

      if features.is_enabled("all_log_file_logger",false)
        FileUtils.mkdir_p(File.dirname(config.log_path))
        FileUtils.touch(config.log_path)

        filename = config.logs["all_log_path"]

        loggingLevel = config.log_level || Logger::INFO
        @file_logger = Logger.new(filename, config.logs["file_history"], config.logs["file_maxsize"])

        @file_logger.formatter = proc do |severity, datetime, progname, msg|
           "#{msg}\n"
        end
        @file_logger.level = loggingLevel
        @loggers.push(@file_logger)
        puts "file logger setup at #{filename}"
      end
    end

    def setup_additional_error_logger(config)
      if features.is_enabled("error_file_logger",false)
        FileUtils.mkdir_p(File.dirname(config.log_path))
        FileUtils.touch(config.log_path)

        filename = config.logs["error_log_path"]

        loggingLevel = Logger::ERROR
        @error_file_logger = Logger.new(filename, config.logs["file_history"], config.logs["file_maxsize"])
        
        @error_file_logger.formatter = proc do |severity, datetime, progname, msg|
           "#{msg}\n"
        end
        @error_file_logger.level = loggingLevel
        @loggers.push(@error_file_logger)
        puts "error file logger setup at #{filename}"
      end

    end

    def setup_console_logger(config)
      if features.is_enabled("stdout_logger",false)
        loggingLevel = config.log_level || Logger::INFO
        @console_logger = Logger.new(STDOUT, 10, 1024000)

        @console_logger.formatter = proc do |severity, datetime, progname, msg|
           "#{msg}\n\n"
        end
        @console_logger.level = loggingLevel
        @loggers.push(@console_logger)
        puts "console logger setup"
      end
    end

    def setup_logstash_logger(config)
      if features.is_enabled("logstash_logger", false)
        host = ENV['LOGSTASH_HOST'] || config.logs['logstash_host']
        port = ENV['LOGSTASH_PORT'] || config.logs['logstash_port']
        @logstash_logger = LogStashLogger.new(type: :tcp, host: host.to_s, port: port)
        @loggers.push(@logstash_logger)
        puts "logstash logger setup, sending logs to HOST: #{host} and PORT: #{port}"
      end
    end

    def setup_email_error_logger(config)
      if features.is_enabled("error_email_logger",false)
        @email_error_logger = Meda::EmailLoggingService.new(config)
        @loggers.push(@email_error_logger)
        puts "email error logger setup"
      end
    end

    def setup_postgres_logger(config)
      if features.is_enabled("logs_postgres",false)
          require_relative 'postgres_logging_service.rb' 
          @postgres_logger = Meda::PostgresLoggingService.new(config)
          @loggers.push(@postgres_logger)
          puts "postgres logger setup"
        end
    end

    def update_log_level(log_level)
      @level = log_level

      if !@file_logger.blank? && !@file_logger.level.blank?
        @file_logger.level = log_level
      end

      if !@console_logger.blank? && !@console_logger.level.blank?
        @console_logger.level = log_level
      end
    end

  	def error(message)
  		message = add_meta_data(message,"error")
  		 @loggers.each do |logger|
        logger.error(message)  
       end
  	end

  	def warn(message)
  		if @level <= 2
	  		message = add_meta_data(message,"warn")
        @loggers.each do |logger|
          logger.warn(message)  
       end
  		end
  	end


  	def info(message)	
  		if @level <= 1
	  		message = add_meta_data(message,"info")
	  		
      @loggers.each do |logger|
          logger.info(message)  
       end
  		end
  	end


  	def debug(message)
		if @level <= 0
	  		message = add_meta_data(message,"debug")

        @loggers.each do |logger|
          logger.debug(message)  
       end
  		end
  	end

  	def add_meta_data(message,severity)

      hash = Hash.new()
      hash["message"] = message
      hash["severity"] = severity
      hash["file"] = caller.second.split(":in")
      hash["timestamp"] = Time.now
      hash["thread"] = Thread.current.object_id.to_s
		  hash["stacktrace"] = message.backtrace if message.respond_to?(:backtrace)
      hash["message"] = message.message if message.respond_to?(:message)

      if(Logging.mdc["meta_logs"].to_s.length>0)
        meta_logs = JSON.parse Logging.mdc["meta_logs"].to_s
        hash = hash.merge(meta_logs)
      end
      
      hash.to_json
  	end
  end
end



