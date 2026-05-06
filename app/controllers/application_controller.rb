class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate!
  before_action :establish_pg_connection

  helper_method :current_user

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id])
  end

  private

  def authenticate!
    redirect_to login_path, alert: "Bitte melden Sie sich an." unless current_user
  end

  def log_in(user)
    session[:user_id]      = user.id
    session[:pg_username]  = user.pg_username
    session[:pg_password]  = user.pg_password
  end

  def log_out
    session.delete(:user_id)
    session.delete(:pg_username)
    session.delete(:pg_password)
    session.delete(:pending_2fa_user_id)
    @current_user = nil
    ActiveRecord::Base.establish_connection(Rails.env.to_sym)
  end

  def establish_pg_connection
    return unless current_user

    pg_user = session[:pg_username]
    pg_pass = session[:pg_password]
    return unless pg_user.present?

    base_config = ApplicationRecord.connection_db_config.configuration_hash
    config = base_config.merge(username: pg_user, password: pg_pass, pool: 5)
    ActiveRecord::Base.establish_connection(config)
    ActiveRecord::Base.connection.execute("SELECT 1")
  rescue PG::Error, ActiveRecord::StatementInvalid => e
    log_out
    redirect_to login_path, alert: "PostgreSQL-Verbindung fehlgeschlagen: #{e.message.split("\n").first}"
  end
end
