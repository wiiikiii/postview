class MagicLink < ApplicationRecord
  belongs_to :user

  EXPIRY = 15.minutes

  def self.generate_for(user)
    raw = SecureRandom.hex(32)
    link = create!(
      user: user,
      token_digest: digest(raw),
      expires_at: EXPIRY.from_now
    )
    [ link, raw ]
  end

  def self.find_valid(raw)
    return nil if raw.blank?

    find_by(token_digest: digest(raw))
      &.then { |link| (link.used_at.nil? && !link.expired?) ? link : nil }
  end

  def consume!
    update!(used_at: Time.current)
  end

  def expired?
    expires_at < Time.current
  end

  private

  def self.digest(raw)
    OpenSSL::Digest::SHA256.hexdigest(raw)
  end
end
