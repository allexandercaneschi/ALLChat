require 'rails_helper'

RSpec.describe ConversationRequests::ExpireJob do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, assignee: owner) }

  it 'expires unanswered requests and keeps the conversation with its assignee' do
    old_request = ConversationRequest.create!(conversation: conversation, requester: owner, target: colleague, request_type: :transfer)
    old_request.update!(expires_at: 1.minute.ago)
    fresh_request = ConversationRequest.create!(conversation: conversation, requester: colleague, target: owner, request_type: :participation)

    described_class.perform_now

    expect(old_request.reload).to be_expired
    expect(fresh_request.reload).to be_pending
    expect(conversation.reload.assignee).to eq(owner)
  end
end
