# ALLChat: immediate broadcast ("Transmissão por empresa") to every contact that has
# the chosen company registered. There is no schedule, and only administrators and
# supervisors use it.
class Api::V1::Accounts::CompanyBroadcastsController < Api::V1::Accounts::BaseController
  SENDING_CHANNELS = Api::V1::Accounts::BroadcastLists::DeliveriesController::SENDING_CHANNELS

  before_action :check_manager_authorization
  before_action :fetch_inbox, only: [:create]

  def index
    render json: { payload: companies.summary }
  end

  def create
    return render_error('broadcast_lists.delivery.invalid_inbox') unless SENDING_CHANNELS.include?(@inbox.channel_type)
    return render_error('broadcast_lists.delivery.subject_required') if params[:send_email] && params[:subject].blank?

    contacts = companies.contacts(params.require(:company))
    return render_error('company_broadcasts.company_not_found') if contacts.empty?

    queued = Broadcasts::DeliveryService.new(account: Current.account, contacts: contacts, options: delivery_options).perform
    render json: { queued: queued }
  end

  private

  def check_manager_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator_or_supervisor?
  end

  def companies
    @companies ||= Broadcasts::Companies.new(account: Current.account)
  end

  def delivery_options
    team = Current.account.teams.find(params[:team_id]) if params[:team_id].present?
    {
      'content' => params.require(:content), 'inbox_id' => @inbox.id, 'team_id' => team&.id, 'subject' => params[:subject],
      'send_email' => params[:send_email] || false, 'name_fallback' => params.fetch(:name_fallback, 'cliente'),
      'resolve_after_minutes' => params.fetch(:resolve_after_minutes, 30)
    }
  end

  def render_error(key)
    render json: { error: I18n.t(key) }, status: :unprocessable_entity
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params.require(:inbox_id))
  end
end
