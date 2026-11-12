# ALLChat: when the contact answers a broadcast, the conversation stops waiting
# for a reply, so it is no longer resolved silently and the usual rules apply.
# A conversation resolved without reply that the contact answers later is reopened by Chatwoot and counts as answered too.
class BroadcastReplyListener < BaseListener
  def message_created(event)
    message, _account = extract_message_and_account(event)
    return unless message.incoming?

    conversation = message.conversation
    return unless ['aguardando', 'encerrada'].include?(conversation.custom_attributes['transmissao'])

    conversation.update!(custom_attributes: conversation.custom_attributes.merge('transmissao' => 'respondida').except('transmissao_resolver_em'))
  end
end
