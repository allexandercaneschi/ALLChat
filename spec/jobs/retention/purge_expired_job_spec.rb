require 'rails_helper'

RSpec.describe Retention::PurgeExpiredJob do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account) }
  let(:bruno) { create(:user, account: account) }
  let(:channel) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }
  let!(:recent_message) { channel.messages.create!(account: account, sender: ana, content: 'nova', created_at: 30.days.ago) }
  let!(:old_open) { create(:conversation, account: account, status: :open, last_activity_at: 400.days.ago) }
  let!(:recent_resolved) { create(:conversation, account: account, status: :resolved, last_activity_at: 30.days.ago) }

  before do
    channel.messages.create!(account: account, sender: ana, content: 'velha', created_at: 400.days.ago)
    create(:conversation, account: account, status: :resolved, last_activity_at: 400.days.ago)
  end

  it 'deletes nothing while the cleanup is off, which is the default' do
    described_class.perform_now

    expect(InternalChat::Message.count).to eq(2)
    expect(Conversation.count).to eq(3)
  end

  it 'reports what would be removed without removing it' do
    expect(described_class.report(account)).to eq(internal_chat_messages: 1, conversations: 1)
    expect(InternalChat::Message.count).to eq(2)
  end

  context 'when the account turned the cleanup on' do
    before { account.update!(settings: account.settings.merge('retention_cleanup_enabled' => true)) }

    it 'removes old internal messages and old resolved conversations only' do
      described_class.perform_now

      expect(InternalChat::Message.pluck(:id)).to eq([recent_message.id])
      expect(Conversation.pluck(:id)).to contain_exactly(old_open.id, recent_resolved.id)
    end

    it 'respects the periods set on the account' do
      account.update!(settings: account.settings.merge('internal_chat_retention_days' => 10))

      described_class.perform_now

      expect(InternalChat::Message.count).to eq(0)
    end

    it 'leaves other accounts alone' do
      other_account = create(:account)
      other_conversation = create(:conversation, account: other_account, status: :resolved, last_activity_at: 400.days.ago)

      described_class.perform_now

      expect(Conversation.exists?(other_conversation.id)).to be(true)
    end
  end
end
