# ALLChat: starts the OIDC login. Also used as the launch URL of the app in Authentik.
#
# The authorize URL is built here (like the Google button does) because
# devise_token_auth cannot redirect a POST to the OmniAuth request phase.
# The state is stored where OmniAuth's callback phase checks it.
class OidcLoginsController < ActionController::Base
  def new
    return head :not_found unless OidcLogin.enabled?

    state = SecureRandom.hex(24)
    session['omniauth.state'] = state
    query = {
      response_type: 'code',
      client_id: OidcLogin.client_id,
      redirect_uri: OidcLogin.callback_url,
      scope: OidcLogin.scope,
      state: state
    }
    redirect_to "#{OidcLogin.discovery['authorization_endpoint']}?#{query.to_query}", allow_other_host: true
  end
end
