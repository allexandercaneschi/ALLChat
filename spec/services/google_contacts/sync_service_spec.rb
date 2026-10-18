require 'rails_helper'

RSpec.describe GoogleContacts::SyncService do
  let(:account) { create(:account) }
  let(:connection) { GoogleContactsConnection.create!(account: account, refresh_token: 'refresh', dry_run: false) }
  let(:client) { instance_double(GoogleContacts::Client, contact_group_resource_name: 'contactGroups/1') }

  def person(resource_name, name, phone, email: nil, updated_at: nil)
    {
      'resourceName' => resource_name, 'etag' => 'etag',
      'names' => [{ 'unstructuredName' => name }],
      'phoneNumbers' => [{ 'value' => phone }],
      'emailAddresses' => email ? [{ 'value' => email }] : [],
      'metadata' => { 'sources' => updated_at ? [{ 'type' => 'CONTACT', 'updateTime' => updated_at.iso8601 }] : [] }
    }
  end

  before do
    allow(GoogleContacts::Client).to receive(:new).and_return(client)
    allow(client).to receive(:create_people) do |persons|
      persons.each_with_index.map { |p, i| p.deep_stringify_keys.merge('resourceName' => "people/new#{i}") }
    end
    allow(client).to receive(:update_people).and_return({})
  end

  it 'creates missing contacts on both sides, keeping the 9th digit only on Google' do
    create(:contact, account: account, name: 'Maria', phone_number: '+552798765432')
    allow(client).to receive(:people).and_return([person('people/1', 'João', '+55 27 99111-2222')])

    described_class.new(connection).perform

    expect(account.contacts.find_by(phone_number: '+552791112222').name).to eq('João')
    expect(client).to have_received(:create_people).with(
      [hash_including(phoneNumbers: [{ value: '+5527998765432' }],
                      memberships: [{ contactGroupMembership: { contactGroupResourceName: 'contactGroups/1' } }])]
    )
    expect(GoogleContactLink.where(account_id: account.id).count).to eq(2)
  end

  it 'matches contacts by phone and lets Google win on the first match' do
    contact = create(:contact, account: account, name: 'Maria', phone_number: '+552798765432')
    allow(client).to receive(:people).and_return([person('people/1', 'Maria Lara', '+5527998765432')])

    described_class.new(connection).perform

    expect(contact.reload.name).to eq('Maria Lara')
    expect(client).not_to have_received(:create_people)
  end

  it 'sends Chatwoot changes to Google after the contacts are linked' do
    contact = create(:contact, account: account, name: 'Maria', phone_number: '+552798765432')
    allow(client).to receive(:people).and_return([person('people/1', 'Maria', '+5527998765432')])
    described_class.new(connection).perform

    contact.update!(name: 'Maria Lara')
    described_class.new(connection).perform

    expect(client).to have_received(:update_people).with(hash_including('people/1' => hash_including(names: [{ unstructuredName: 'Maria Lara' }])))
  end

  it 'writes nothing in dry run and summarises the plan' do
    connection.update!(dry_run: true)
    create(:contact, account: account, name: 'Maria', phone_number: '+552798765432')
    allow(client).to receive(:people).and_return([person('people/1', 'João', '+5527991112222')])

    described_class.new(connection).perform

    expect(client).not_to have_received(:create_people)
    expect(account.contacts.count).to eq(1)
    expect(connection.reload.last_sync_summary['counts']).to include('create_google' => 1, 'create_chatwoot' => 1)
  end

  it 'skips phones shared by several contacts' do
    create(:contact, account: account, name: 'A', phone_number: '+552798765432')
    allow(client).to receive(:people).and_return([person('people/1', 'B', '+5527998765432'), person('people/2', 'C', '+552798765432')])

    described_class.new(connection).perform

    expect(client).not_to have_received(:create_people)
    expect(connection.reload.last_sync_summary['duplicates'].size).to eq(1)
  end

  describe 'conflicts' do
    let!(:contact) { create(:contact, account: account, name: 'Maria Lara', phone_number: '+552798765432', email: 'maria@lara.com') }

    before { allow(client).to receive(:people).and_return([person('people/1', 'Maria', '+5527998765432')]) }

    it 'lets Chatwoot win on the first match when the rule says so, keeping fields Google already has' do
      connection.update!(conflict_winner: 'chatwoot')

      described_class.new(connection).perform

      expect(contact.reload.name).to eq('Maria Lara')
      expect(client).to have_received(:update_people).with(
        'people/1' => hash_including(names: [{ unstructuredName: 'Maria Lara' }], emailAddresses: [{ value: 'maria@lara.com' }])
      )
    end

    it 'follows the choice made for one contact over the rule and clears it after writing' do
      connection.update!(conflict_winner: 'google', conflict_overrides: { '552798765432' => 'chatwoot' })

      described_class.new(connection).perform

      expect(contact.reload.name).to eq('Maria Lara')
      expect(client).to have_received(:update_people)
      expect(connection.reload.conflict_overrides).to eq({})
    end

    it 'lists the conflicts in dry run with both sides and keeps the choices' do
      connection.update!(dry_run: true, conflict_overrides: { '552798765432' => 'chatwoot' })

      described_class.new(connection).perform

      summary = connection.reload.last_sync_summary
      expect(summary['conflicts']).to contain_exactly(
        hash_including('key' => '552798765432', 'winner' => 'chatwoot', 'chosen' => true,
                       'chatwoot' => { 'name' => 'Maria Lara', 'email' => 'maria@lara.com' },
                       'google' => { 'name' => 'Maria', 'email' => nil })
      )
      expect(summary['counts']).to include('update_google' => 1, 'update_chatwoot' => 0)
      expect(connection.conflict_overrides).to eq('552798765432' => 'chatwoot')
    end

    it 'writes once when asked to apply while in dry run' do
      connection.update!(dry_run: true, conflict_winner: 'chatwoot')

      described_class.new(connection, apply: true).perform

      expect(client).to have_received(:update_people)
      expect(connection.reload.last_sync_summary['dry_run']).to be(false)
      expect(connection.dry_run).to be(true)
    end

    it 'picks the side changed last when both changed and the rule is newest' do
      connection.update!(conflict_winner: 'chatwoot')
      described_class.new(connection).perform

      connection.update!(conflict_winner: 'newest')
      travel_to(1.hour.ago) { contact.update!(name: 'Maria L.') }
      allow(client).to receive(:people).and_return([person('people/1', 'Maria Souza', '+5527998765432', updated_at: Time.current)])
      described_class.new(connection).perform

      expect(contact.reload.name).to eq('Maria Souza')
    end
  end
end
