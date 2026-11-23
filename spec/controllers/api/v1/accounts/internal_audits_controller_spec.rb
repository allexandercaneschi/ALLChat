require 'rails_helper'

RSpec.describe 'Internal chat audit API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:supervisor) { create(:user, account: account, role: :agent) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bruno) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:direct) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }
  let(:path) { "/api/v1/accounts/#{account.id}/internal_chat/audit" }

  before do
    account.account_users.find_by(user: supervisor).update!(supervisor: true)
    create(:team_member, team: team, user: supervisor)
    InternalChat::Messages::CreateService.new(channel: direct, sender: ana, content: 'segredo da conversa').perform
  end

  it 'lets an administrator list and read any conversation, and records each read' do
    get path, headers: administrator.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('id')).to eq([direct.id])
    expect(response.parsed_body['payload'].first['participants'].pluck('id')).to contain_exactly(ana.id, bruno.id)

    expect { get "#{path}/#{direct.id}", headers: administrator.create_new_auth_token, as: :json }.to change(InternalChat::AuditLog, :count).by(1)
    expect(response.parsed_body['payload'].pluck('content')).to eq(['segredo da conversa'])
    log = InternalChat::AuditLog.last
    expect(log).to have_attributes(auditor_id: administrator.id, channel_id: direct.id, action: 'read_messages')
  end

  it 'does not show a supervisor conversations of people outside their teams' do
    get path, headers: supervisor.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to eq([])

    get "#{path}/#{direct.id}", headers: supervisor.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(InternalChat::AuditLog.count).to eq(0)
  end

  it 'shows a supervisor the direct conversations of their team members and the team room' do
    create(:team_member, team: team, user: ana)
    room = InternalChat::Channel.find_or_create_for_team!(account, team)

    get path, headers: supervisor.create_new_auth_token, as: :json

    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(direct.id, room.id)
  end

  it 'refuses agents' do
    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    get "#{path}/#{direct.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
