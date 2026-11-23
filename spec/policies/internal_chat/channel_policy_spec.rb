require 'rails_helper'

RSpec.describe InternalChat::ChannelPolicy, type: :policy do
  subject(:channel_policy) { described_class }

  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account) }
  let(:bruno) { create(:user, account: account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:team) { create(:team, account: account) }
  let(:direct_channel) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }
  let(:team_room) { InternalChat::Channel.find_or_create_for_team!(account, team) }

  def context_for(user)
    { user: user, account: account, account_user: account.account_users.find_by(user: user) }
  end

  before { create(:team_member, team: team, user: ana) }

  permissions :show?, :create?, :read? do
    it { expect(channel_policy).to permit(context_for(ana), direct_channel) }
    it { expect(channel_policy).to permit(context_for(bruno), direct_channel) }
    it { expect(channel_policy).not_to permit(context_for(administrator), direct_channel) }

    it { expect(channel_policy).to permit(context_for(ana), team_room) }
    it { expect(channel_policy).not_to permit(context_for(bruno), team_room) }
    it { expect(channel_policy).not_to permit(context_for(administrator), team_room) }
  end

  permissions :index? do
    it { expect(channel_policy).to permit(context_for(ana), InternalChat::Channel) }
    it { expect(channel_policy).not_to permit({ user: ana, account: account, account_user: nil }, InternalChat::Channel) }
  end
end
