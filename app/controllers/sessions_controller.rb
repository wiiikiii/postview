class SessionsController < ApplicationController
  skip_before_action :authenticate!
  skip_before_action :establish_pg_connection

  def new
    redirect_to root_path if current_user
  end

  def create
    user = User.find_by("LOWER(username) = LOWER(?)", params[:username].to_s.strip)

    if user&.authenticate(params[:password])
      if user.otp_enabled?
        session[:pending_2fa_user_id] = user.id
        redirect_to two_factor_verify_path
      else
        log_in(user)
        redirect_to root_path, notice: "Willkommen, #{user.username}!"
      end
    else
      flash.now[:alert] = "Ungültiger Benutzername oder Passwort."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    log_out
    redirect_to login_path, notice: "Sie wurden erfolgreich abgemeldet."
  end
end
