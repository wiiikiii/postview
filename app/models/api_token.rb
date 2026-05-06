class ApiToken < ApplicationRecord
  belongs_to :user

  validates :name, presence: true

  attr_reader :raw_token

  before_create :set_token_digest

  def self.authenticate(raw)
    return nil if raw.blank?

    find_by(token_digest: digest(raw))&.tap { |t| t.touch(:last_used_at) }
  end

  def self.digest(raw)
    OpenSSL::Digest::SHA256.hexdigest(raw)
  end

  def active?
    expires_at.nil? || expires_at.future?
  end

  private

  def set_token_digest
    token = SecureRandom.hex(32)
    @raw_token = token
    self.token_digest = self.class.digest(token)
  end
end
