require 'rails_helper'

RSpec.describe AutoReplyFeedbackListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversation) do
    create(:conversation, account: account, status: :resolved, custom_attributes: { 'resposta_automatica' => 'silenciada' })
  end
  let(:text) { 'Bom dia! No momento estamos fora do escritório, voltamos amanhã.' }
  let!(:held_message) do
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :incoming,
                     sender: conversation.contact, content: text, additional_attributes: { 'resposta_automatica' => 'silenciada' })
  end

  before { AutoReplySignature.remember!(conversation.contact, text, verdict: :auto_reply, source: :ai) }

  it 'learns that the text is human when an agent removes the label' do
    event = Events::Base.new('conversation.updated', Time.zone.now,
                             conversation: conversation, changed_attributes: { 'label_list' => [['resposta-automatica'], []] })

    listener.conversation_updated(event)

    expect(AutoReplySignature.lookup(conversation.contact, text)).to have_attributes(verdict: 'human', source: 'agent')
    expect(held_message.reload.additional_attributes['resposta_automatica']).to eq('liberada')
    expect(conversation.reload.custom_attributes['resposta_automatica']).to eq('liberada')
  end

  it 'ignores other updates' do
    event = Events::Base.new('conversation.updated', Time.zone.now,
                             conversation: conversation, changed_attributes: { 'label_list' => [[], ['resposta-automatica']] })

    listener.conversation_updated(event)

    expect(AutoReplySignature.lookup(conversation.contact, text)).to have_attributes(verdict: 'auto_reply')
  end

  it 'stops treating a reopened conversation as held' do
    conversation.update!(status: :open)

    listener.conversation_opened(Events::Base.new('conversation.opened', Time.zone.now, conversation: conversation))

    expect(conversation.reload.custom_attributes['resposta_automatica']).to eq('liberada')
  end
end
