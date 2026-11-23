require 'rails_helper'

RSpec.describe InternalChat::MessagePolicy, type: :policy do
  subject(:message_policy) { described_class }

  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account) }
  let(:bruno) { create(:user, account: account) }
  let(:carla) { create(:user, account: account) }
  let(:channel) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }
  let(:message) { InternalChat::Message.new(channel: channel) }

  def context_for(user)
    { user: user, account: account, account_user: account.account_users.find_by(user: user) }
  end

  permissions :index?, :create? do
    it { expect(message_policy).to permit(context_for(ana), message) }
    it { expect(message_policy).not_to permit(context_for(carla), message) }
  end
end
