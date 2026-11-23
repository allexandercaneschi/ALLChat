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

  def deliver(pushed_message)
    with_modified_env VAPID_PUBLIC_KEY: 'test' do
      described_class.new(message: pushed_message, recipient: bruno).perform
    end
  end

  def close_every_inbox_of_bruno
    inbox = create(:inbox, account: account, working_hours_enabled: true)
    create(:inbox_member, inbox: inbox, user: bruno)
    inbox.working_hours.each { |hour| hour.update!(closed_all_day: true, open_all_day: false) }
  end

  before do
    allow(WebPush).to receive(:payload_send).and_return(true)
    allow(Notification::FcmService).to receive(:new).and_return(fcm_service_double)
    allow(fcm_double).to receive(:send_v1).and_return({ body: { 'results': [] }.to_json })
    allow(GlobalConfigService).to receive(:load).with('FIREBASE_PROJECT_ID', nil).and_return('project')
    allow(GlobalConfigService).to receive(:load).with('FIREBASE_CREDENTIALS', nil).and_return('credentials')
    create(:notification_subscription, user: bruno, identifier: 'browser-subscription')
    create(:notification_subscription, user: bruno, subscription_type: 'fcm', identifier: 'fcm-subscription')
  end

  it 'is turned on by default for new users' do
    expect(notification_setting.push_internal_message?).to be(true)
  end

  it 'sends the browser push with the sender name and a link that is not a conversation' do
    deliver(message)

    expect(WebPush).to have_received(:payload_send) do |args|
      payload = JSON.parse(args[:message])
      expect(payload['title']).to eq('New message from Ana')
      expect(payload['tag']).to eq("internal_chat_#{channel.id}")
      expect(payload['url']).to include("/app/accounts/#{account.id}")
      expect(payload['urgent']).to be(false)
    end
  end

  it 'sends the FCM push to the phone even when no inbox is open' do
    deliver(message)

    expect(fcm_double).to have_received(:send_v1) do |options|
      expect(options[:notification][:body]).to eq('preciso de ajuda com o servidor')
      expect(JSON.parse(options[:data][:payload]).dig('data', 'notification', 'notification_type')).to eq('internal_message')
      expect(options[:android]).to eq({ priority: 'high' })
    end
  end

  it 'sends nothing when the user turned the preference off' do
    notification_setting.update!(selected_push_flags: [])

    deliver(message)

    expect(WebPush).not_to have_received(:payload_send)
    expect(fcm_double).not_to have_received(:send_v1)
  end

  describe 'titles' do
    it 'tells who is asking for help, to the person or to the team' do
      help = channel.messages.create!(account: account, sender: ana, recipient: bruno, kind: :help_request, content: 'socorro')
      deliver(help)
      expect(WebPush).to have_received(:payload_send) { |args| expect(JSON.parse(args[:message])['title']).to eq('Ana is asking for your help') }
    end

    it 'tells the team asked for help' do
      team = create(:team, account: account)
      [ana, bruno].each { |user| create(:team_member, team: team, user: user) }
      room = InternalChat::Channel.find_or_create_for_team!(account, team)
      help = room.messages.create!(account: account, sender: ana, kind: :help_request, content: 'socorro')
      deliver(help)

      expect(WebPush).to have_received(:payload_send) { |args| expect(JSON.parse(args[:message])['title']).to eq('Ana asked the team for help') }
    end

    it 'tells who mentioned the user' do
      mention = channel.messages.create!(account: account, sender: ana, content: '@bruno olha', mentioned_user_ids: [bruno.id])
      deliver(mention)

      expect(WebPush).to have_received(:payload_send) { |args| expect(JSON.parse(args[:message])['title']).to eq('Ana mentioned you') }
    end
  end

  context 'when the recipient is out of business hours' do
    before { close_every_inbox_of_bruno }

    it 'sends nothing for a normal message or a help request' do
      deliver(message)

      expect(WebPush).not_to have_received(:payload_send)
      expect(fcm_double).not_to have_received(:send_v1)
    end

    it 'still sends a mention, as urgent' do
      mention = channel.messages.create!(account: account, sender: ana, content: '@bruno olha', mentioned_user_ids: [bruno.id])
      deliver(mention)

      expect(WebPush).to have_received(:payload_send) { |args| expect(JSON.parse(args[:message])['urgent']).to be(true) }
    end

    it 'still sends a message marked as urgent, calling attention on the phone' do
      urgent = channel.messages.create!(account: account, sender: ana, content: 'caiu o servidor', urgent: true)
      deliver(urgent)

      expect(fcm_double).to have_received(:send_v1) do |options|
        expect(options[:android]).to include(priority: 'high', notification: { channel_id: 'urgent', sound: 'urgent' })
        expect(options[:apns][:payload][:aps]).to include('interruption-level': 'time-sensitive')
      end
    end

    it 'still sends the attention nudge' do
      nudge = channel.messages.create!(account: account, sender: ana, kind: :nudge, content: '')
      deliver(nudge)

      expect(WebPush).to have_received(:payload_send) { |args| expect(JSON.parse(args[:message])['title']).to eq('Ana is calling your attention') }
    end

    it 'does not turn a mention of someone else into an urgent push' do
      other = channel.messages.create!(account: account, sender: ana, content: '@carla', mentioned_user_ids: [ana.id])
      deliver(other)

      expect(WebPush).not_to have_received(:payload_send)
    end
  end
end
