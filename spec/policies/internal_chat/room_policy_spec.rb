require 'rails_helper'

RSpec.describe InternalChat::RoomPolicy, type: :policy do
  subject(:room_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:supervisor) { create(:user, account: account) }
  let(:agent) { create(:user, account: account) }

  def context_for(user)
    { user: user, account: account, account_user: account.account_users.find_by(user: user) }
  end

  before { account.account_users.find_by(user: supervisor).update!(supervisor: true) }

  permissions :index?, :update? do
    it { expect(room_policy).to permit(context_for(administrator), InternalChat::Channel) }
    it { expect(room_policy).not_to permit(context_for(supervisor), InternalChat::Channel) }
    it { expect(room_policy).not_to permit(context_for(agent), InternalChat::Channel) }
  end
end
