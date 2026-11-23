require 'rails_helper'

RSpec.describe InternalChat::Messages::CreateService do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account) }
  let(:bruno) { create(:user, account: account) }
  let(:carla) { create(:user, account: account) }
  let(:channel) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }

  it 'creates the message and marks it as read for the sender only' do
    message = described_class.new(channel: channel, sender: ana, content: 'oi').perform

    expect(message).to be_persisted
    expect(channel.participants.find_by(user: ana).last_read_message_id).to eq(message.id)
    expect(channel.participants.find_by(user: bruno).last_read_message_id).to be < message.id
  end

  it 'broadcasts only to the pubsub tokens of the channel members' do
    expect { described_class.new(channel: channel, sender: ana, content: 'oi').perform }
      .to have_enqueued_job(ActionCableBroadcastJob).with(
        contain_exactly(ana.pubsub_token, bruno.pubsub_token), 'internal_chat.message.created', hash_including(content: 'oi', account_id: account.id)
      )
  end

  it 'never uses the account-wide stream or the tokens of non-members' do
    described_class.new(channel: channel, sender: ana, content: 'oi').perform

    tokens = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |job| job['job_class'] == 'ActionCableBroadcastJob' }['arguments'].first
    expect(tokens).not_to include(carla.pubsub_token)
    expect(tokens.grep(/account_/)).to be_empty
  end

  it 'queues a push for everyone but the sender' do
    expect { described_class.new(channel: channel, sender: ana, content: 'oi').perform }
      .to have_enqueued_job(InternalChat::PushNotificationJob).with(anything, bruno.id).exactly(:once)
  end

  it 'notifies every other member of a team room' do
    team = create(:team, account: account)
    [ana, bruno, carla].each { |user| create(:team_member, team: team, user: user) }
    room = InternalChat::Channel.find_or_create_for_team!(account, team)

    expect { described_class.new(channel: room, sender: ana, content: 'time').perform }
      .to have_enqueued_job(InternalChat::PushNotificationJob).exactly(2).times
    expect(InternalChat::Channel.unread_counts_for(carla, [room.id])).to eq(room.id => 1)
  end

  it 'does not create the message when the sender is not a member' do
    expect { described_class.new(channel: channel, sender: carla, content: 'oi').perform }.to raise_error(ActiveRecord::RecordInvalid)
  end

  describe 'attention nudge' do
    it 'can not be used again before the cooldown' do
      described_class.new(channel: channel, sender: ana, kind: :nudge).perform

      expect { described_class.new(channel: channel, sender: ana, kind: :nudge).perform }
        .to raise_error(CustomExceptions::InternalChat::NudgeTooSoon) { |error| expect(error.to_hash[:retry_after]).to be_between(1, 60) }
    end

    it 'can be used again after the cooldown' do
      described_class.new(channel: channel, sender: ana, kind: :nudge).perform

      travel_to(61.seconds.from_now) do
        expect { described_class.new(channel: channel, sender: ana, kind: :nudge).perform }.not_to raise_error
      end
    end

    it 'has a cooldown for each person' do
      described_class.new(channel: channel, sender: ana, kind: :nudge).perform

      expect { described_class.new(channel: channel, sender: bruno, kind: :nudge).perform }.not_to raise_error
    end
  end

  describe 'mentions' do
    it 'keeps only members of the channel, never the sender' do
      team = create(:team, account: account)
      [ana, bruno].each { |user| create(:team_member, team: team, user: user) }
      room = InternalChat::Channel.find_or_create_for_team!(account, team)

      message = described_class.new(channel: room, sender: ana, content: '@bruno @carla', mentioned_user_ids: [bruno.id, carla.id, ana.id]).perform

      expect(message.mentioned_user_ids).to eq([bruno.id])
    end
  end

  describe 'company room' do
    let(:administrator) { create(:user, :administrator, account: account) }
    let(:room) { InternalChat::Channel.find_or_create_company_room!(account) }

    before { [ana, bruno, carla, administrator] }

    it 'only pushes to who was mentioned while everyone can send' do
      expect { described_class.new(channel: room, sender: ana, content: 'bom dia @bruno', mentioned_user_ids: [bruno.id]).perform }
        .to have_enqueued_job(InternalChat::PushNotificationJob).with(anything, bruno.id).exactly(:once)
    end

    it 'does not push to anyone when nobody is mentioned' do
      expect { described_class.new(channel: room, sender: ana, content: 'bom dia').perform }
        .not_to have_enqueued_job(InternalChat::PushNotificationJob)
    end

    it 'notifies everyone but the sender when the room is restricted, as an announcement' do
      room.update!(posting_policy: :admins_only)

      expect { described_class.new(channel: room, sender: administrator, content: 'reunião às 15h').perform }
        .to have_enqueued_job(InternalChat::PushNotificationJob).exactly(3).times
    end

    it 'counts the message as unread for the other members' do
      described_class.new(channel: room, sender: ana, content: 'bom dia').perform

      expect(InternalChat::Channel.unread_counts_for(bruno, [room.id])).to eq(room.id => 1)
    end
  end
end
