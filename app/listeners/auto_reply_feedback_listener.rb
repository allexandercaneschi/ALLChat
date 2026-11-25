# ALLChat: lets agents correct the auto reply guard (see AutoReply::Guard).
# - Removing the resposta-automatica label: the held texts are remembered as human for this contact
#   and are never held again.
# - Reopening a held conversation: it stops counting as held (CSAT and the usual rules apply again).
class AutoReplyFeedbackListener < BaseListener
  def conversation_updated(event)
    conversation, _account = extract_conversation_and_account(event)
    return unless label_removed?(event.data[:changed_attributes])
    return unless AutoReply::Guard.state_of(conversation) == AutoReply::Guard::SILENCED

    conversation.messages.incoming.where('additional_attributes->>? = ?', AutoReply::Guard::ATTRIBUTE, AutoReply::Guard::SILENCED)
                .find_each { |message| learn_human(conversation, message) }
    release(conversation)
  end

  def conversation_opened(event)
    conversation, _account = extract_conversation_and_account(event)
    release(conversation) if AutoReply::Guard.held?(conversation)
  end

  private

  def label_removed?(changed_attributes)
    previous_labels, current_labels = (changed_attributes || {}).with_indifferent_access[:label_list]
    Array(previous_labels).include?(AutoReply::Guard::LABEL) && Array(current_labels).exclude?(AutoReply::Guard::LABEL)
  end

  def learn_human(conversation, message)
    AutoReplySignature.remember!(conversation.contact, message.content, verdict: :human, source: :agent)
    # rubocop:disable Rails/SkipsModelValidations
    message.update_columns(additional_attributes: message.additional_attributes.merge(AutoReply::Guard::ATTRIBUTE => AutoReply::Guard::RELEASED))
    # rubocop:enable Rails/SkipsModelValidations
  end

  def release(conversation)
    conversation.update!(custom_attributes: conversation.custom_attributes.merge(AutoReply::Guard::ATTRIBUTE => AutoReply::Guard::RELEASED))
  end
end
