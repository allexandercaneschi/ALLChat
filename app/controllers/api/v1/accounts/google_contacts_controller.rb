# ALLChat: Google Contacts sync settings (administrators only).
class Api::V1::Accounts::GoogleContactsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def show
    render json: {
      configured: GoogleContacts::Oauth.configured?,
      redirect_uri: GoogleContacts::Oauth.redirect_uri,
      connection: connection&.as_json
    }
  end

  def authorization
    return render_could_not_create_error(I18n.t('google_contacts.not_configured')) unless GoogleContacts::Oauth.configured?

    url = GoogleContacts::Oauth.client.auth_code.authorize_url(
      redirect_uri: GoogleContacts::Oauth.redirect_uri,
      scope: GoogleContacts::Oauth::SCOPE,
      access_type: 'offline',
      prompt: 'consent',
      state: Current.account.to_sgid(expires_in: 15.minutes, for: 'google_contacts').to_s
    )
    render json: { url: url }
  end

  def update
    connection!.update!(params.permit(:dry_run, :enabled))
    render json: connection.as_json
  end

  def sync
    GoogleContacts::SyncJob.perform_later(connection!)
    head :accepted
  end

  def destroy
    connection!.destroy!
    head :ok
  end

  private

  def connection
    @connection ||= GoogleContactsConnection.find_by(account: Current.account)
  end

  def connection!
    connection || raise(ActiveRecord::RecordNotFound)
  end
end
