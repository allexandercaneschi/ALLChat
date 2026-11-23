require 'rails_helper'

RSpec.describe 'Internal chat help requests API', type: :request do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bruno) { create(:user, account: account, role: :agent) }
  let(:carla) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/internal_chat/help_requests" }

  it 'sends the request to the chosen person in their direct channel' do
    post path, params: { recipient_id: bruno.id, content: 'preciso de ajuda' }, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    message = InternalChat::Message.last
    expect(message).to be_help_request
    expect(message.recipient).to eq(bruno)
    expect(message.channel.members).to contain_exactly(ana, bruno)
  end

  it 'broadcasts only to the sender and the recipient' do
    expect do
      post path, params: { recipient_id: bruno.id, content: 'ajuda' }, headers: ana.create_new_auth_token, as: :json
    end.to have_enqueued_job(ActionCableBroadcastJob).with(contain_exactly(ana.pubsub_token, bruno.pubsub_token), anything, anything)
  end

  it 'notifies only the recipient' do
    expect do
      post path, params: { recipient_id: bruno.id, content: 'ajuda' }, headers: ana.create_new_auth_token, as: :json
    end.to have_enqueued_job(InternalChat::PushNotificationJob).with(anything, bruno.id).exactly(:once)
  end

  it 'links the request to a conversation of the account' do
    conversation = create(:conversation, account: account)

    post path, params: { recipient_id: bruno.id, content: 'ajuda', conversation_id: conversation.display_id },
               headers: ana.create_new_auth_token, as: :json

    expect(InternalChat::Message.last.conversation).to eq(conversation)
  end

  it 'refuses a list of recipients, so it can never be a broadcast' do
    post path, params: { recipient_id: [bruno.id, carla.id], content: 'ajuda' }, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(InternalChat::Message.count).to eq(0)
  end

  it 'refuses to ask for help from yourself' do
    post path, params: { recipient_id: ana.id, content: 'ajuda' }, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'needs a recipient and content' do
    post path, params: { content: 'ajuda' }, headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post path, params: { recipient_id: bruno.id }, headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not accept a recipient from another account' do
    stranger = create(:user, account: create(:account))

    post path, params: { recipient_id: stranger.id, content: 'ajuda' }, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  describe 'to a whole team' do
    let(:team) { create(:team, account: account) }

    before { [ana, bruno].each { |user| create(:team_member, team: team, user: user) } }

    it 'posts the request in the room of the team and notifies every other member' do
      expect do
        post path, params: { team_id: team.id, content: 'alguém sabe configurar o DNS?' }, headers: ana.create_new_auth_token, as: :json
      end.to have_enqueued_job(InternalChat::PushNotificationJob).with(anything, bruno.id).exactly(:once)

      expect(response).to have_http_status(:success)
      message = InternalChat::Message.last
      expect(message).to be_help_request
      expect(message.recipient).to be_nil
      expect(message.channel.team).to eq(team)
    end

    it 'refuses a team the agent does not belong to' do
      other_team = create(:team, account: account)

      post path, params: { team_id: other_team.id, content: 'ajuda' }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses a request for a person and a team at once' do
      post path, params: { team_id: team.id, recipient_id: bruno.id, content: 'ajuda' }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
