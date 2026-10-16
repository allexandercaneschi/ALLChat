# ALLChat: refreshes a contact's photo with its current WhatsApp profile picture.
#
# Evolution API hands Chatwoot a signed WhatsApp URL that expires quickly, so
# photos often never get downloaded. This asks Evolution for a fresh URL and
# downloads it right away. Configured with EVOLUTION_API_URL, EVOLUTION_API_KEY
# and EVOLUTION_INSTANCE.
class Evolution::ProfilePictureService
  REQUEST_TIMEOUT = 15

  pattr_initialize [:contact!]

  def self.configured?
    %w[EVOLUTION_API_URL EVOLUTION_API_KEY EVOLUTION_INSTANCE].all? { |key| ENV[key].present? }
  end

  # Returns true when a picture was found and downloaded.
  def perform
    return false unless self.class.configured? && contact.phone_number.present?

    url = picture_url
    return false if url.blank?

    Avatar::AvatarFromUrlJob.perform_now(contact, url)
    true
  end

  private

  def picture_url
    response = HTTParty.post(
      "#{ENV.fetch('EVOLUTION_API_URL').chomp('/')}/chat/fetchProfilePictureUrl/#{ENV.fetch('EVOLUTION_INSTANCE')}",
      headers: { 'apikey' => ENV.fetch('EVOLUTION_API_KEY'), 'Content-Type' => 'application/json' },
      body: { number: contact.phone_number.delete('^0-9') }.to_json,
      timeout: REQUEST_TIMEOUT
    )
    response.success? ? response.parsed_response['profilePictureUrl'] : nil
  end
end
