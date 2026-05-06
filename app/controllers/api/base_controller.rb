class Api::BaseController < ActionController::API
  before_action :authenticate_api_token!

  private

  def authenticate_api_token!
    raw = request.headers["Authorization"]&.delete_prefix("Bearer ")&.strip
    return render json: { error: "Unauthorized" }, status: :unauthorized if raw.blank?

    @api_token = ApiToken.authenticate(raw)
    return render json: { error: "Invalid or expired token" }, status: :unauthorized unless @api_token&.active?

    @current_user = @api_token.user
    establish_pg_connection
  end

  def establish_pg_connection
    config = ActiveRecord::Base.connection_db_config.configuration_hash
               .merge(username: @current_user.pg_username, password: @current_user.pg_password, pool: 5)
    ActiveRecord::Base.establish_connection(config)
    ActiveRecord::Base.connection.execute("SELECT 1")
  rescue PG::Error, ActiveRecord::StatementInvalid => e
    render json: { error: "PostgreSQL connection failed" }, status: :service_unavailable
  end
end
