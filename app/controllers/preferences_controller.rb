class PreferencesController < ApplicationController
  def show
    key = params[:key].to_s
    render json: { key: key, value: current_user.preferences[key] }
  end

  def update
    key   = params[:key].to_s
    value = params[:value]
    return render json: { error: "Missing key" }, status: :bad_request if key.blank?

    prefs      = current_user.preferences.dup
    prefs[key] = value
    current_user.update!(preferences: prefs)
    render json: { ok: true }
  end
end
