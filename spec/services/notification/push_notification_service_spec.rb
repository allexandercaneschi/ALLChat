require 'rails_helper'

describe Notification::PushNotificationService do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:notification) { create(:notification, user: user, account: user.accounts.first) }
  let(:fcm_double) { instance_double(FCM) }
  let(:fcm_service_double) { instance_double(Notification::FcmService, fcm_client: fcm_double) }

  describe '#perform' do
    context 'when the push server returns success' do
      before do
        allow(WebPush).to receive(:payload_send).and_return(true)
        allow(Rails.logger).to receive(:info)
        allow(Notification::FcmService).to receive(:new).and_return(fcm_service_double)
        allow(fcm_double).to receive(:send_v1).and_return({ body: { 'results': [] }.to_json })
        allow(GlobalConfigService).to receive(:load).with('FIREBASE_PROJECT_ID', nil).and_return('test_project_id')
        allow(GlobalConfigService).to receive(:load).with('FIREBASE_CREDENTIALS', nil).and_return('test_credentials')
      end

      it 'sends webpush notifications for webpush subscription' do
        with_modified_env VAPID_PUBLIC_KEY: 'test' do
          create(:notification_subscription, user: notification.user)

          described_class.new(notification: notification).perform
          expect(WebPush).to have_received(:payload_send)
          expect(Notification::FcmService).not_to have_received(:new)
          expect(Rails.logger).to have_received(:info).with("Browser push sent to #{user.email} with title #{notification.push_message_title}")
        end
      end

      it 'sends a fcm notification for firebase subscription' do
        with_modified_env ENABLE_PUSH_RELAY_SERVER: 'false' do
          create(:notification_subscription, user: notification.user, subscription_type: 'fcm')

          described_class.new(notification: notification).perform
          expect(Notification::FcmService).to have_received(:new)
          expect(fcm_double).to have_received(:send_v1)
          expect(WebPush).not_to have_received(:payload_send)
          expect(Rails.logger).to have_received(:info).with("FCM push sent to #{user.email} with title #{notification.push_message_title}")
        end
      end
    end
  end

  describe 'business hours of the inbox' do
    let(:inbox) { notification.conversation.inbox }

    before do
      allow(WebPush).to receive(:payload_send).and_return(true)
      allow(Rails.logger).to receive(:info)
      allow(Notification::FcmService).to receive(:new).and_return(fcm_service_double)
      allow(fcm_double).to receive(:send_v1).and_return({ body: { 'results': [] }.to_json })
      allow(GlobalConfigService).to receive(:load).with('FIREBASE_PROJECT_ID', nil).and_return('test_project_id')
      allow(GlobalConfigService).to receive(:load).with('FIREBASE_CREDENTIALS', nil).and_return('test_credentials')
      create(:notification_subscription, user: notification.user, subscription_type: 'fcm')
      # Default hours: Monday to Friday, 9:00-17:00 in the inbox timezone
      inbox.update!(timezone: 'UTC')
    end

    def perform_at(time)
      travel_to(Time.utc(*time)) do
        with_modified_env(ENABLE_PUSH_RELAY_SERVER: 'false') { described_class.new(notification: notification).perform }
      end
    end

    it 'sends the mobile push when the inbox does not use working hours' do
      inbox.update!(working_hours_enabled: false)

      perform_at([2024, 1, 21, 22, 0]) # Sunday night

      expect(fcm_double).to have_received(:send_v1)
    end

    it 'sends the mobile push while the inbox is open' do
      inbox.update!(working_hours_enabled: true)

      perform_at([2024, 1, 17, 10, 0]) # Wednesday 10:00

      expect(fcm_double).to have_received(:send_v1)
    end

    it 'does not send the mobile push when the inbox is closed' do
      inbox.update!(working_hours_enabled: true)

      perform_at([2024, 1, 17, 20, 0]) # Wednesday 20:00

      expect(fcm_double).not_to have_received(:send_v1)
      expect(Notification::FcmService).not_to have_received(:new)
    end

    it 'does not send the mobile push during the lunch break' do
      inbox.update!(working_hours_enabled: true)
      inbox.working_hours.find_by(day_of_week: 3).update!(
        break_start_hour: 12, break_start_minutes: 0, break_end_hour: 13, break_end_minutes: 0
      )

      perform_at([2024, 1, 17, 12, 30]) # Wednesday 12:30

      expect(fcm_double).not_to have_received(:send_v1)
    end

    it 'sends the mobile push again after the lunch break' do
      inbox.update!(working_hours_enabled: true)
      inbox.working_hours.find_by(day_of_week: 3).update!(
        break_start_hour: 12, break_start_minutes: 0, break_end_hour: 13, break_end_minutes: 0
      )

      perform_at([2024, 1, 17, 13, 0]) # Wednesday 13:00

      expect(fcm_double).to have_received(:send_v1)
    end

    it 'still sends the browser push when the inbox is closed' do
      inbox.update!(working_hours_enabled: true)
      create(:notification_subscription, :browser_push, user: notification.user)

      with_modified_env VAPID_PUBLIC_KEY: 'test' do
        perform_at([2024, 1, 17, 20, 0])
      end

      expect(WebPush).to have_received(:payload_send)
    end
  end

  context 'when the push server returns error' do
    it 'sends webpush notifications for webpush subscription' do
      with_modified_env VAPID_PUBLIC_KEY: 'test' do
        mock_response = instance_double(Net::HTTPResponse, body: 'Subscription is invalid')
        mock_host = 'fcm.googleapis.com'

        allow(WebPush).to receive(:payload_send).and_raise(WebPush::InvalidSubscription.new(mock_response, mock_host))
        allow(Rails.logger).to receive(:info)

        create(:notification_subscription, :browser_push, user: notification.user)

        expect(Rails.logger).to receive(:info) do |message|
          expect(message).to include('WebPush subscription expired:')
        end

        described_class.new(notification: notification).perform
      end
    end
  end
end
