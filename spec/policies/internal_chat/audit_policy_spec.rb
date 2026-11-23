require 'rails_helper'

RSpec.describe InternalChat::AuditPolicy, type: :policy do
  subject(:audit_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:supervisor) { create(:user, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:ana) { create(:user, account: account) }
  let(:bruno) { create(:user, account: account) }
  let(:team) { create(:team, account: account) }
  let(:other_team) { create(:team, account: account) }
  let(:direct_channel) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }

  def context_for(user)
    { user: user, account: account, account_user: account.account_users.find_by(user: user) }
  end

  before do
    account.account_users.find_by(user: supervisor).update!(supervisor: true)
    create(:team_member, team: team, user: supervisor)
  end

  permissions :index? do
    it { expect(audit_policy).to permit(context_for(administrator), InternalChat::Channel) }
    it { expect(audit_policy).to permit(context_for(supervisor), InternalChat::Channel) }
    it { expect(audit_policy).not_to permit(context_for(agent), InternalChat::Channel) }
  end

  permissions :show? do
    it 'lets administrators audit any conversation' do
      expect(audit_policy).to permit(context_for(administrator), direct_channel)
    end

    it 'does not let a supervisor audit a conversation of people outside their teams' do
      expect(audit_policy).not_to permit(context_for(supervisor), direct_channel)
    end

    it 'lets a supervisor audit a direct conversation with someone from their team' do
      create(:team_member, team: team, user: ana)

      expect(audit_policy).to permit(context_for(supervisor), direct_channel)
    end

    it 'lets a supervisor audit the room of their team but not of another team' do
      room = InternalChat::Channel.find_or_create_for_team!(account, team)
      other_room = InternalChat::Channel.find_or_create_for_team!(account, other_team)

      expect(audit_policy).to permit(context_for(supervisor), room)
      expect(audit_policy).not_to permit(context_for(supervisor), other_room)
    end

    it 'does not let agents audit anything' do
      expect(audit_policy).not_to permit(context_for(agent), direct_channel)
    end
  end
end
