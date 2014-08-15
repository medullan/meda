require 'sinatra/base'
require 'sinatra/cookies'
require 'sinatra/json'
require 'meda'
require 'meda/collector/connection'

module Meda
  module Collector

    # Extends Sinatra:Base to create a Sinatra application implementing the collector's REST API.
    # All operations are delegated to an instance of Meda::Collector::Connection, which implements
    # the desired operation on the given dataset.
    #
    # All routes require the dataset's token to be passed in the "dataset" parameter.
    class App < Sinatra::Base

      set :public_folder, 'static'

      helpers Sinatra::Cookies
      helpers Sinatra::JSON

      # @method get_index
      # @overload get "/"
      # Says hello and gives version number. Useful only to test if service is installed.
      get '/' do
        "Meda version #{Meda::VERSION}"
      end

      # @method get_static
      # @overload get "/static/:file"
      # Serves any files in the project's public directory, usually named "static"
      get '/static/:file' do
        path = File.join(settings.public_folder, params[:file])
        send_file(path)
      end

      # @method post_identify_json
      # @overload post "/identify.json"
      # Identifies the user, and returns a meda profile_id
      post '/identify.json', :provides => :json do
        identify_data = json_from_request
        print_out_params(identify_data)
        profile = settings.connection.identify(identify_data)
        if profile
          json({'profile_id' => profile[:id]})
        else
          respond_with_bad_request
        end
      end

      # @method get_identify_gif
      # @overload get "/identify.gif"
      # Identifies the user, and sets a cookie with the meda profile_id
      get '/identify.gif' do
        profile = settings.connection.identify(params)
        print_out_params(params)
        set_profile_id_in_cookie(profile['id'])
        respond_with_pixel
      end

      # @method post_profile_json
      # @overload post "/profile.json"
      # Sets attributes on the given profile
      post '/profile.json', :provides => :json do
        profile_data = raw_json_from_request
        print_out_params(profile_data)
        result = settings.connection.profile(profile_data)
        if result 
          respond_with_ok
        else
          respond_with_bad_request
        end
      end


      # @method post_getprofile_json
      # @overload post "/getprofile.json"
      # Displays a profile for given profile_id
      # NOTE: This needs to be modified in keeping with the RESTful interface
      # Did not get the time to
      post '/getprofile.json', :provides => :json do
        profile_data = raw_json_from_request
        profile = settings.connection.get_profile_by_id(profile_data)
        if profile 
          profile.to_json
        else
          respond_with_bad_request
        end
      end


      # @method get_profile_gif
      # @overload get "/profile.gif"
      # Sets attributes on the given profile
      get '/profile.gif' do
        get_profile_id_from_cookie
        print_out_params(params)
        settings.connection.profile(params)
        respond_with_pixel
      end

      # @method get_utm_gif
      # @overload get "/:dataset/__utm.gif"
      # Accept google analytics __utm.gif formatted hits
      get '/:dataset/__utm.gif' do
        get_profile_id_from_cookie

        if params[:utmt] == 'event'
          utm_data = event_params_from_utm
          if valid_hit_request?(utm_data)
            settings.connection.track(utm_data)
            respond_with_pixel
          else
            respond_with_bad_request
          end
        else
          utm_data = page_params_from_utm
          if valid_hit_request?(utm_data)
            settings.connection.page(utm_data)
            respond_with_pixel
          else
            respond_with_bad_request
          end
        end
      end

      # @method post_page_json
      # @overload post "/page.json"
      # Record a pageview
      post '/page.json', :provides => :json do
        page_data = json_from_request
        print_out_params(page_data)
        if valid_hit_request?(page_data)
          settings.connection.page(page_data)
          respond_with_ok
        else
          respond_with_bad_request
        end
      end

      # @method get_page_gif
      # @overload get "/page.gif"
      # Record a pageview
      get '/page.gif' do
        if valid_hit_request?(params)
          print_out_params(params)
          get_profile_id_from_cookie
          settings.connection.page(request_environment.merge(params))
          respond_with_pixel
        else
          respond_with_bad_request
        end
      end

      # @method post_track_json
      # @overload post "/track.json"
      # Record an event
      post '/track.json', :provides => :json do
        track_data = json_from_request
        print_out_params(track_data)
        if valid_hit_request?(track_data)
          settings.connection.track(track_data)
          respond_with_ok
        else
          respond_with_bad_request
        end
      end

      # @method get_track_gif
      # @overload get "/track.gif"
      # Record an event
      get '/track.gif' do
        if valid_hit_request?(params)
          print_out_params(params)
          get_profile_id_from_cookie
          settings.connection.track(request_environment.merge(params))
          respond_with_pixel
        else
          respond_with_bad_request
        end
      end
      
      # Creates and updates survey data
      post '/survey.json', :provides => :json do
        survey_data = json_from_request
        settings.connection.survey(survey_data, request)
        respond_with_ok
      end
      
      # Returns surveys
      get '/survey.json', :provides => :json do
        survey_data=params
        survey=settings.connection.survey(survey_data, request)
        
        if survey
          json(survey)
        else
          respond_with_bad_request
        end
      end
      
      # deletes survey data
      delete '/survey.json', :provides => :json do
        survey_data = json_from_request
        settings.connection.survey(survey_data, request)
        respond_with_ok
      end
      
      
      # Config

      configure do
        set :connection, Meda::Collector::Connection.new
      end

      protected

      def json_from_request
        request_environment.merge(raw_json_from_request)
      end

      def raw_json_from_request
        begin
          params_hash = JSON.parse(request.body.read)
          ActiveSupport::HashWithIndifferentAccess.new(params_hash)
        rescue JSON::ParserError => e
          status 422
          json({'error' => 'Request body is invalid'})
        end
      end

      def respond_with_ok
        json({"status" => "ok"})
      end

      def print_out_params(params)
        puts params
      end

      def respond_with_bad_request
        status 400
        json({"status"=>"bad request"})
      end

      def respond_with_pixel
        img_path = File.expand_path('../../../../assets/images/1x1.gif', __FILE__)
        send_file(open(img_path), :type => 'image/gif', :disposition => 'inline')
      end

      def set_profile_id_in_cookie(id)
        cookies[:'_meda_profile_id'] = id
      end

      def get_profile_id_from_cookie
        params[:profile_id] ||= cookies[:'_meda_profile_id']
      end

      def valid_hit_request?(request_params)
        [:dataset, :profile_id, :client_id].all? {|p| request_params[p].present? }
      end

      # Extracts hit params from request environment
      def request_environment
        ActiveSupport::HashWithIndifferentAccess.new({
          :user_ip => remote_ip,
          :referrer => request.referrer,
          :user_agent => request.user_agent
        })
      end

      # Replace Sinatra's default request.ip call.
      # Default gives proxy IPs instead of remote client IP
      def remote_ip
        request.env['HTTP_X_FORWARDED_FOR'].present? ?
          request.env['HTTP_X_FORWARDED_FOR'].strip.split(/[,\s]+/)[0] : request.ip
      end

      # Extracts pageview hit params from __utm request
      def page_params_from_utm
        ActiveSupport::HashWithIndifferentAccess.new({
          :profile_id => cookies[:'_meda_profile_id'],
          :hostname => params[:utmhn],
          :referrer => params[:utmr] || request.referrer,
          :user_ip => params[:utmip] || remote_ip,
          :user_agent => request.user_agent,
          :path => params[:utmp],
          :title => params[:utmdt],
          :user_language => params[:utmul],
          :screen_depth => params[:utmsc],
          :screen_resolution => params[:utmsr]
        })
      end

      # Extracts event hit params from __utm request
      def event_params_from_utm
        parsed_utme = params[:utme].match(/\d\((.+)\*(.+)\*(.+)\*(.+)\)/) # '5(object*action*label*value)'
        ActiveSupport::HashWithIndifferentAccess.new({
          :profile_id => cookies[:'_meda_profile_id'],
          :category => parsed_utme[1],
          :action => parsed_utme[2],
          :label => parsed_utme[3],
          :value => parsed_utme[4],
          :hostname => params[:utmhn],
          :referrer => params[:utmr] || request.referrer,
          :user_ip => params[:utmip] || remote_ip,
          :user_agent => request.user_agent,
          :user_language => params[:utmul],
          :screen_depth => params[:utmsc],
          :screen_resolution => params[:utmsr]
        })
      end

    end

  end
end
