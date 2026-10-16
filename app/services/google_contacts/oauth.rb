# ALLChat: OAuth client for the Google Contacts sync.
# Uses its own Google Cloud OAuth client (GOOGLE_CONTACTS_CLIENT_ID / _SECRET),
# separate from the Gmail inbox integration.
module GoogleContacts::Oauth
  SCOPE = 'openid email https://www.googleapis.com/auth/contacts'.freeze
  CALLBACK_PATH = '/google/contacts/callback'.freeze

  module_function

  def client
    ::OAuth2::Client.new(
      ENV.fetch('GOOGLE_CONTACTS_CLIENT_ID'),
      ENV.fetch('GOOGLE_CONTACTS_CLIENT_SECRET'),
      site: 'https://oauth2.googleapis.com',
      authorize_url: 'https://accounts.google.com/o/oauth2/auth',
      token_url: 'https://oauth2.googleapis.com/token'
    )
  end

  def configured?
    ENV['GOOGLE_CONTACTS_CLIENT_ID'].present? && ENV['GOOGLE_CONTACTS_CLIENT_SECRET'].present?
  end

  def redirect_uri
    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}#{CALLBACK_PATH}"
  end
end
