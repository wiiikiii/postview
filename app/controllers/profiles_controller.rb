class ProfilesController < ApplicationController
  def show
    @api_tokens = current_user.api_tokens.order(created_at: :desc)
  end

  def update
    permitted = params.require(:user).permit(:username, :email, :pg_username, :pg_password, :password, :password_confirmation)

    # Remove blank password fields so they don't override existing password
    if permitted[:password].blank?
      permitted = permitted.except(:password, :password_confirmation)
    end

    # Remove blank pg_password so it doesn't override existing
    permitted = permitted.except(:pg_password) if permitted[:pg_password].blank?

    if current_user.update(permitted)
      # Update session pg credentials if they changed
      session[:pg_username] = current_user.pg_username
      session[:pg_password] = current_user.pg_password
      redirect_to profile_path, notice: "Profil erfolgreich aktualisiert."
    else
      @api_tokens = current_user.api_tokens.order(created_at: :desc)
      flash.now[:alert] = current_user.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end
end
