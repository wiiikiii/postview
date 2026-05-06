class ApplicationMailer < ActionMailer::Base
  default from: Rails.application.credentials.dig(:mailer, :from) ||
                ENV.fetch("MAILER_FROM", "Postview <noreply@postview.local>")
  layout "mailer"
end
