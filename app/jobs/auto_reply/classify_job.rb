# ALLChat: asks Chip whether a held message came from an automatic responder (see AutoReply::Guard).
class AutoReply::ClassifyJob < ApplicationJob
  queue_as :medium

  def perform(message)
    AutoReply::Guard.new(message: message).apply_chip_verdict!
  end
end
