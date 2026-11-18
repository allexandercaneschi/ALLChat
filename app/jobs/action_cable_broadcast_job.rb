class ActionCableBroadcastJob < ApplicationJob
  queue_as :critical
  include Events::Types

  CONVERSATION_UPDATE_EVENTS = [
    CONVERSATION_READ,
    CONVERSATION_UPDATED,
    TEAM_CHANGED,
    ASSIGNEE_CHANGED,
    CONVERSATION_STATUS_CHANGED
  ].freeze

  # ActiveStorage writes the file only after the message transaction commits, so the
  # event can be ready before the file is. Browsers that react to it would get a 404.
  UPLOAD_WAIT_ATTEMPTS = 20
  UPLOAD_WAIT_INTERVAL = 0.25

  def perform(members, event_name, data)
    return if members.blank?

    wait_for_attachment_files(event_name, data)
    broadcast_data = prepare_broadcast_data(event_name, data)
    broadcast_to_members(members, event_name, broadcast_data)
  end

  private

  def wait_for_attachment_files(event_name, data)
    return unless event_name == MESSAGE_CREATED && data[:attachments].present?

    attachment_ids = data[:attachments].pluck(:id)
    UPLOAD_WAIT_ATTEMPTS.times do
      break if attachment_files_written?(attachment_ids)

      sleep UPLOAD_WAIT_INTERVAL
    end
  end

  def attachment_files_written?(attachment_ids)
    Attachment.where(id: attachment_ids).includes(file_attachment: :blob).all? do |attachment|
      !attachment.file.attached? || attachment.file.blob.service.exist?(attachment.file.blob.key)
    end
  end

  # Ensures that only the latest available data is sent to prevent UI issues
  # caused by out-of-order events during high-traffic periods. This prevents
  # the conversation job from processing outdated data.
  def prepare_broadcast_data(event_name, data)
    return data unless CONVERSATION_UPDATE_EVENTS.include?(event_name)

    account = Account.find(data[:account_id])
    conversation = account.conversations.find_by!(display_id: data[:id])
    broadcast_data = conversation.push_event_data.merge(account_id: data[:account_id])
    if event_name == ASSIGNEE_CHANGED
      # Keep the original assignment together even when the conversation is
      # refreshed. The dashboard checks its identity against the current owner.
      # Other events omit this field so unrelated updates cannot overwrite it.
      broadcast_data[:assignment] = {
        automatic: data[:automatic_assignment] == true,
        assignee_id: data.dig(:meta, :assignee, :id),
        assignee_type: data.dig(:meta, :assignee_type),
        updated_at: data[:updated_at]
      }
    end
    broadcast_data
  end

  def broadcast_to_members(members, event_name, broadcast_data)
    members.each do |member|
      ActionCable.server.broadcast(
        member,
        {
          event: event_name,
          data: broadcast_data
        }
      )
    end
  end
end
