# ALLChat: login via OpenID Connect (Authentik or any OIDC provider).
#
# Enabled when OIDC_ISSUER, OIDC_CLIENT_ID and OIDC_CLIENT_SECRET are set.
# The provider endpoints come from the issuer's discovery document.
require 'omniauth-oauth2'

module OidcLogin
  module_function

  def enabled?
    issuer.present? && client_id.present? && client_secret.present?
  end

  def issuer
    value = ENV.fetch('OIDC_ISSUER', '').strip
    return if value.blank?

    value.end_with?('/') ? value : "#{value}/"
  end

  def client_id
    ENV.fetch('OIDC_CLIENT_ID', nil)
  end

  def client_secret
    ENV.fetch('OIDC_CLIENT_SECRET', nil)
  end

  def scope
    ENV.fetch('OIDC_SCOPE', 'openid email profile')
  end

  def button_label
    ENV.fetch('OIDC_BUTTON_LABEL', 'Entrar com SSO')
  end

  def callback_url
    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/omniauth/oidc/callback"
  end

  def auto_create_users?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('OIDC_AUTO_CREATE_USERS', false))
  end

  def account_id
    ENV.fetch('OIDC_ACCOUNT_ID', '1')
  end

  def admin_groups
    group_list('OIDC_ADMIN_GROUPS')
  end

  def supervisor_groups
    group_list('OIDC_SUPERVISOR_GROUPS')
  end

  def group_list(env_key)
    ENV.fetch(env_key, '').split(',').map(&:strip).compact_blank
  end

  def discovery
    @discovery ||= begin
      response = Net::HTTP.get_response(URI.join(issuer, '.well-known/openid-configuration'))
      response.value
      JSON.parse(response.body)
    end
  end

  class Strategy < OmniAuth::Strategies::OAuth2
    option :name, 'oidc'

    uid { raw_info['sub'] }

    # devise_token_auth drops `extra` when it stores the auth hash in the session,
    # so everything the callback needs (including groups) lives in `info`.
    info do
      {
        email: raw_info['email'],
        name: raw_info['name'].presence || raw_info['preferred_username'],
        nickname: raw_info['preferred_username'],
        image: raw_info['picture'],
        email_verified: raw_info['email_verified'],
        groups: Array(raw_info['groups'])
      }
    end

    def request_phase
      return fail!(:oidc_disabled) unless OidcLogin.enabled?

      super
    end

    def callback_phase
      return fail!(:oidc_disabled) unless OidcLogin.enabled?

      super
    end

    def client
      options.client_options.site = OidcLogin.issuer
      options.client_options.authorize_url = OidcLogin.discovery['authorization_endpoint']
      options.client_options.token_url = OidcLogin.discovery['token_endpoint']
      super
    end

    def raw_info
      @raw_info ||= access_token.get(OidcLogin.discovery['userinfo_endpoint']).parsed
    end

    # Must match exactly the redirect_uri sent by OidcLoginsController#new.
    def callback_url
      OidcLogin.callback_url
    end
  end
end
