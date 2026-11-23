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

  context 'with a restricted room' do
    let(:administrator) { create(:user, :administrator, account: account) }
    let(:supervisor) { create(:user, account: account) }
    let(:room) { InternalChat::Channel.find_or_create_company_room!(account) }
    let(:room_message) { InternalChat::Message.new(channel: room) }

    before { account.account_users.find_by(user: supervisor).update!(supervisor: true) }

    permissions :create? do
      it 'lets every member send when the room is open to everyone' do
        [ana, supervisor, administrator].each { |user| expect(message_policy).to permit(context_for(user), room_message) }
      end

      it 'lets only administrators send when restricted to them' do
        room.update!(posting_policy: :admins_only)

        expect(message_policy).to permit(context_for(administrator), room_message)
        expect(message_policy).not_to permit(context_for(supervisor), room_message)
        expect(message_policy).not_to permit(context_for(ana), room_message)
      end

      it 'lets administrators and supervisors send when restricted to them' do
        room.update!(posting_policy: :admins_and_supervisors)

        expect(message_policy).to permit(context_for(administrator), room_message)
        expect(message_policy).to permit(context_for(supervisor), room_message)
        expect(message_policy).not_to permit(context_for(ana), room_message)
      end
    end

    permissions :index? do
      it 'keeps reading open to every member of a restricted room' do
        room.update!(posting_policy: :admins_only)

        expect(message_policy).to permit(context_for(ana), room_message)
      end
    end
  end
end
