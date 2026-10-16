# ALLChat: closes transfer/participation requests nobody answered in time.
# The conversation stays with its current assignee.
class ConversationRequests::ExpireJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ConversationRequest.pending.where('expires_at <= ?', Time.current).find_each do |request|
      request.expire!
    rescue CustomExceptions::ConversationRequest::NotOpen
      next
    end
  end
end
