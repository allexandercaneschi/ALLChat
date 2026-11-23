require 'rails_helper'

RSpec.describe InternalChat::Message do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account) }
  let(:bruno) { create(:user, account: account) }
  let(:carla) { create(:user, account: account) }
  let(:channel) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }

  it 'requires content within the size limit' do
    expect(described_class.new(account: account, channel: channel, sender: ana, content: '')).not_to be_valid
    expect(described_class.new(account: account, channel: channel, sender: ana, content: 'a' * 5001)).not_to be_valid
  end

  it 'only accepts messages from members of the channel' do
    expect(described_class.new(account: account, channel: channel, sender: carla, content: 'oi')).not_to be_valid
    expect(described_class.new(account: account, channel: channel, sender: ana, content: 'oi')).to be_valid
  end

  describe 'help requests' do
    it 'are valid when addressed to the other person of a direct channel' do
      message = described_class.new(account: account, channel: channel, sender: ana, recipient: bruno, content: 'ajuda', kind: :help_request)

      expect(message).to be_valid
    end

    it 'need a recipient' do
      message = described_class.new(account: account, channel: channel, sender: ana, content: 'ajuda', kind: :help_request)

      expect(message).not_to be_valid
    end

    it 'cannot be addressed to someone outside the channel' do
      message = described_class.new(account: account, channel: channel, sender: ana, recipient: carla, content: 'ajuda', kind: :help_request)

      expect(message).not_to be_valid
    end

    it 'cannot be sent to a team room' do
      team = create(:team, account: account)
      create(:team_member, team: team, user: ana)
      create(:team_member, team: team, user: bruno)
      room = InternalChat::Channel.find_or_create_for_team!(account, team)
      message = described_class.new(account: account, channel: room, sender: ana, recipient: bruno, content: 'ajuda', kind: :help_request)

      expect(message).not_to be_valid
    end
  end

  describe '.past_retention' do
    it 'uses 90 days by default and the account setting when present' do
      old = described_class.create!(account: account, channel: channel, sender: ana, content: 'velha', created_at: 100.days.ago)
      recent = described_class.create!(account: account, channel: channel, sender: ana, content: 'nova', created_at: 10.days.ago)

      expect(described_class.past_retention(account)).to contain_exactly(old)

      account.update!(settings: account.settings.merge('internal_chat_retention_days' => 5))
      expect(described_class.past_retention(account)).to contain_exactly(old, recent)
    end
  end
end
