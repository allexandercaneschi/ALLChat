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

  context 'with a help request' do
    let(:help_request) do
      InternalChat::Message.create!(account: account, channel: channel, sender: ana, recipient: bruno, kind: :help_request, content: 'ajuda')
    end

    permissions :claim? do
      it { expect(message_policy).to permit(context_for(bruno), help_request) }
      it { expect(message_policy).not_to permit(context_for(ana), help_request) }
      it { expect(message_policy).not_to permit(context_for(carla), help_request) }
    end

    permissions :resolve? do
      it { expect(message_policy).to permit(context_for(ana), help_request) }
      it { expect(message_policy).not_to permit(context_for(bruno), help_request) }

      it 'is open to who took it' do
        help_request.claim!(bruno)

        expect(message_policy).to permit(context_for(bruno), help_request.reload)
      end
    end
  end
end
