# ALLChat: contacts of a broadcast list, available to every user authorized on it.
# Adding or removing a contact adds or removes the list's label.
class Api::V1::Accounts::BroadcastLists::ContactsController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25
  MAX_IMPORT_SIZE = 1.megabyte

  before_action :fetch_list

  def index
    contacts = @list.contacts
    if params[:q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      contacts = contacts.where('contacts.name ILIKE :q OR contacts.phone_number ILIKE :q OR contacts.email ILIKE :q', q: query)
    end
    page = contacts.reorder(:name).page(params[:page]).per(RESULTS_PER_PAGE)
    render json: { payload: page.map { |contact| contact_json(contact) }, meta: { count: contacts.count, current_page: page.current_page } }
  end

  def create
    added = 0
    Current.account.contacts.where(id: params.require(:contact_ids)).find_each do |contact|
      next if contact.label_list.include?(label_title)

      contact.label_list.add(label_title)
      contact.save!
      added += 1
    end
    render json: { added: added }
  end

  def destroy
    contact = @list.contacts.find(params[:id])
    contact.label_list.remove(label_title)
    contact.save!
    head :ok
  end

  def import
    content = params.require(:content)
    if content.bytesize > MAX_IMPORT_SIZE
      return render json: { error: I18n.t('broadcast_lists.import.too_large') }, status: :unprocessable_entity
    end

    render json: BroadcastLists::ImportService.new(broadcast_list: @list, content: content).perform
  end

  private

  def fetch_list
    @list = Current.account.broadcast_lists.visible_to(Current.account_user).find(params[:broadcast_list_id])
  end

  def label_title
    @list.label.title
  end

  def contact_json(contact)
    {
      id: contact.id,
      name: contact.name,
      phone_number: contact.phone_number,
      email: contact.email,
      thumbnail: contact.avatar_url
    }
  end
end
