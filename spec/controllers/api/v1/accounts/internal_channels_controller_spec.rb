require 'rails_helper'

RSpec.describe 'Internal chat channels API', type: :request do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bruno) { create(:user, account: account, role: :agent) }
  let(:carla) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:team) { create(:team, account: account) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/internal_chat/channels" }

  describe 'GET /internal_chat/channels' do
    it 'requires authentication' do
      get base_path

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists the direct channels of the agent with the other person and the unread count' do
      channel = InternalChat::Channel.find_or_create_direct!(account, ana, bruno)
      InternalChat::Messages::CreateService.new(channel: channel, sender: bruno, content: 'oi').perform
      InternalChat::Channel.find_or_create_direct!(account, bruno, carla)

      get base_path, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload'].select { |item| item['kind'] == 'direct' }
      expect(payload.size).to eq(1)
      expect(payload.first).to include('id' => channel.id, 'kind' => 'direct', 'unread_count' => 1)
      expect(payload.first['user']['id']).to eq(bruno.id)
      expect(payload.first['last_message']['content']).to eq('oi')
    end

    it 'lists the company room for every user of the account, with whether they can send' do
      get base_path, headers: ana.create_new_auth_token, as: :json

      room = response.parsed_body['payload'].find { |channel| channel['kind'] == 'company_room' }
      expect(room).to include('name' => account.name, 'posting_policy' => 'everyone', 'can_post' => true)
    end

    it 'tells an agent they can not send in a room restricted to administrators' do
      InternalChat::Channel.find_or_create_company_room!(account).update!(posting_policy: :admins_only)

      get base_path, headers: ana.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].find { |channel| channel['kind'] == 'company_room' }['can_post']).to be(false)

      get base_path, headers: administrator.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].find { |channel| channel['kind'] == 'company_room' }['can_post']).to be(true)
    end

    it 'lists the rooms of the teams of the agent only' do
      create(:team_member, team: team, user: ana)
      other_team = create(:team, account: account)
      create(:team_member, team: other_team, user: bruno)

      get base_path, headers: ana.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].reject { |channel| channel['kind'] == 'company_room' }
      expect(payload.pluck('kind')).to eq(['team_room'])
      expect(payload.first['team']).to include('id' => team.id)
    end

    it 'does not show direct channels of others to administrators' do
      InternalChat::Channel.find_or_create_direct!(account, ana, bruno)

      get base_path, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('kind')).to eq(['company_room'])
    end
  end

  describe 'POST /internal_chat/channels' do
    it 'opens the direct channel with another agent and reuses it next time' do
      post base_path, params: { kind: 'direct', user_id: bruno.id }, headers: ana.create_new_auth_token, as: :json
      first_id = response.parsed_body['id']
      post base_path, params: { kind: 'direct', user_id: ana.id }, headers: bruno.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(first_id)
      expect(InternalChat::Channel.direct.count).to eq(1)
    end

    it 'rejects a channel with yourself' do
      post base_path, params: { kind: 'direct', user_id: ana.id }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects an unknown kind' do
      post base_path, params: { kind: 'everyone' }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'does not open a direct channel with someone from another account' do
      stranger = create(:user, account: create(:account))

      post base_path, params: { kind: 'direct', user_id: stranger.id }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'opens the room of a team the agent belongs to' do
      create(:team_member, team: team, user: ana)

      post base_path, params: { kind: 'team_room', team_id: team.id }, headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['team']).to include('id' => team.id)
    end

    it 'refuses the room of a team the agent does not belong to, even for administrators' do
      post base_path, params: { kind: 'team_room', team_id: team.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(InternalChat::Channel.count).to eq(0)
    end
  end

  describe 'POST /internal_chat/channels/:id/read' do
    let(:channel) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }

    before { InternalChat::Messages::CreateService.new(channel: channel, sender: bruno, content: 'oi').perform }

    it 'zeroes the unread count' do
      post "#{base_path}/#{channel.id}/read", headers: ana.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['unread_count']).to eq(0)
    end

    it 'refuses people outside the channel' do
      post "#{base_path}/#{channel.id}/read", headers: carla.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
