class Broadcasts::SendToContactJob < ApplicationJob
  queue_as :low

  def perform(contact_id, options)
    contact = Contact.find_by(id: contact_id)
    return if contact.nil? || contact.blocked?

    Broadcasts::ContactSender.new(contact: contact, options: options).perform
  end
end
