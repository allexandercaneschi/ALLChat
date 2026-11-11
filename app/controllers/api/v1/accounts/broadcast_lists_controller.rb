# ALLChat: broadcast lists. Administrators manage every list and choose who may
# use each one; other users only see the lists they were authorized on.
class Api::V1::Accounts::BroadcastListsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, except: [:index, :show]
  before_action :fetch_list, except: [:index, :create]

  def index
    lists = Current.account.broadcast_lists.visible_to(Current.account_user).includes(:label).order(:name)
    render json: { payload: lists.map { |list| list.as_json_for(Current.account_user) } }
  end

  def show
    render json: @list.as_json_for(Current.account_user)
  end

  def create
    @list = Current.account.broadcast_lists.create!(list_params)
    render json: @list.as_json_for(Current.account_user)
  end

  def update
    @list.update!(list_params)
    render json: @list.as_json_for(Current.account_user)
  end

  # Deleting the label deletes the list and untags its contacts.
  def destroy
    label = @list.label
    label.destroy!
    Labels::RemoveAssociationsJob.perform_later(label_title: label.title, account_id: Current.account.id, label_deleted_at: Time.current)
    head :ok
  end

  def users
    @list.user_ids = Current.account.users.where(id: params.fetch(:user_ids, [])).pluck(:id)
    render json: @list.as_json_for(Current.account_user)
  end

  private

  def fetch_list
    @list = Current.account.broadcast_lists.visible_to(Current.account_user).find(params[:id])
  end

  def list_params
    params.require(:broadcast_list).permit(:name, :description)
  end
end
