class ApplicationController < ActionController::Base

  protect_from_forgery with: :exception
  
  before_action :authenticate

  class Dbconnect < ActiveRecord::Base
    def self.set_table_name 
      "pg_roles"
    end
  end

  def authenticate
    authenticate_or_request_with_http_basic('Database login') do |username, password|
      config = Dbconnect.connection.instance_eval { @config }
      if username != config[:user] || !Dbconnect.connected?
        logger.debug "Connect as user: #{username}"
        Dbconnect.establish_connection(config.merge(:username => username, :password => password))
        Dbconnect.connection.execute("SELECT now()") rescue nil #force connection
      end
      login_ok = Dbconnect.connected?
      @current_user = username if login_ok
      login_ok
    end
  rescue
    false
  end

  def logout
    @realm = 'Login Required'
    response.headers["Status"] = "Unauthorized"
    response.headers["WWW-Authenticate"] = "Basic realm=\"#{@realm}\""
    render :text => '', :status => 401
  end

  def current_user
    @current_user ||= nil
  end

  private
  
  def db_schema_tables_select
    if params[:database_name]
      @database = Database.find_by_name(params[:database_name])
      params[:schema_name] ||= 'public'
      @db_schema = @database.find_schema_by_name(params[:schema_name])
      @tables = @db_schema.tables
    end
  end
  
end
