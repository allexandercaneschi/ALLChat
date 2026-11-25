require 'rails_helper'

# ALLChat: automatic responders on WhatsApp must not reopen conversations in a loop.
RSpec.describe AutoReply::Guard do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5532999990001') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:auto_text) { 'Olá! Esta é uma mensagem automática. No momento não podemos atender, retornaremos em breve.' }

  before do
    allow(described_class).to receive(:enabled?).and_return(true)
    Redis::Alfred.delete(format(described_class::LOOP_KEY, contact_id: contact.id))
  end

  def send_ours(target = conversation, ago: 5.seconds)
    create(:message, account: account, inbox: inbox, conversation: target, message_type: :outgoing,
                     content: 'Seu atendimento foi finalizado.', created_at: ago.ago)
  end

  def receive_text(text, target = conversation)
    create(:message, account: account, inbox: inbox, conversation: target, message_type: :incoming, sender: contact, content: text)
  end

  def resolve_after_our_message(ago: 5.seconds)
    send_ours(ago: ago)
    conversation.update!(status: :resolved)
  end

  describe 'reply to a resolved conversation' do
    it 'holds an unknown fast reply and asks Chip' do
      resolve_after_our_message

      message = receive_text(auto_text)

      expect(conversation.reload).to be_resolved
      expect(conversation.custom_attributes['resposta_automatica']).to eq('analisando')
      expect(message.reload.additional_attributes['resposta_automatica']).to eq('analisando')
      expect(AutoReply::ClassifyJob).to have_been_enqueued.with(message)
    end

    it 'silences a text already known as automatic for the contact, at any time' do
      resolve_after_our_message(ago: 3.hours)
      signature = AutoReplySignature.remember!(contact, auto_text, verdict: :auto_reply, source: :ai)

      receive_text(auto_text.sub('Olá!', 'Ola'))

      conversation.reload
      expect(conversation).to be_resolved
      expect(conversation.custom_attributes['resposta_automatica']).to eq('silenciada')
      expect(conversation.label_list).to include('resposta-automatica')
      expect(signature.reload.hits).to eq(1)
      expect(Conversations::ActivityMessageJob).to have_been_enqueued.at_least(:once)
      expect(AutoReply::ClassifyJob).not_to have_been_enqueued
    end

    it 'reopens when the contact takes longer than the fast reply window' do
      resolve_after_our_message(ago: 10.minutes)

      receive_text(auto_text)

      expect(conversation.reload).to be_open
      expect(AutoReply::ClassifyJob).not_to have_been_enqueued
    end

    it 'reopens a fast reply whose text an agent marked as human' do
      resolve_after_our_message
      AutoReplySignature.remember!(contact, auto_text, verdict: :human, source: :agent)

      receive_text(auto_text)

      expect(conversation.reload).to be_open
    end

    it 'silences the third fast reply in a row and remembers it, even without Chip' do
      resolve_after_our_message
      2.times do
        receive_text(auto_text)
        conversation.reload.update!(status: :resolved, custom_attributes: {})
        send_ours(ago: 1.second)
      end

      receive_text(auto_text)

      expect(conversation.reload.custom_attributes['resposta_automatica']).to eq('silenciada')
      expect(AutoReplySignature.lookup(contact, auto_text)).to have_attributes(verdict: 'auto_reply', source: 'rule')
    end

    it 'releases a held conversation when the contact writes for real later' do
      resolve_after_our_message(ago: 2.hours)
      conversation.update!(custom_attributes: { 'resposta_automatica' => 'silenciada' })

      receive_text('Bom dia, o computador da recepção não liga')

      conversation.reload
      expect(conversation).to be_open
      expect(conversation.custom_attributes['resposta_automatica']).to eq('liberada')
    end
  end

  describe 'reply that creates a new conversation' do
    it 'resolves it without any message' do
      previous = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      send_ours(previous)
      previous.update!(status: :resolved)
      AutoReplySignature.remember!(contact, auto_text, verdict: :auto_reply, source: :ai)

      receive_text(auto_text)

      conversation.reload
      expect(conversation).to be_resolved
      expect(conversation.custom_attributes).to include('encerramento_tipo' => 'sem_mensagem', 'resposta_automatica' => 'silenciada')
    end
  end

  describe 'reply to a broadcast waiting for an answer' do
    it 'ends the broadcast as unanswered' do
      conversation.update!(custom_attributes: { 'transmissao' => 'aguardando', 'transmissao_resolver_em' => 30.minutes.from_now.iso8601 })
      send_ours
      AutoReplySignature.remember!(contact, auto_text, verdict: :auto_reply, source: :ai)

      message = receive_text(auto_text)
      BroadcastReplyListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: message.reload))

      conversation.reload
      expect(conversation).to be_resolved
      expect(conversation.custom_attributes).to include('transmissao' => 'encerrada', 'encerramento_tipo' => 'sem_mensagem')
      expect(conversation.custom_attributes).not_to have_key('transmissao_resolver_em')
    end
  end

  describe 'conversations it does not touch' do
    it 'ignores a conversation in progress' do
      send_ours
      receive_text(auto_text)

      expect(conversation.reload).to be_open
      expect(conversation.custom_attributes).not_to have_key('resposta_automatica')
    end

    it 'ignores inboxes other than API and WhatsApp' do
      widget_conversation = create(:conversation, account: account)
      create(:message, account: account, inbox: widget_conversation.inbox, conversation: widget_conversation,
                       message_type: :outgoing, created_at: 5.seconds.ago)
      widget_conversation.update!(status: :resolved)

      create(:message, account: account, inbox: widget_conversation.inbox, conversation: widget_conversation,
                       message_type: :incoming, sender: widget_conversation.contact, content: auto_text)

      expect(widget_conversation.reload).to be_open
    end

    it 'does nothing when turned off' do
      allow(described_class).to receive(:enabled?).and_return(false)
      resolve_after_our_message

      receive_text(auto_text)

      expect(conversation.reload).to be_open
    end
  end

  describe '#apply_chip_verdict!' do
    let(:classifier) { instance_double(Chip::AutoReplyClassifier) }
    let(:message) do
      resolve_after_our_message
      receive_text(auto_text)
    end

    before { allow(Chip::AutoReplyClassifier).to receive(:new).and_return(classifier) }

    it 'silences and remembers the text when Chip sees an automatic reply' do
      allow(classifier).to receive(:perform).and_return({ auto_reply: true, reason: 'aviso de ausência' })

      described_class.new(message: message.reload).apply_chip_verdict!

      conversation.reload
      expect(conversation).to be_resolved
      expect(conversation.custom_attributes['resposta_automatica']).to eq('silenciada')
      expect(conversation.label_list).to include('resposta-automatica')
      expect(AutoReplySignature.lookup(contact, auto_text)).to have_attributes(verdict: 'auto_reply', source: 'ai')
    end

    it 'reopens and remembers the text as human when Chip sees a person' do
      allow(classifier).to receive(:perform).and_return({ auto_reply: false, reason: 'pedido de suporte' })

      described_class.new(message: message.reload).apply_chip_verdict!

      conversation.reload
      expect(conversation).to be_open
      expect(conversation.custom_attributes['resposta_automatica']).to eq('liberada')
      expect(AutoReplySignature.lookup(contact, auto_text)).to have_attributes(verdict: 'human', source: 'ai')
    end

    it 'reopens without remembering anything when Chip is unavailable' do
      allow(classifier).to receive(:perform).and_return({ error: 'Captain is disabled' })

      described_class.new(message: message.reload).apply_chip_verdict!

      expect(conversation.reload).to be_open
      expect(AutoReplySignature.lookup(contact, auto_text)).to be_nil
    end

    it 'marks a held broadcast as answered when Chip sees a person' do
      conversation.update!(custom_attributes: { 'transmissao' => 'aguardando' })
      send_ours(ago: 1.second)
      held = receive_text(auto_text)
      allow(classifier).to receive(:perform).and_return({ auto_reply: false, reason: 'resposta à transmissão' })

      described_class.new(message: held.reload).apply_chip_verdict!

      conversation.reload
      expect(conversation).to be_open
      expect(conversation.custom_attributes['transmissao']).to eq('respondida')
    end
  end

  it 'skips the CSAT survey of a held conversation' do
    conversation.update!(status: :resolved, custom_attributes: { 'resposta_automatica' => 'silenciada' })
    inbox.update!(csat_survey_enabled: true)

    expect(CsatSurveyService.new(conversation: conversation).send(:should_send_csat_survey?)).to be false
  end
end
