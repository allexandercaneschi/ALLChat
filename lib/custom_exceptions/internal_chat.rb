# frozen_string_literal: true

# ALLChat: errors for the internal team chat.
module CustomExceptions::InternalChat
  class Error < CustomExceptions::Base
    def to_hash
      { error: message }
    end

    def http_status
      :unprocessable_entity
    end
  end

  # The attention nudge can not be used again right away.
  class NudgeTooSoon < Error
    def message
      I18n.t('internal_chat.errors.nudge_too_soon', seconds: @data[:retry_after])
    end

    def to_hash
      { error: message, retry_after: @data[:retry_after] }
    end

    def http_status
      :too_many_requests
    end
  end

  class AlreadyClaimed < Error
    def message
      I18n.t('internal_chat.errors.already_claimed')
    end

    def http_status
      :conflict
    end
  end

  class NotAHelpRequest < Error
    def message
      I18n.t('internal_chat.errors.not_a_help_request')
    end
  end
end
