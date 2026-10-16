require 'rails_helper'

RSpec.describe 'Conversation requests API', type: :request do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, assignee: owner) }
  let(:conversation_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}" }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: owner)
    create(:inbox_member, inbox: conversation.inbox, user: colleague)
  end

  describe 'transfer through the assignments endpoint' do
    it 'creates a transfer request instead of reassigning' do
      post "#{conversation_path}/assignments", params: { assignee_id: colleague.id }, headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body.dig('conversation_request', 'request_type')).to eq('transfer')
      expect(conversation.reload.assignee).to eq(owner)
    end

    it "forbids agents from taking someone else's conversation" do
      post "#{conversation_path}/assignments", params: { assignee_id: colleague.id }, headers: colleague.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(conversation.reload.assignee).to eq(owner)
    end

    it 'lets supervisors reassign directly' do
      supervisor = create(:user, account: account, role: :agent)
      account.account_users.find_by(user: supervisor).update!(supervisor: true)
      create(:inbox_member, inbox: conversation.inbox, user: supervisor)

      post "#{conversation_path}/assignments", params: { assignee_id: colleague.id }, headers: supervisor.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload.assignee).to eq(colleague)
    end
  end

  describe 'POST /conversation_requests/:id/accept' do
    let!(:request) { ConversationRequest.create!(conversation: conversation, requester: owner, target: colleague, request_type: :transfer) }

    it 'lets the target accept and take the conversation' do
      post "/api/v1/accounts/#{account.id}/conversation_requests/#{request.id}/accept", headers: colleague.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload.assignee).to eq(colleague)
    end

    it 'refuses anyone else' do
      post "/api/v1/accounts/#{account.id}/conversation_requests/#{request.id}/accept", headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(request.reload).to be_pending
    end
  end

  describe 'participation' do
    it 'asks the assignee and unlocks replies once accepted' do
      post "#{conversation_path}/messages", params: { content: 'hi' }, headers: colleague.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "#{conversation_path}/requests", headers: colleague.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)

      ConversationRequest.last.accept!
      post "#{conversation_path}/messages", params: { content: 'hi' }, headers: colleague.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'lists the open requests of the current agent' do
      ConversationRequest.create!(conversation: conversation, requester: colleague, target: owner, request_type: :participation)

      get "/api/v1/accounts/#{account.id}/conversation_requests", headers: owner.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('request_type')).to eq(['participation'])
    end
  end

  describe 'reply lock' do
    it 'rejects public replies on unassigned conversations, even from administrators' do
      admin = create(:user, account: account, role: :administrator)
      conversation.update!(assignee: nil)

      post "#{conversation_path}/messages", params: { content: 'hi' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "#{conversation_path}/messages", params: { content: 'note', private: true }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end
end
