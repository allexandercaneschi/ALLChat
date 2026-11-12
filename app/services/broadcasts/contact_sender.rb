# ALLChat: sends a broadcast to one contact. The WhatsApp message opens a
# conversation sent by the Chip bot, routed to the chosen team and waiting for
# a reply (see Broadcasts::AutoResolveJob), and optionally also goes by e-mail.
class Broadcasts::ContactSender
  pattr_initialize [:contact!, :options!]

  def perform
    text = Broadcasts::Personalization.new(contact: contact, fallback: options['name_fallback']).render(options['content'])
    send_whatsapp(text) if contact.phone_number.present?
    send_email(text) if options['send_email'] && contact.email.present?
  end

  private

  def account
    contact.account
  end

  def inbox
    @inbox ||= account.inboxes.find(options['inbox_id'])
  end

  def send_whatsapp(text)
    contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox) || ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    conversation = Conversation.create!(
      account_id: account.id, inbox_id: inbox.id, contact_id: contact.id, contact_inbox_id: contact_inbox.id,
      team_id: options['team_id'], status: :open, custom_attributes: awaiting_reply_attributes
    )
    conversation.messages.create!(
      account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: text, sender: account.agent_bots.find(options['bot_id'])
    )
  end

  def awaiting_reply_attributes
    { 'transmissao' => 'aguardando', 'transmissao_resolver_em' => options['resolve_after_hours'].to_i.hours.from_now.iso8601 }
  end

  def send_email(text)
    BroadcastMailer.with(account: account, email: contact.email, subject: options['subject'], content: text).broadcast.deliver_later
  end
end
