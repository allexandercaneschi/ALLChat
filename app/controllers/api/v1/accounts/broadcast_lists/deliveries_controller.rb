# ALLChat: immediate broadcast ("Envio rápido") to every contact of a list,
# available to the users authorized on the list.
class Api::V1::Accounts::BroadcastLists::DeliveriesController < Api::V1::Accounts::BaseController
  SENDING_CHANNELS = ['Channel::Api', 'Channel::Whatsapp'].freeze

  before_action :fetch_list
  before_action :fetch_inbox

  def create
    return render_error('broadcast_lists.delivery.invalid_inbox') unless SENDING_CHANNELS.include?(@inbox.channel_type)
    return render_error('broadcast_lists.delivery.subject_required') if params[:send_email] && params[:subject].blank?

    queued = Broadcasts::DeliveryService.new(account: Current.account, contacts: @list.contacts, options: delivery_options).perform
    render json: { queued: queued }
  end

  private

  def delivery_options
    team = Current.account.teams.find(params[:team_id]) if params[:team_id].present?
    {
      'content' => params.require(:content), 'inbox_id' => @inbox.id, 'team_id' => team&.id, 'subject' => params[:subject],
      'send_email' => params[:send_email] || false, 'name_fallback' => params.fetch(:name_fallback, 'cliente'),
      'resolve_after_hours' => params.fetch(:resolve_after_hours, 24)
    }
  end

  def render_error(key)
    render json: { error: I18n.t(key) }, status: :unprocessable_entity
  end

  def fetch_list
    @list = Current.account.broadcast_lists.visible_to(Current.account_user).find(params[:broadcast_list_id])
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params.require(:inbox_id))
  end
end
