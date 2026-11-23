require 'rails_helper'

RSpec.describe 'Internal chat rooms settings API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:supervisor) { create(:user, account: account, role: :agent) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/internal_chat/rooms" }

  before do
    account.account_users.find_by(user: supervisor).update!(supervisor: true)
    team
    agent
  end

  describe 'GET /internal_chat/rooms' do
    it 'lists the company room and the room of every team, creating the ones that do not exist yet' do
      get path, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload.pluck('kind')).to eq(%w[company_room team_room])
      expect(payload.first).to include('name' => account.name, 'posting_policy' => 'everyone', 'members_count' => 3)
      expect(payload.last).to include('name' => team.name, 'team_id' => team.id, 'posting_policy' => 'everyone')
    end

    it 'is only for administrators' do
      [supervisor, agent].each do |user|
        get path, headers: user.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /internal_chat/rooms/:id' do
    let(:room) { InternalChat::Channel.find_or_create_company_room!(account) }

    it 'sets who can send messages' do
      patch "#{path}/#{room.id}", params: { posting_policy: 'admins_and_supervisors' }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['posting_policy']).to eq('admins_and_supervisors')
      expect(room.reload.posting_admins_and_supervisors?).to be(true)
    end

    it 'refuses an unknown policy' do
      patch "#{path}/#{room.id}", params: { posting_policy: 'nobody' }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(room.reload.posting_everyone?).to be(true)
    end

    it 'does not let supervisors or agents change it' do
      [supervisor, agent].each do |user|
        patch "#{path}/#{room.id}", params: { posting_policy: 'admins_only' }, headers: user.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
      expect(room.reload.posting_everyone?).to be(true)
    end

    it 'does not touch direct conversations or rooms of other accounts' do
      direct = InternalChat::Channel.find_or_create_direct!(account, agent, supervisor)
      other_room = InternalChat::Channel.find_or_create_company_room!(create(:account))

      [direct, other_room].each do |channel|
        patch "#{path}/#{channel.id}", params: { posting_policy: 'admins_only' }, headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
