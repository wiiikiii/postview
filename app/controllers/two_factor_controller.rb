class TwoFactorController < ApplicationController
  skip_before_action :authenticate!
  skip_before_action :establish_pg_connection

  def show
    redirect_to login_path unless session[:pending_2fa_user_id]
  end

  def create
    user = User.find_by(id: session[:pending_2fa_user_id])

    unless user
      redirect_to login_path, alert: "Sitzung abgelaufen. Bitte erneut anmelden."
      return
    end

    if user.verify_otp(params[:code])
      session.delete(:pending_2fa_user_id)
      log_in(user)
      redirect_to root_path, notice: "Willkommen, #{user.username}!"
    else
      flash.now[:alert] = "Ungültiger Verifizierungscode. Bitte versuchen Sie es erneut."
      render :show, status: :unprocessable_entity
    end
  end
end
