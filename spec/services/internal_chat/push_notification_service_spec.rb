require 'rails_helper'

RSpec.describe InternalChat::PushNotificationService do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, name: 'Ana') }
  let(:bruno) { create(:user, account: account) }
  let(:channel) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }
  let(:message) { channel.messages.create!(account: account, sender: ana, content: 'preciso de ajuda com o servidor') }
  let(:notification_setting) { bruno.notification_settings.find_by(account: account) }
  let(:fcm_double) { instance_double(FCM) }
  let(:fcm_service_double) { instance_double(Notification::FcmService, fcm_client: fcm_double) }

  before do
    allow(WebPush).to receive(:payload_send).and_return(true)
    allow(Notification::FcmService).to receive(:new).and_return(fcm_service_double)
    allow(fcm_double).to receive(:send_v1).and_return({ body: { 'results': [] }.to_json })
    allow(GlobalConfigService).to receive(:load).with('FIREBASE_PROJECT_ID', nil).and_return('project')
    allow(GlobalConfigService).to receive(:load).with('FIREBASE_CREDENTIALS', nil).and_return('credentials')
    create(:notification_subscription, user: bruno, identifier: 'browser-subscription')
    create(:notification_subscription, user: bruno, subscription_type: 'fcm', identifier: 'fcm-subscription')
  end

  context 'when the user turned the preference on' do
    before { notification_setting.update!(selected_push_flags: [:push_internal_message]) }

    it 'sends the browser push with the sender name and a link that is not a conversation' do
      with_modified_env VAPID_PUBLIC_KEY: 'test' do
        described_class.new(message: message, recipient: bruno).perform
      end

      expect(WebPush).to have_received(:payload_send) do |args|
        payload = JSON.parse(args[:message])
        expect(payload['title']).to eq('New message from Ana')
        expect(payload['tag']).to eq("internal_chat_#{channel.id}")
        expect(payload['url']).to include("/app/accounts/#{account.id}")
      end
    end

    it 'sends the FCM push to the phone even when no inbox is open' do
      described_class.new(message: message, recipient: bruno).perform

      expect(fcm_double).to have_received(:send_v1) do |options|
        expect(options[:notification][:body]).to eq('preciso de ajuda com o servidor')
        expect(JSON.parse(options[:data][:payload]).dig('data', 'notification', 'notification_type')).to eq('internal_message')
      end
    end

    it 'uses the help request title for help requests' do
      help = channel.messages.create!(account: account, sender: ana, recipient: bruno, kind: :help_request, content: 'socorro')
      with_modified_env VAPID_PUBLIC_KEY: 'test' do
        described_class.new(message: help, recipient: bruno).perform
      end

      expect(WebPush).to have_received(:payload_send) { |args| expect(JSON.parse(args[:message])['title']).to eq('Ana is asking for your help') }
    end
  end

  context 'when the user did not turn the preference on' do
    it 'sends nothing' do
      with_modified_env VAPID_PUBLIC_KEY: 'test' do
        described_class.new(message: message, recipient: bruno).perform
      end

      expect(WebPush).not_to have_received(:payload_send)
      expect(fcm_double).not_to have_received(:send_v1)
    end
  end
end
