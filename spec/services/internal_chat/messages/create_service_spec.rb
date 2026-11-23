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
end
