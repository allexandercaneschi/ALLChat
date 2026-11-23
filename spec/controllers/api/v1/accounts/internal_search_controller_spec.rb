require 'rails_helper'

RSpec.describe 'Internal chat search API', type: :request do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bruno) { create(:user, account: account, role: :agent) }
  let(:carla) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:direct) { InternalChat::Channel.find_or_create_direct!(account, ana, bruno) }
  let(:other_direct) { InternalChat::Channel.find_or_create_direct!(account, bruno, carla) }
  let(:path) { "/api/v1/accounts/#{account.id}/internal_chat/search" }

  def say(channel, sender, content)
    InternalChat::Messages::CreateService.new(channel: channel, sender: sender, content: content).perform
  end

  before do
    say(direct, ana, 'a senha do roteador mudou')
    say(direct, bruno, 'obrigado, anotei')
    say(other_direct, bruno, 'a senha do servidor é segredo')
  end

  it 'finds messages in all the conversations of the agent, never in others' do
    get path, params: { q: 'senha' }, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].pluck('content')).to eq(['a senha do roteador mudou'])
  end

  it 'finds inside one conversation when channel_id is given' do
    get path, params: { q: 'anotei', channel_id: direct.id }, headers: ana.create_new_auth_token, as: :json

    expect(response.parsed_body['payload'].pluck('content')).to eq(['obrigado, anotei'])
  end

  it 'ignores upper and lower case and treats % and _ as plain text' do
    get path, params: { q: 'SENHA' }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].size).to eq(1)

    get path, params: { q: '%%' }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to eq([])
  end

  it 'does not let the search reach a conversation of others, even for administrators' do
    get path, params: { q: 'senha', channel_id: other_direct.id }, headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    get path, params: { q: 'senha' }, headers: administrator.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to eq([])
  end

  it 'asks for at least two characters' do
    get path, params: { q: 's' }, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
