# ALLChat: queues one send per contact, spaced out so WhatsApp is not flooded.
class Broadcasts::DeliveryService
  SECONDS_BETWEEN_CONTACTS = 5
  CHIP_BOT_NAME = 'Chip'.freeze

  pattr_initialize [:account!, :contacts!, :options!]

  def perform
    contact_options = options.merge('bot_id' => chip_bot.id)
    contact_ids = contacts.pluck('contacts.id')
    contact_ids.each_with_index do |contact_id, index|
      job = Broadcasts::SendToContactJob.set(wait: (index * SECONDS_BETWEEN_CONTACTS).seconds)
      job.perform_later(contact_id, contact_options)
    end
    contact_ids.size
  end

  private

  def chip_bot
    account.agent_bots.find_or_create_by!(name: CHIP_BOT_NAME) { |bot| bot.description = 'Atendente virtual da ALL Tecnologias' }
  end
end
