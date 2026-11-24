require 'rails_helper'

# ALLChat: the conversation opened by a broadcast must stay in the inbox without an agent. Team routing
# (Team#allow_auto_assign, on by default) assigned an online member even with the inbox auto assignment off.
RSpec.describe Broadcasts::ContactSender do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account, allow_auto_assign: true) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5532999990000') }
  let(:options) do
    { 'content' => 'Aviso para {{nome}}', 'inbox_id' => inbox.id, 'team_id' => team.id, 'bot_id' => bot.id,
      'name_fallback' => 'cliente', 'resolve_after_minutes' => 30 }
  end

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    OnlineStatusTracker.update_presence(account.id, 'User', agent.id)
    OnlineStatusTracker.set_status(account.id, agent.id, 'online')
  end

  it 'opens the conversation in the chosen team without assigning any agent' do
    described_class.new(contact: contact, options: options).perform

    conversation = inbox.conversations.last
    expect(conversation.team_id).to eq(team.id)
    expect(conversation.assignee_id).to be_nil
    expect(conversation.custom_attributes['transmissao']).to eq('aguardando')
  end

  it 'does not assign the conversation when the contact replies and it is reopened' do
    described_class.new(contact: contact, options: options).perform
    conversation = inbox.conversations.last
    conversation.update!(status: :resolved)

    conversation.update!(status: :open)

    expect(conversation.reload.assignee_id).to be_nil
  end
end
