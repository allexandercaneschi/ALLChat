# ALLChat: search in the messages of the internal conversations of the current agent, in one
# conversation (channel_id) or in all of them. Never reaches conversations the agent is not part of.
class Api::V1::Accounts::InternalSearchController < Api::V1::Accounts::BaseController
  MIN_QUERY_LENGTH = 2
  PAGE_SIZE = 30

  def show
    authorize InternalChat::Channel, :index?
    messages = scoped_messages.where('internal_chat_messages.content ILIKE ?', "%#{InternalChat::Message.sanitize_sql_like(query)}%")
    messages = messages.where(id: ...params[:before_id].to_i) if params[:before_id].present?
    page = messages.includes(:sender, :claimed_by).order(id: :desc).limit(PAGE_SIZE + 1).to_a
    render json: { payload: page.first(PAGE_SIZE).map(&:push_event_data), meta: { has_more: page.size > PAGE_SIZE } }
  end

  private

  def query
    text = params.require(:q).to_s.strip
    raise ActionController::ParameterMissing, "q needs at least #{MIN_QUERY_LENGTH} characters" if text.length < MIN_QUERY_LENGTH

    text
  end

  def scoped_messages
    return InternalChat::Message.where(channel_id: visible_channels.select(:id)) if params[:channel_id].blank?

    channel = InternalChat::Channel.where(account: Current.account).find(params[:channel_id])
    authorize channel, :show?
    channel.messages
  end

  def visible_channels
    InternalChat::Channel.visible_to(Current.user, Current.account)
  end
end
