require 'rails_helper'

RSpec.describe Evolution::ProfilePictureService do
  let(:contact) { create(:contact, phone_number: '+552798765432') }
  let(:env) { { 'EVOLUTION_API_URL' => 'https://evo.example.com/', 'EVOLUTION_API_KEY' => 'key', 'EVOLUTION_INSTANCE' => 'all' } }

  it 'downloads the current WhatsApp picture' do
    with_modified_env env do
      stub_request(:post, 'https://evo.example.com/chat/fetchProfilePictureUrl/all')
        .with(body: { number: '552798765432' }.to_json, headers: { 'apikey' => 'key' })
        .to_return(status: 200, body: { profilePictureUrl: 'https://pps.whatsapp.net/pic.jpg' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      allow(Avatar::AvatarFromUrlJob).to receive(:perform_now)

      expect(described_class.new(contact: contact).perform).to be(true)
      expect(Avatar::AvatarFromUrlJob).to have_received(:perform_now).with(contact, 'https://pps.whatsapp.net/pic.jpg')
    end
  end

  it 'does nothing when the contact has no visible picture' do
    with_modified_env env do
      stub_request(:post, 'https://evo.example.com/chat/fetchProfilePictureUrl/all')
        .to_return(status: 200, body: { profilePictureUrl: nil }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(described_class.new(contact: contact).perform).to be(false)
    end
  end

  it 'is skipped when Evolution is not configured' do
    expect(described_class.new(contact: contact).perform).to be(false)
  end
end
