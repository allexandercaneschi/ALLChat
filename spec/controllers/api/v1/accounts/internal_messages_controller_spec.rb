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
end
