# ALLChat: daily refresh of WhatsApp photos for contacts active in the last 30 days.
class Evolution::RefreshProfilePicturesJob < ApplicationJob
  queue_as :low

  ACTIVE_WINDOW = 30.days
  PAUSE_BETWEEN_CONTACTS = 1 # second, to stay gentle with WhatsApp

  def perform
    return unless Evolution::ProfilePictureService.configured?

    Contact.where.not(phone_number: [nil, '']).where('last_activity_at > ?', ACTIVE_WINDOW.ago).find_each do |contact|
      Evolution::ProfilePictureService.new(contact: contact).perform
      sleep PAUSE_BETWEEN_CONTACTS
    rescue StandardError => e
      Rails.logger.warn("Evolution profile picture refresh failed for contact #{contact.id}: #{e.message}")
    end
  end
end
