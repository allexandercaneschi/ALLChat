require 'rails_helper'

RSpec.describe InternalChat::Channel do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account) }
  let(:bruno) { create(:user, account: account) }
  let(:carla) { create(:user, account: account) }
  let(:team) { create(:team, account: account) }

  describe '.find_or_create_direct!' do
    it 'returns the same channel for the same pair, whatever the order' do
      channel = described_class.find_or_create_direct!(account, ana, bruno)

      expect(described_class.find_or_create_direct!(account, bruno, ana)).to eq(channel)
      expect(channel.participants.pluck(:user_id)).to contain_exactly(ana.id, bruno.id)
    end
  end

  describe '#member?' do
    it 'limits a direct channel to its two participants' do
      channel = described_class.find_or_create_direct!(account, ana, bruno)

      expect(channel.member?(ana)).to be(true)
      expect(channel.member?(carla)).to be(false)
    end

    it 'limits a team room to the members of the team' do
      create(:team_member, team: team, user: ana)
      room = described_class.find_or_create_for_team!(account, team)

      expect(room.member?(ana)).to be(true)
      expect(room.member?(bruno)).to be(false)
    end

    it 'gives administrators no access to channels they are not part of' do
      admin = create(:user, account: account, role: :administrator)
      channel = described_class.find_or_create_direct!(account, ana, bruno)

      expect(channel.member?(admin)).to be(false)
    end
  end

  describe '.visible_to' do
    it 'lists only the direct channels of the user and the rooms of their teams' do
      create(:team_member, team: team, user: ana)
      own_direct = described_class.find_or_create_direct!(account, ana, bruno)
      room = described_class.find_or_create_for_team!(account, team)
      described_class.find_or_create_direct!(account, bruno, carla)
      described_class.find_or_create_for_team!(account, create(:team, account: account))

      expect(described_class.visible_to(ana, account)).to contain_exactly(own_direct, room)
    end
  end

  describe '.unread_counts_for' do
    let(:channel) { described_class.find_or_create_direct!(account, ana, bruno) }

    it 'counts messages from others after the read pointer' do
      InternalChat::Messages::CreateService.new(channel: channel, sender: bruno, content: 'oi').perform
      InternalChat::Messages::CreateService.new(channel: channel, sender: bruno, content: 'tudo bem?').perform

      expect(described_class.unread_counts_for(ana, [channel.id])).to eq(channel.id => 2)
      expect(described_class.unread_counts_for(bruno, [channel.id])).to eq({})
      channel.participants.find_by(user: ana).mark_read!
      expect(described_class.unread_counts_for(ana, [channel.id])).to eq({})
    end

    it 'marks the conversation as read for whoever replies' do
      InternalChat::Messages::CreateService.new(channel: channel, sender: bruno, content: 'oi').perform
      InternalChat::Messages::CreateService.new(channel: channel, sender: ana, content: 'olá').perform

      expect(described_class.unread_counts_for(ana, [channel.id])).to eq({})
      expect(described_class.unread_counts_for(bruno, [channel.id])).to eq(channel.id => 1)
    end
  end

  describe '#ensure_participants!' do
    it 'does not count the existing history as unread for a new team member' do
      create(:team_member, team: team, user: ana)
      room = described_class.find_or_create_for_team!(account, team)
      InternalChat::Messages::CreateService.new(channel: room, sender: ana, content: 'antes').perform
      create(:team_member, team: team, user: bruno)
      room.ensure_participants!

      expect(described_class.unread_counts_for(bruno, [room.id])).to eq({})
    end
  end

  it 'rejects a team from another account' do
    channel = described_class.new(account: account, kind: :team_room, team: create(:team))

    expect(channel).not_to be_valid
  end

  describe 'company room' do
    let(:supervisor) { create(:user, account: account) }
    let(:administrator) { create(:user, :administrator, account: account) }
    let(:other_account_user) { create(:user, account: create(:account)) }
    let(:room) { described_class.find_or_create_company_room!(account) }

    before { account.account_users.find_by(user: supervisor).update!(supervisor: true) }

    it 'exists once per account' do
      expect(described_class.find_or_create_company_room!(account)).to eq(room)
      expect(described_class.company_room.where(account: account).count).to eq(1)
    end

    it 'has every user of the account as member, and nobody from another account' do
      [ana, bruno, administrator].each { |user| expect(room.member?(user)).to be(true) }
      expect(room.members).to include(ana, bruno, administrator)
      expect(room.member?(other_account_user)).to be(false)
      expect(room.members).not_to include(other_account_user)
    end

    it 'is visible to every user of the account' do
      expect(described_class.visible_to(ana, account)).to include(room)
      expect(described_class.visible_to(other_account_user, account)).to include(room) # scoped by account, membership is checked by the policy
      expect(described_class.visible_to(ana, create(:account))).not_to include(room)
    end

    it 'lets everyone send by default' do
      expect(room.posting_policy).to eq('everyone')
      [ana, supervisor, administrator].each { |user| expect(room.can_post?(account.account_users.find_by(user: user))).to be(true) }
    end

    it 'can be restricted to administrators' do
      room.update!(posting_policy: :admins_only)

      expect(room.can_post?(account.account_users.find_by(user: administrator))).to be(true)
      expect(room.can_post?(account.account_users.find_by(user: supervisor))).to be(false)
      expect(room.can_post?(account.account_users.find_by(user: ana))).to be(false)
    end

    it 'can be restricted to administrators and supervisors' do
      room.update!(posting_policy: :admins_and_supervisors)

      expect(room.can_post?(account.account_users.find_by(user: administrator))).to be(true)
      expect(room.can_post?(account.account_users.find_by(user: supervisor))).to be(true)
      expect(room.can_post?(account.account_users.find_by(user: ana))).to be(false)
    end

    it 'does not restrict direct conversations' do
      direct = described_class.find_or_create_direct!(account, ana, bruno)

      expect(direct.can_post?(account.account_users.find_by(user: ana))).to be(true)
      expect(described_class.new(account: account, kind: :direct, direct_key: '1:2', posting_policy: :admins_only)).not_to be_valid
    end
  end
end
