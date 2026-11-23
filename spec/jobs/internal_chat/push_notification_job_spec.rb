require 'rails_helper'

RSpec.describe InternalChat::PushNotificationJob do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account) }
  let(:bruno) { create(:user, account: account) }
  let(:channel) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }
  let(:message) { channel.messages.create!(account: account, sender: ana, content: 'oi') }
  let(:service) { instance_double(InternalChat::PushNotificationService, perform: true) }

  it 'delivers the push to the recipient' do
    allow(InternalChat::PushNotificationService).to receive(:new).with(message: message, recipient: bruno).and_return(service)

    described_class.perform_now(message.id, bruno.id)

    expect(service).to have_received(:perform)
  end

  it 'does nothing when the message no longer exists' do
    allow(InternalChat::PushNotificationService).to receive(:new)

    described_class.perform_now(0, bruno.id)

    expect(InternalChat::PushNotificationService).not_to have_received(:new)
  end
end
