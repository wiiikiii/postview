class Api::DocsController < ApplicationController
  def show
    @base_url = "#{request.scheme}://#{request.host_with_port}"
    # Users manage tokens on the profile page; nil here so the template uses the profile link
    @token = nil
  end
end
