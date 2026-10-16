require 'rails_helper'

RSpec.describe Conversations::OwnershipRules do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:supervisor) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }

  before { account.account_users.find_by(user: supervisor).update!(supervisor: true) }

  def rules(user)
    described_class.new(conversation: conversation, user: user)
  end

  describe '#can_reply?' do
    it 'locks unassigned conversations for everyone' do
      [agent, supervisor, admin].each { |user| expect(rules(user).can_reply?).to be(false) }
    end

    context 'when the conversation belongs to another agent' do
      before { conversation.update!(assignee: other_agent) }

      it 'lets the assignee, supervisors and administrators reply' do
        expect(rules(other_agent).can_reply?).to be(true)
        expect(rules(supervisor).can_reply?).to be(true)
        expect(rules(admin).can_reply?).to be(true)
      end

      it 'locks plain agents until the assignee accepts their participation' do
        expect(rules(agent).can_reply?).to be(false)

        ConversationRequest.create!(conversation: conversation, requester: agent, target: other_agent,
                                    request_type: :participation, status: :accepted)
        expect(rules(agent).can_reply?).to be(true)
      end

      it 'drops the participation when the conversation changes hands' do
        ConversationRequest.create!(conversation: conversation, requester: agent, target: other_agent,
                                    request_type: :participation, status: :accepted)
        conversation.update!(assignee: admin)

        expect(rules(agent).can_reply?).to be(false)
      end
    end
  end

  describe '#assignment_decision' do
    it 'lets managers assign anyone directly' do
      conversation.update!(assignee: other_agent)

      expect(rules(supervisor).assignment_decision(agent.id)).to eq(:direct)
      expect(rules(admin).assignment_decision(nil)).to eq(:direct)
    end

    it 'lets agents take unassigned conversations only' do
      expect(rules(agent).assignment_decision(agent.id)).to eq(:direct)

      conversation.update!(assignee: other_agent)
      expect(rules(agent).assignment_decision(agent.id)).to eq(:forbidden)
    end

    it 'turns an agent hand-over into a transfer request' do
      conversation.update!(assignee: agent)

      expect(rules(agent).assignment_decision(other_agent.id)).to eq(:transfer_request)
      expect(rules(agent).assignment_decision(nil)).to eq(:direct)
    end

    it "forbids agents from reassigning someone else's conversation" do
      conversation.update!(assignee: other_agent)

      expect(rules(agent).assignment_decision(admin.id)).to eq(:forbidden)
      expect(rules(agent).assignment_decision(nil)).to eq(:forbidden)
    end
  end
end
