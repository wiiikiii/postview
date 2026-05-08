class User < ApplicationRecord
  has_secure_password

  has_many :api_tokens,    dependent: :destroy
  has_many :magic_links,   dependent: :destroy
  has_many :deleted_rows,  dependent: :destroy

  validates :username, presence: true, uniqueness: { case_sensitive: false }
  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :pg_username, presence: true
  validates :pg_password, presence: true

  def totp
    return nil unless otp_secret.present?

    ROTP::TOTP.new(otp_secret, issuer: "Postview")
  end

  def verify_otp(code)
    return nil unless totp

    totp.verify(code.to_s.delete(" "), drift_behind: 30, drift_ahead: 30)
  end

  def otp_provisioning_uri
    totp&.provisioning_uri(email)
  end

  def generate_otp_secret!
    update!(otp_secret: ROTP::Base32.random)
  end
end
