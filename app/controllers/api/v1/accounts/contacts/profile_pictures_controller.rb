# ALLChat: "Update WhatsApp photo" button on the contact.
class Api::V1::Accounts::Contacts::ProfilePicturesController < Api::V1::Accounts::Contacts::BaseController
  def create
    return render_could_not_create_error(I18n.t('contacts.profile_picture.not_configured')) unless Evolution::ProfilePictureService.configured?
    return render_could_not_create_error(I18n.t('contacts.profile_picture.not_found')) unless refreshed?

    render json: { thumbnail: @contact.reload.avatar_url }
  end

  private

  def refreshed?
    Evolution::ProfilePictureService.new(contact: @contact).perform
  end
end
