require 'rails_helper'

RSpec.describe AutoReplySignature do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:text) { 'Olá! Recebemos sua mensagem às 08:15 do dia 25/11. Retornaremos em breve: https://exemplo.com/ajuda' }

  describe '.normalize' do
    it 'drops accents, digits, links and punctuation' do
      expect(described_class.normalize(text)).to eq('ola recebemos sua mensagem as do dia retornaremos em breve')
    end
  end

  describe '.fingerprint_for' do
    it 'is the same for the message sent on another day' do
      other_day = 'Olá! Recebemos sua mensagem às 14:02 do dia 26/11. Retornaremos em breve: https://exemplo.com/outra'

      expect(described_class.fingerprint_for(other_day)).to eq(described_class.fingerprint_for(text))
    end

    it 'ignores short texts' do
      expect(described_class.fingerprint_for('Ok, obrigado!')).to be_nil
    end
  end

  describe '.remember!' do
    it 'creates and updates the signature of the contact' do
      described_class.remember!(contact, text, verdict: :auto_reply, source: :rule)
      described_class.remember!(contact, text, verdict: :human, source: :ai)

      signature = described_class.lookup(contact, text)
      expect(signature).to have_attributes(verdict: 'human', source: 'ai', account_id: account.id)
      expect(described_class.where(contact: contact).count).to eq(1)
    end

    it 'keeps the verdict an agent gave' do
      described_class.remember!(contact, text, verdict: :human, source: :agent)
      described_class.remember!(contact, text, verdict: :auto_reply, source: :rule)

      expect(described_class.lookup(contact, text)).to have_attributes(verdict: 'human', source: 'agent')
    end

    it 'is per contact' do
      described_class.remember!(contact, text, verdict: :auto_reply, source: :ai)

      expect(described_class.lookup(create(:contact, account: account), text)).to be_nil
    end
  end
end
