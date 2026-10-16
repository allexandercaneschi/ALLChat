# frozen_string_literal: true

# ALLChat: errors for conversation transfer/participation requests.
module CustomExceptions::ConversationRequest
  class Error < CustomExceptions::Base
    def to_hash
      { error: message }
    end

    def http_status
      :unprocessable_entity
    end
  end

  class NotOpen < Error
    def message
      I18n.t('conversations.requests.not_open')
    end
  end

  class Stale < Error
    def message
      I18n.t('conversations.requests.stale')
    end
  end

  class NotAllowed < Error
    def message
      I18n.t("conversations.requests.not_allowed.#{@data[:reason]}")
    end

    def http_status
      :forbidden
    end
  end
end
