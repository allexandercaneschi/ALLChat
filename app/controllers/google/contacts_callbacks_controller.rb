# ALLChat: OAuth callback that connects a Google account to the contacts sync.
class Google::ContactsCallbacksController < ApplicationController
  def show
    account = GlobalID::Locator.locate_signed(params[:state], for: 'google_contacts')
    raise ActionController::BadRequest, 'Invalid or expired state' if account.nil?

    token = GoogleContacts::Oauth.client.auth_code.get_token(params[:code], redirect_uri: GoogleContacts::Oauth.redirect_uri)
    save_connection(account, token)
    redirect_to "/app/accounts/#{account.id}/settings/general"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    redirect_to '/'
  end

  private

  def save_connection(account, token)
    connection = GoogleContactsConnection.find_or_initialize_by(account: account)
    connection.update!(
      email: JWT.decode(token.params['id_token'], nil, false).first['email'],
      access_token: token.token,
      refresh_token: token.refresh_token.presence || connection.refresh_token,
      expires_at: Time.zone.at(token.expires_at),
      enabled: true
    )
  end
end
