require 'rails_helper'

RSpec.describe 'Internal chat messages API', type: :request do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bruno) { create(:user, account: account, role: :agent) }
  let(:carla) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:channel) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }
  let(:path) { "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/messages" }

  describe 'GET /messages' do
    before do
      3.times { |index| InternalChat::Messages::CreateService.new(channel: channel, sender: bruno, content: "mensagem #{index}").perform }
    end

    it 'returns the messages in order' do
      get path, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('content')).to eq(['mensagem 0', 'mensagem 1', 'mensagem 2'])
      expect(response.parsed_body['meta']['has_more']).to be(false)
    end

    it 'pages backwards with before_id' do
      newest_id = channel.messages.maximum(:id)

      get path, params: { limit: 1, before_id: newest_id }, headers: ana.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('content')).to eq(['mensagem 1'])
      expect(response.parsed_body['meta']['has_more']).to be(true)
    end

    it 'does not show a direct conversation to a third agent or to administrators' do
      [carla, administrator].each do |outsider|
        get path, headers: outsider.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'does not find a channel from another account' do
      other_account = create(:account)
      other_user = create(:user, account: other_account)

      get "/api/v1/accounts/#{other_account.id}/internal_chat/channels/#{channel.id}/messages", headers: other_user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /messages' do
    it 'creates the message as the current agent' do
      post path, params: { content: 'oi Bruno' }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('content' => 'oi Bruno', 'kind' => 'text')
      expect(response.parsed_body['sender']['id']).to eq(ana.id)
    end

    it 'ignores a sender_id sent by the client' do
      post path, params: { content: 'oi', sender_id: bruno.id }, headers: ana.create_new_auth_token, as: :json

      expect(response.parsed_body['sender']['id']).to eq(ana.id)
    end

    it 'rejects empty and oversized content' do
      post path, params: { content: '' }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post path, params: { content: 'a' * 5001 }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses people outside the channel' do
      post path, params: { content: 'intruso' }, headers: carla.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(channel.messages.count).to eq(0)
    end

    it 'sends messages to the room of a team to its members only' do
      team = create(:team, account: account)
      [ana, bruno].each { |user| create(:team_member, team: team, user: user) }
      room = InternalChat::Channel.find_or_create_for_team!(account, team)
      room_path = "/api/v1/accounts/#{account.id}/internal_chat/channels/#{room.id}/messages"

      post room_path, params: { content: 'time' }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      post room_path, params: { content: 'intruso' }, headers: carla.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'urgent messages, mentions and the attention nudge' do
    it 'accepts an urgent message in a direct conversation' do
      post path, params: { content: 'caiu o servidor', urgent: true }, headers: ana.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('urgent' => true)
    end

    it 'refuses an urgent message in a team room' do
      team = create(:team, account: account)
      [ana, bruno].each { |user| create(:team_member, team: team, user: user) }
      room = InternalChat::Channel.find_or_create_for_team!(account, team)

      post "/api/v1/accounts/#{account.id}/internal_chat/channels/#{room.id}/messages", params: { content: 'agora', urgent: true },
                                                                                        headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'keeps the mentions of members only' do
      post path, params: { content: '@bruno', mentioned_user_ids: [bruno.id, carla.id] }, headers: ana.create_new_auth_token, as: :json

      expect(response.parsed_body['mentioned_user_ids']).to eq([bruno.id])
    end

    it 'sends the attention nudge and blocks the next one with the time left' do
      post path, params: { kind: 'nudge' }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['kind']).to eq('nudge')

      post path, params: { kind: 'nudge' }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['retry_after']).to be_between(1, 60)
    end

    it 'does not send help requests through the message endpoint' do
      post path, params: { kind: 'help_request', content: 'ajuda' }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'taking and resolving a help request' do
    let(:team) { create(:team, account: account) }
    let(:room) { InternalChat::Channel.find_or_create_for_team!(account, team) }
    let(:conversation) { create(:conversation, account: account) }
    let(:help_request) do
      room.messages.create!(account: account, sender: ana, kind: :help_request, content: 'alguém sabe configurar o DNS?', conversation: conversation)
    end
    let(:claim_path) { "/api/v1/accounts/#{account.id}/internal_chat/channels/#{room.id}/messages/#{help_request.id}/claim" }
    let(:resolve_path) { "/api/v1/accounts/#{account.id}/internal_chat/channels/#{room.id}/messages/#{help_request.id}/resolve" }

    before do
      [ana, bruno, carla].each { |user| create(:team_member, team: team, user: user) }
      create(:inbox_member, inbox: conversation.inbox, user: bruno)
    end

    it 'lets a teammate take it, opens the direct conversation and joins the customer conversation as participant' do
      post claim_path, headers: bruno.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['message']['claimed_by']['id']).to eq(bruno.id)
      expect(response.parsed_body['joined_conversation']).to be(true)
      expect(conversation.reload.conversation_participants.pluck(:user_id)).to include(bruno.id)
      expect(conversation.assignee_id).to be_nil
      direct = InternalChat::Channel.find(response.parsed_body['channel_id'])
      expect(direct.members).to contain_exactly(ana, bruno)
      expect(direct.messages.last.sender).to eq(bruno)
    end

    it 'does not fail when the person has no access to the inbox of the conversation, but does not join' do
      post claim_path, headers: carla.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['joined_conversation']).to be(false)
    end

    it 'lets only the first person take it' do
      post claim_path, headers: bruno.create_new_auth_token, as: :json
      post claim_path, headers: carla.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
    end

    it 'does not let the requester take their own request' do
      post claim_path, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not let people outside the team take it' do
      outsider = create(:user, account: account, role: :agent)

      post claim_path, headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'can be resolved by the requester or by who took it' do
      post claim_path, headers: bruno.create_new_auth_token, as: :json
      post resolve_path, headers: carla.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post resolve_path, headers: bruno.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['resolved_at']).to be_present
    end
  end
end
