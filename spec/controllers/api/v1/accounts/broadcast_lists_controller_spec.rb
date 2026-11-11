require 'rails_helper'

RSpec.describe 'Broadcast lists API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:lists_path) { "/api/v1/accounts/#{account.id}/broadcast_lists" }
  let(:list) { account.broadcast_lists.create!(name: 'Clientes Tecmar') }

  describe 'POST /broadcast_lists' do
    it 'creates the list with its label' do
      post lists_path, params: { broadcast_list: { name: 'Clientes Tecmar' } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['label']).to eq('lista-clientes-tecmar')
      expect(account.labels.exists?(title: 'lista-clientes-tecmar')).to be(true)
    end

    it 'forbids agents' do
      post lists_path, params: { broadcast_list: { name: 'Clientes' } }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /broadcast_lists' do
    it 'shows agents only the lists they are authorized on' do
      list
      other = account.broadcast_lists.create!(name: 'Fornecedores')
      other.users << agent

      get lists_path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('name')).to eq(['Fornecedores'])
    end

    it 'shows administrators every list' do
      list
      account.broadcast_lists.create!(name: 'Fornecedores')

      get lists_path, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('name')).to eq(['Clientes Tecmar', 'Fornecedores'])
    end
  end

  describe 'PATCH /broadcast_lists/:id' do
    it 'renames the label of its contacts' do
      contact = create(:contact, account: account)
      contact.update!(label_list: [list.label.title])

      patch "#{lists_path}/#{list.id}", params: { broadcast_list: { name: 'Grupo Tecmar' } }, headers: admin.create_new_auth_token, as: :json
      perform_enqueued_jobs

      expect(response).to have_http_status(:success)
      expect(contact.reload.label_list).to eq(['lista-grupo-tecmar'])
    end
  end

  describe 'PATCH /broadcast_lists/:id/users' do
    it 'authorizes the chosen users' do
      patch "#{lists_path}/#{list.id}/users", params: { user_ids: [agent.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(list.reload.users).to eq([agent])
    end
  end

  describe 'DELETE /broadcast_lists/:id' do
    it 'deletes the list and its label' do
      label_id = list.label_id

      delete "#{lists_path}/#{list.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(BroadcastList.exists?(list.id)).to be(false)
      expect(Label.exists?(label_id)).to be(false)
    end
  end

  describe 'contacts' do
    let(:contacts_path) { "#{lists_path}/#{list.id}/contacts" }

    before { list.users << agent }

    it 'adds and removes contacts through the label' do
      contact = create(:contact, account: account)

      post contacts_path, params: { contact_ids: [contact.id] }, headers: agent.create_new_auth_token, as: :json
      expect(contact.reload.label_list).to include('lista-clientes-tecmar')

      delete "#{contacts_path}/#{contact.id}", headers: agent.create_new_auth_token, as: :json
      expect(contact.reload.label_list).not_to include('lista-clientes-tecmar')
    end

    it 'hides the list from agents without authorization' do
      get "#{lists_path}/#{account.broadcast_lists.create!(name: 'Outra').id}/contacts", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'imports a file saved by the ALL Mensagens app' do
      existing = create(:contact, account: account, phone_number: '+553288887777')
      content = "Cliente Antigo,5532988887777\nJoao Teste - Compras - Cliente,32 99911-2233\nSem numero,abc\n"

      post "#{contacts_path}/import", params: { content: content }, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('added' => 2, 'created' => 1, 'already_in_list' => 0, 'invalid_lines' => [3])
      expect(existing.reload.label_list).to include('lista-clientes-tecmar')
      expect(account.contacts.find_by(phone_number: '+553299112233').name).to eq('Joao Teste - Compras - Cliente')
    end
  end
end
