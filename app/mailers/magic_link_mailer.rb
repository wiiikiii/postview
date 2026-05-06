class MagicLinkMailer < ApplicationMailer
  def magic_link_email(user, raw_token)
    @user      = user
    @login_url = magic_link_verify_url(token: raw_token)
    @expires_in = MagicLink::EXPIRY / 60

    mail(to: user.email, subject: "Dein Postview Login-Link")
  end
end
