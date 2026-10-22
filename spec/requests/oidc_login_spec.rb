require 'rails_helper'

RSpec.describe 'ALLChat OIDC login', type: :request do
  let(:account) { create(:account) }
  let(:frontend_url) { 'http://www.example.com' }
  let(:discovery) do
    {
      'authorization_endpoint' => 'https://auth.example.com/application/o/authorize/',
      'token_endpoint' => 'https://auth.example.com/application/o/token/',
      'userinfo_endpoint' => 'https://auth.example.com/application/o/userinfo/'
    }
  end
  let(:oidc_env) do
    {
      OIDC_ISSUER: 'https://auth.example.com/application/o/allchat/',
      OIDC_CLIENT_ID: 'client-id',
      OIDC_CLIENT_SECRET: 'client-secret',
      FRONTEND_URL: frontend_url
    }
  end

  before do
    allow(OidcLogin).to receive(:discovery).and_return(discovery)
  end

  after do
    OmniAuth.config.mock_auth[:oidc] = nil
  end

  describe 'GET /sso/oidc' do
    it 'redirects to the provider authorize endpoint with a state' do
      with_modified_env(**oidc_env) do
        get '/sso/oidc'

        location = URI.parse(response.location)
        query = Rack::Utils.parse_query(location.query)
        expect(response).to have_http_status(:redirect)
        expect("#{location.scheme}://#{location.host}#{location.path}").to eq(discovery['authorization_endpoint'])
        expect(query).to include(
          'client_id' => 'client-id',
          'redirect_uri' => "#{frontend_url}/omniauth/oidc/callback",
          'response_type' => 'code',
          'scope' => 'openid email profile'
        )
        expect(query['state']).to be_present
      end
    end

    it 'returns not found when OIDC is not configured' do
      get '/sso/oidc'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'callback' do
    def mock_oidc_auth(email:, groups: [])
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(
        provider: 'oidc',
        uid: 'authentik-sub',
        info: { email: email, name: 'Maria Silva', groups: groups }
      )
    end

    it 'signs in an existing user with the SSO token' do
      user = create(:user, account: account, email: 'maria@alltecnologias.com.br')
      mock_oidc_auth(email: user.email)

      with_modified_env(**oidc_env) do
        get '/omniauth/oidc/callback'
        follow_redirect!

        expect(response).to redirect_to(%r{/app/login\?.*sso_auth_token=})
      end
    end

    it 'redirects with an error when the user does not exist and auto creation is off' do
      mock_oidc_auth(email: 'nobody@alltecnologias.com.br')

      with_modified_env(**oidc_env) do
        get '/omniauth/oidc/callback'
        follow_redirect!

        expect(response).to redirect_to(%r{/app/login\?error=no-account-found})
        expect(User.from_email('nobody@alltecnologias.com.br')).to be_nil
      end
    end

    it 'creates the agent with the role from the provider groups when auto creation is on' do
      mock_oidc_auth(email: 'novo@alltecnologias.com.br', groups: %w[allchat allchat-supervisor])

      with_modified_env(**oidc_env, OIDC_AUTO_CREATE_USERS: 'true', OIDC_ACCOUNT_ID: account.id.to_s,
                                    OIDC_ADMIN_GROUPS: 'allchat-admin', OIDC_SUPERVISOR_GROUPS: 'allchat-supervisor') do
        get '/omniauth/oidc/callback'
        follow_redirect!

        user = User.from_email('novo@alltecnologias.com.br')
        account_user = user.account_users.find_by(account: account)
        expect(response).to redirect_to(%r{/app/login\?.*sso_auth_token=})
        expect(user).to be_confirmed
        expect(account_user).to be_agent
        expect(account_user.supervisor).to be(true)
      end
    end

    it 'creates administrators from the admin groups' do
      mock_oidc_auth(email: 'admin@alltecnologias.com.br', groups: %w[allchat-admin])

      with_modified_env(**oidc_env, OIDC_AUTO_CREATE_USERS: 'true', OIDC_ACCOUNT_ID: account.id.to_s,
                                    OIDC_ADMIN_GROUPS: 'allchat-admin') do
        get '/omniauth/oidc/callback'
        follow_redirect!

        user = User.from_email('admin@alltecnologias.com.br')
        expect(user.account_users.find_by(account: account)).to be_administrator
      end
    end
  end
end
