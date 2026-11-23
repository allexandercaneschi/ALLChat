# ALLChat: messages of an internal chat channel.
class Api::V1::Accounts::InternalMessagesController < Api::V1::Accounts::BaseController
  rescue_from CustomExceptions::InternalChat::Error, with: :render_error_response

  DEFAULT_PAGE_SIZE = 30
  MAX_PAGE_SIZE = 100
  # Help requests have their own endpoint.
  SENDABLE_KINDS = %w[text nudge].freeze

  before_action :fetch_channel
  before_action :fetch_message, only: [:claim, :resolve]

  def index
    authorize InternalChat::Message.new(channel: @channel), :index?
    page_size = (params[:limit].presence || DEFAULT_PAGE_SIZE).to_i.clamp(1, MAX_PAGE_SIZE)
    messages = @channel.messages.includes(:sender, :claimed_by).order(id: :desc).limit(page_size + 1)
    messages = messages.where(id: ...params[:before_id].to_i) if params[:before_id].present?
    page = messages.to_a
    render json: { payload: page.first(page_size).reverse.map(&:push_event_data), meta: { has_more: page.size > page_size } }
  end

  def create
    authorize InternalChat::Message.new(channel: @channel), :create?
    message = InternalChat::Messages::CreateService.new(channel: @channel, sender: Current.user, **message_attributes).perform
    render json: message.push_event_data
  end

  def claim
    authorize @message, :claim?
    result = InternalChat::HelpRequests::ClaimService.new(message: @message, user: Current.user).perform
    render json: { message: result[:message].push_event_data, channel_id: result[:channel].id, joined_conversation: result[:joined_conversation] }
  end

  def resolve
    authorize @message, :resolve?
    @message.resolve!
    InternalChat::Messages::CreateService.broadcast(@message, InternalChat::Messages::CreateService::MESSAGE_UPDATED_EVENT)
    render json: @message.push_event_data
  end

  private

  def fetch_channel
    @channel = InternalChat::Channel.where(account: Current.account).find(params[:internal_channel_id])
  end

  def fetch_message
    @message = @channel.messages.find(params[:id])
  end

  def message_attributes
    kind = params.fetch(:kind, 'text')
    raise ActionController::ParameterMissing, 'kind must be text or nudge' unless SENDABLE_KINDS.include?(kind)

    attributes = { kind: kind, urgent: params[:urgent] == true, mentioned_user_ids: Array(params[:mentioned_user_ids]).map(&:to_i) }
    attributes[:content] = params.require(:content) unless kind == 'nudge'
    attributes
  end
end
