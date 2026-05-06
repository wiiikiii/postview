class ApiTokensController < ApplicationController
  def index
    redirect_to profile_path
  end

  def create
    token = current_user.api_tokens.build(
      name: params[:name].to_s.strip,
      expires_at: params[:expires_at].presence
    )

    if token.save
      flash[:notice] = "API-Token '#{token.name}' wurde erstellt. " \
                       "Ihr Token (wird nur einmal angezeigt): #{token.raw_token}"
    else
      flash[:alert] = token.errors.full_messages.to_sentence
    end

    redirect_to profile_path
  end

  def destroy
    token = current_user.api_tokens.find_by(id: params[:id])

    if token
      token.destroy
      flash[:notice] = "API-Token wurde gelöscht."
    else
      flash[:alert] = "Token nicht gefunden."
    end

    redirect_to profile_path
  end
end
