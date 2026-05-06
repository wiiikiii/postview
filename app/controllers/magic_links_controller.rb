class MagicLinksController < ApplicationController
  skip_before_action :authenticate!
  skip_before_action :establish_pg_connection

  def new
    # render form
  end

  def create
    user = User.find_by("LOWER(email) = LOWER(?)", params[:email].to_s.strip)

    if user
      _link, raw_token = MagicLink.generate_for(user)
      MagicLinkMailer.magic_link_email(user, raw_token).deliver_later
    end

    flash.now[:notice] = "Falls die E-Mail existiert, wurde ein Magic Link gesendet."
    render :new
  end

  def show
    link = MagicLink.find_valid(params[:token])

    unless link
      redirect_to login_path, alert: "Dieser Magic Link ist ungültig oder abgelaufen."
      return
    end

    link.consume!

    if link.user.otp_enabled?
      session[:pending_2fa_user_id] = link.user.id
      redirect_to two_factor_verify_path
    else
      log_in(link.user)
      redirect_to root_path, notice: "Willkommen, #{link.user.username}!"
    end
  end
end
