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

    it 'can go to the whole team in a team room, without a recipient' do
      team = create(:team, account: account)
      [ana, bruno].each { |user| create(:team_member, team: team, user: user) }
      room = InternalChat::Channel.find_or_create_for_team!(account, team)

      expect(described_class.new(account: account, channel: room, sender: ana, content: 'ajuda', kind: :help_request)).to be_valid
      expect(described_class.new(account: account, channel: room, sender: ana, recipient: bruno, content: 'ajuda',
                                 kind: :help_request)).not_to be_valid
    end
  end

  describe 'in the company room' do
    let(:company_room) { InternalChat::Channel.find_or_create_company_room!(account) }

    it 'accepts text and refuses help requests, urgent messages and nudges' do
      expect(described_class.new(account: account, channel: company_room, sender: ana, content: 'bom dia')).to be_valid
      expect(described_class.new(account: account, channel: company_room, sender: ana, content: 'ajuda', kind: :help_request)).not_to be_valid
      expect(described_class.new(account: account, channel: company_room, sender: ana, content: 'agora', urgent: true)).not_to be_valid
      expect(described_class.new(account: account, channel: company_room, sender: ana, kind: :nudge, content: '')).not_to be_valid
    end
  end

  describe 'urgent messages and attention nudges' do
    let(:team_room) do
      team = create(:team, account: account)
      [ana, bruno].each { |user| create(:team_member, team: team, user: user) }
      InternalChat::Channel.find_or_create_for_team!(account, team)
    end

    it 'are allowed in a direct channel, and a nudge needs no text' do
      expect(described_class.new(account: account, channel: channel, sender: ana, content: 'agora', urgent: true)).to be_valid
      expect(described_class.new(account: account, channel: channel, sender: ana, kind: :nudge, content: '')).to be_valid
    end

    it 'are refused in a team room' do
      expect(described_class.new(account: account, channel: team_room, sender: ana, content: 'agora', urgent: true)).not_to be_valid
      expect(described_class.new(account: account, channel: team_room, sender: ana, kind: :nudge, content: '')).not_to be_valid
    end
  end

  describe 'taking a help request' do
    let(:help_request) do
      described_class.create!(account: account, channel: channel, sender: ana, recipient: bruno, content: 'ajuda', kind: :help_request)
    end

    it 'lets only the first person take it' do
      help_request.claim!(bruno)

      expect(help_request.reload.claimed_by).to eq(bruno)
      expect { described_class.find(help_request.id).claim!(bruno) }.to raise_error(CustomExceptions::InternalChat::AlreadyClaimed)
    end

    it 'can be resolved' do
      help_request.resolve!

      expect(help_request.reload.resolved_at).to be_present
    end

    it 'only applies to help requests' do
      text = described_class.create!(account: account, channel: channel, sender: ana, content: 'oi')

      expect { text.claim!(bruno) }.to raise_error(CustomExceptions::InternalChat::NotAHelpRequest)
    end
  end

  describe '.past_retention' do
    it 'uses 365 days by default and the account setting when present' do
      old = described_class.create!(account: account, channel: channel, sender: ana, content: 'velha', created_at: 400.days.ago)
      recent = described_class.create!(account: account, channel: channel, sender: ana, content: 'nova', created_at: 10.days.ago)

      expect(described_class.past_retention(account)).to contain_exactly(old)

      account.update!(settings: account.settings.merge('internal_chat_retention_days' => 5))
      expect(described_class.past_retention(account)).to contain_exactly(old, recent)
    end
  end
end
