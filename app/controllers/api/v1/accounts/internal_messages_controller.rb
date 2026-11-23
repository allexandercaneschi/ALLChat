# ALLChat: messages of an internal chat channel.
class Api::V1::Accounts::InternalMessagesController < Api::V1::Accounts::BaseController
  DEFAULT_PAGE_SIZE = 30
  MAX_PAGE_SIZE = 100

  before_action :fetch_channel

  def index
    authorize InternalChat::Message.new(channel: @channel), :index?
    page_size = (params[:limit].presence || DEFAULT_PAGE_SIZE).to_i.clamp(1, MAX_PAGE_SIZE)
    messages = @channel.messages.includes(:sender).order(id: :desc).limit(page_size + 1)
    messages = messages.where(id: ...params[:before_id].to_i) if params[:before_id].present?
    page = messages.to_a
    render json: { payload: page.first(page_size).reverse.map(&:push_event_data), meta: { has_more: page.size > page_size } }
  end

  def create
    authorize InternalChat::Message.new(channel: @channel), :create?
    message = InternalChat::Messages::CreateService.new(channel: @channel, sender: Current.user, content: params.require(:content)).perform
    render json: message.push_event_data
  end

  private

  def fetch_channel
    @channel = InternalChat::Channel.where(account: Current.account).find(params[:internal_channel_id])
  end
end
