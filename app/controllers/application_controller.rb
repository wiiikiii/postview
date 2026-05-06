class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate

  private

  def authenticate
    authenticate_or_request_with_http_basic("Postview") do |username, password|
      config = ActiveRecord::Base.connection_db_config.configuration_hash
                                 .merge(username: username, password: password, pool: 5)
      ActiveRecord::Base.establish_connection(config)
      ActiveRecord::Base.connection.execute("SELECT 1")
      @current_user = username
      true
    rescue PG::Error, ActiveRecord::StatementInvalid
      false
    end
  rescue StandardError
    false
  end

  def current_user
    @current_user
  end
  helper_method :current_user
end
