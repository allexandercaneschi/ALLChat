require 'rails_helper'

RSpec.describe ConversationRequest do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, assignee: owner) }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: owner)
    create(:inbox_member, inbox: conversation.inbox, user: colleague)
  end

  it 'expires after the account timeout, 60 minutes by default' do
    freeze_time do
      request = described_class.create!(conversation: conversation, requester: owner, target: colleague, request_type: :transfer)
      expect(request.expires_at).to eq(60.minutes.from_now)

      account.update!(conversation_request_timeout: 15)
      other = described_class.create!(conversation: conversation, requester: colleague, target: owner, request_type: :participation)
      expect(other.expires_at).to eq(15.minutes.from_now)
    end
  end

  it 'allows a single open request per agent, conversation and type' do
    described_class.create!(conversation: conversation, requester: owner, target: colleague, request_type: :transfer)
    duplicate = described_class.new(conversation: conversation, requester: owner, target: colleague, request_type: :transfer)

    expect(duplicate).not_to be_valid
  end

  it 'broadcasts updates to both agents' do
    expect do
      described_class.create!(conversation: conversation, requester: owner, target: colleague, request_type: :transfer)
    end.to have_enqueued_job(ActionCableBroadcastJob).with(
      contain_exactly(owner.pubsub_token, colleague.pubsub_token), 'conversation_request.updated', anything
    )
  end

  describe '#accept!' do
    it 'hands a transfer over to the target' do
      request = described_class.create!(conversation: conversation, requester: owner, target: colleague, request_type: :transfer)

      request.accept!

      expect(request.reload).to be_accepted
      expect(conversation.reload.assignee).to eq(colleague)
    end

    it 'adds the requester as participant on a participation request' do
      request = described_class.create!(conversation: conversation, requester: colleague, target: owner, request_type: :participation)

      request.accept!

      expect(request.reload).to be_accepted
      expect(conversation.conversation_participants.exists?(user: colleague)).to be(true)
    end

    it 'refuses requests the conversation outgrew' do
      request = described_class.create!(conversation: conversation, requester: owner, target: colleague, request_type: :transfer)
      conversation.update!(assignee: create(:user, account: account, role: :agent))

      expect { request.accept! }.to raise_error(CustomExceptions::ConversationRequest::Stale)
      expect(request.reload).to be_pending
    end

    it 'refuses expired requests' do
      request = described_class.create!(conversation: conversation, requester: owner, target: colleague, request_type: :transfer)

      travel 61.minutes do
        expect { request.accept! }.to raise_error(CustomExceptions::ConversationRequest::NotOpen)
      end
      expect(conversation.reload.assignee).to eq(owner)
    end
  end
end
