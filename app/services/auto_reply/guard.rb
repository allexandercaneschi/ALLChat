# ALLChat: stops the loop caused by contacts' automatic responders on WhatsApp.
#
# The loop: we resolve a conversation (or send a broadcast) -> the n8n flows send a message (closing
# message, queue position) -> the contact's WhatsApp Business answers by itself -> the conversation
# reopens or a new one starts -> it is resolved again -> another message goes out -> ...
#
# Before Chatwoot reopens a conversation, the guard looks at the incoming message. It only acts when
# the message would start something (resolved conversation, broadcast waiting for a reply, or a
# conversation that has just been created) and it never touches a conversation in progress.
#
#   1. Memory (AutoReplySignature): a text already known as automatic for this contact is held at
#      once; one an agent marked as human always passes.
#   2. Speed: a message that did not arrive within FAST_REPLY_WINDOW of our last message passes.
#   3. Loop: the LOOP_LIMIT-th fast reply from the same contact within LOOP_WINDOW is held and its
#      text remembered, even if Chip is unavailable.
#   4. Otherwise Chip (the company AI) decides in AutoReply::ClassifyJob. Meanwhile the message is
#      held; if Chip says it was a person, or fails, the conversation is reopened.
#
# Holding is silent: the conversation stays (or becomes) resolved with encerramento_tipo =
# sem_mensagem, so the n8n closing flow sends nothing, CSAT is skipped and the queue does not move.
# The state goes in custom_attributes['resposta_automatica'] and in the message's
# additional_attributes. Removing the resposta-automatica label teaches the memory that the text is
# human (AutoReplyFeedbackListener).
class AutoReply::Guard
  FAST_REPLY_WINDOW = 45.seconds
  LOOP_WINDOW = 1.hour
  LOOP_LIMIT = 3
  LOOP_KEY = 'ALLCHAT::AUTO_REPLY::LOOP::%<contact_id>d'.freeze
  CLASSIFY_DELAY = 5.seconds

  LABEL = 'resposta-automatica'.freeze
  ATTRIBUTE = 'resposta_automatica'.freeze
  ANALYZING = 'analisando'.freeze
  SILENCED = 'silenciada'.freeze
  RELEASED = 'liberada'.freeze
  HELD_STATES = [ANALYZING, SILENCED].freeze

  class << self
    # On by default; ALLCHAT_AUTO_REPLY_GUARD=false turns it off. Off in tests unless a spec enables it.
    def enabled?
      ENV.fetch('ALLCHAT_AUTO_REPLY_GUARD', Rails.env.test? ? 'false' : 'true') == 'true'
    end

    def held?(record)
      HELD_STATES.include?(state_of(record))
    end

    def state_of(record)
      attributes = record.is_a?(Message) ? record.additional_attributes : record.custom_attributes
      attributes&.dig(ATTRIBUTE)
    end
  end

  pattr_initialize [:message!]

  # Called right before Chatwoot reopens the conversation. True when the message was held.
  def hold?
    return false unless self.class.enabled? && guarded?

    verdict, reason = decide
    return hold!(verdict == :auto ? SILENCED : ANALYZING, reason) unless verdict == :human

    release_previous_hold
    false
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: message.account).capture_exception
    false
  end

  # Runs in AutoReply::ClassifyJob for a message held while Chip decides.
  def apply_chip_verdict!
    return unless self.class.state_of(message) == ANALYZING

    result = ask_chip
    if result[:error].present?
      Rails.logger.info("[AutoReply::Guard] Chip unavailable for message #{message.id}: #{result[:error]}")
      return release!
    end

    AutoReplySignature.remember!(contact, message.content, verdict: result[:auto_reply] ? :auto_reply : :human, source: :ai)
    result[:auto_reply] ? confirm_hold!(result[:reason]) : release!
  end

  private

  def ask_chip
    Chip::AutoReplyClassifier.new(account: account, text: message.content,
                                  previous_text: last_outgoing&.content, seconds: seconds_since_last_outgoing).perform
  end

  delegate :conversation, :inbox, :account, to: :message

  def contact
    conversation.contact
  end

  def guarded?
    guarded_message? && (conversation.resolved? || awaiting_broadcast? || fresh_conversation?)
  end

  def guarded_message?
    message.incoming? && !message.private? && message.content.present? && contact.present? && (inbox.api? || inbox.whatsapp?)
  end

  def awaiting_broadcast?
    conversation.custom_attributes['transmissao'] == 'aguardando'
  end

  # A conversation the contact's message has just created (e.g. Evolution opens a new one when the
  # previous is resolved): nothing was said in it before.
  def fresh_conversation?
    conversation.messages.where(message_type: %i[incoming outgoing], private: false).where.not(id: message.id).none?
  end

  def decide
    signature = AutoReplySignature.lookup(contact, message.content)
    return decide_known(signature) if signature
    return [:human] unless fast_reply?

    count_loop >= LOOP_LIMIT ? remember_loop : [:suspect]
  end

  # Chip already said this text is human: no need to ask her again, but a loop still overrides her
  # (never an agent).
  def decide_known(signature)
    signature.seen!
    return [:auto, :memory] if signature.auto_reply?
    return [:human] if signature.agent? || !fast_reply?

    count_loop >= LOOP_LIMIT ? remember_loop : [:human]
  end

  def remember_loop
    AutoReplySignature.remember!(contact, message.content, verdict: :auto_reply, source: :rule)
    [:auto, :loop]
  end

  def fast_reply?
    last_outgoing.present? && seconds_since_last_outgoing <= FAST_REPLY_WINDOW.to_i
  end

  # Our last message to this contact in this inbox, in any conversation (the closing message lives in
  # the conversation that was resolved, the auto reply may arrive in a new one).
  def last_outgoing
    @last_outgoing ||= Message.where(conversation_id: Conversation.where(contact_id: contact.id, inbox_id: inbox.id).select(:id),
                                     message_type: :outgoing, private: false)
                              .where(created_at: ..message.created_at).where.not(id: message.id)
                              .reorder(created_at: :desc, id: :desc).first
  end

  def seconds_since_last_outgoing
    return unless last_outgoing

    (message.created_at - last_outgoing.created_at).round
  end

  def count_loop
    key = format(LOOP_KEY, contact_id: contact.id)
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, LOOP_WINDOW.to_i) if count == 1
    count
  end

  def hold!(state, reason)
    mark_message(state)
    conversation.update!(held_changes(state))
    if state == SILENCED
      announce(reason)
    else
      AutoReply::ClassifyJob.set(wait: CLASSIFY_DELAY).perform_later(message)
    end
    true
  end

  def held_changes(state)
    attributes = conversation.custom_attributes.merge(ATTRIBUTE => state)
    changes = { custom_attributes: attributes }
    changes[:label_list] = labels_with_guard_label if state == SILENCED
    return changes if conversation.resolved?

    # Resolving here must send nothing: the n8n closing flow skips encerramento_tipo, and a broadcast
    # that only got an auto reply ends as unanswered (like Broadcasts::AutoResolveJob).
    attributes['encerramento_tipo'] = 'sem_mensagem'
    if attributes['transmissao'] == 'aguardando'
      attributes['transmissao'] = 'encerrada'
      attributes.delete('transmissao_resolver_em')
    end
    changes.merge(status: :resolved)
  end

  def confirm_hold!(reason)
    mark_message(SILENCED)
    return unless self.class.state_of(conversation) == ANALYZING

    conversation.update!(custom_attributes: conversation.custom_attributes.merge(ATTRIBUTE => SILENCED), label_list: labels_with_guard_label)
    announce(reason)
  end

  # Chip said it was a person (or could not answer): the conversation goes back to how Chatwoot would
  # have left it, and a broadcast counts as answered.
  def release!
    mark_message(RELEASED)
    return unless self.class.state_of(conversation) == ANALYZING

    attributes = conversation.custom_attributes.merge(ATTRIBUTE => RELEASED).except('encerramento_tipo', 'transmissao_resolver_em')
    attributes['transmissao'] = 'respondida' if %w[aguardando encerrada].include?(attributes['transmissao'])
    conversation.update!(status: inbox.active_bot? ? :pending : :open, custom_attributes: attributes)
  end

  # The contact is now really writing to a conversation that was held before
  def release_previous_hold
    return unless self.class.held?(conversation)

    conversation.update!(custom_attributes: conversation.custom_attributes.merge(ATTRIBUTE => RELEASED))
  end

  def labels_with_guard_label
    (conversation.label_list.to_a + [LABEL]).uniq
  end

  def mark_message(state)
    # rubocop:disable Rails/SkipsModelValidations
    message.update_columns(additional_attributes: (message.additional_attributes || {}).merge(ATTRIBUTE => state))
    # rubocop:enable Rails/SkipsModelValidations
  end

  def announce(reason)
    content = with_account_locale do
      key = reason.is_a?(Symbol) ? reason : :chip
      I18n.t("conversations.activity.auto_reply.held_#{key}", reason: reason.to_s)
    end
    ::Conversations::ActivityMessageJob.perform_later(conversation, account_id: account.id, inbox_id: inbox.id,
                                                                    message_type: :activity, content: content)
  end

  def with_account_locale(&)
    I18n.with_locale(account.locale.presence || I18n.default_locale, &)
  rescue I18n::InvalidLocale
    yield
  end
end
