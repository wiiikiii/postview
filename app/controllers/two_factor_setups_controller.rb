class TwoFactorSetupsController < ApplicationController
  def new
    unless current_user.otp_enabled?
      current_user.generate_otp_secret! unless current_user.otp_secret.present?
    end

    @qr_code = RQRCode::QRCode.new(current_user.otp_provisioning_uri)
                              .as_svg(viewbox: true, svg_attributes: { class: "w-48 h-48" })
    @otp_secret = current_user.otp_secret
  end

  def create
    if current_user.verify_otp(params[:code])
      current_user.update!(otp_enabled: true)
      redirect_to profile_path, notice: "Zwei-Faktor-Authentifizierung wurde erfolgreich aktiviert."
    else
      flash.now[:alert] = "Ungültiger Code. Bitte versuchen Sie es erneut."
      @qr_code = RQRCode::QRCode.new(current_user.otp_provisioning_uri)
                                .as_svg(viewbox: true, svg_attributes: { class: "w-48 h-48" })
      @otp_secret = current_user.otp_secret
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    if current_user.verify_otp(params[:code])
      current_user.update!(otp_enabled: false, otp_secret: nil)
      redirect_to profile_path, notice: "Zwei-Faktor-Authentifizierung wurde deaktiviert."
    else
      redirect_to profile_path, alert: "Ungültiger Code. 2FA wurde nicht deaktiviert."
    end
  end
end
