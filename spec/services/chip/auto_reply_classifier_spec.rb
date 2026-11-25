require 'rails_helper'

RSpec.describe Chip::AutoReplyClassifier do
  let(:account) { create(:account) }
  let(:service) do
    described_class.new(account: account, text: 'Olá! Esta é uma mensagem automática.', previous_text: 'Seu atendimento foi finalizado.', seconds: 3)
  end

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
  end

  it 'returns what Chip decided' do
    allow(service).to receive(:make_api_call).and_return({ message: "```json\n{\"automatica\": true, \"motivo\": \"aviso de ausência\"}\n```" })

    expect(service.perform).to eq({ auto_reply: true, reason: 'aviso de ausência' })
  end

  it 'sends our message, the reply and the delay to the LLM' do
    expect(service).to receive(:make_api_call) do |**args|
      expect(args[:feature]).to eq('editor')
      expect(args[:messages].last[:content]).to include('Seu atendimento foi finalizado.', 'chegou 3 segundos depois', 'mensagem automática')
      { message: '{"automatica": false, "motivo": "pessoa"}' }
    end

    expect(service.perform[:auto_reply]).to be false
  end

  it 'reports an answer it cannot read as an error' do
    allow(service).to receive(:make_api_call).and_return({ message: 'talvez' })

    expect(service.perform).to have_key(:error)
  end

  it 'passes LLM errors on' do
    allow(service).to receive(:make_api_call).and_return({ error: 'API key missing', error_code: 401 })

    expect(service.perform).to eq({ error: 'API key missing' })
  end
end
