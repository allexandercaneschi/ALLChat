require 'rails_helper'

RSpec.describe Chip::AutoReplyClassifier do
  let(:account) { create(:account) }
  let(:service) do
    described_class.new(account: account, text: 'Olá! Esta é uma mensagem automática.', previous_text: 'Seu atendimento foi finalizado.', seconds: 3)
  end
  let(:chip_url) { 'https://n8n.example.com/webhook/chip/resposta-automatica' }

  context 'when Chip is configured' do
    before do
      create(:installation_config, name: 'CHIP_N8N_URL', value: 'https://n8n.example.com/webhook/chip/')
      create(:installation_config, name: 'CHIP_N8N_TOKEN', value: 'chip-token')
    end

    it 'returns what Chip decided' do
      stub_request(:post, chip_url).to_return(status: 200, body: { automatica: true, motivo: 'aviso de ausência' }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })

      expect(service.perform).to eq({ auto_reply: true, reason: 'aviso de ausência' })
    end

    it 'sends our message, the reply and the delay with the token' do
      stub = stub_request(:post, chip_url)
             .with(headers: { 'X-Chip-Token' => 'chip-token' },
                   body: { texto: 'Olá! Esta é uma mensagem automática.', ultima_mensagem: 'Seu atendimento foi finalizado.', segundos: 3 }.to_json)
             .to_return(status: 200, body: { automatica: false, motivo: 'pessoa' }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.perform[:auto_reply]).to be false
      expect(stub).to have_been_requested
    end

    it 'reports an answer it cannot read as an error' do
      stub_request(:post, chip_url).to_return(status: 200, body: { automatica: 'talvez' }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(service.perform).to have_key(:error)
    end

    it 'reports a failed flow as an error' do
      stub_request(:post, chip_url).to_return(status: 503, body: { erro: 'Gemini e Ollama fora' }.to_json)

      expect(service.perform).to eq({ error: 'Chip answered HTTP 503' })
    end

    it 'reports a timeout as an error' do
      stub_request(:post, chip_url).to_timeout

      expect(service.perform).to have_key(:error)
    end
  end

  it 'reports an error without calling anything when Chip is not configured' do
    expect(service.perform[:error]).to include('not configured')
  end
end
