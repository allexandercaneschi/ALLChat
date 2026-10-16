# ALLChat: two-way sync between Chatwoot contacts and the connected Google account.
#
# - Contacts match by phone (GoogleContacts::PhoneNumber key).
# - Contacts that exist on one side only are created on the other side.
#   New Google contacts get the "Chatwoot" label.
# - For linked contacts, the side that changed since the last sync wins;
#   when both changed, Google wins. Only name and email are synced after the
#   first match, phones are never rewritten.
# - Deletions are not mirrored: a link whose contact disappeared on one side
#   is left alone.
# - In dry run nothing is written; the summary lists what would happen.
class GoogleContacts::SyncService
  SAMPLE_SIZE = 50

  def initialize(connection)
    @connection = connection
    @account = connection.account
    @client = GoogleContacts::Client.new(connection)
    @summary = Hash.new { |hash, key| hash[key] = [] }
    @duplicate_keys = Set.new
  end

  def perform
    plan
    apply unless @connection.dry_run
    finish
  rescue StandardError => e
    @connection.update!(last_error: e.message.truncate(500), last_synced_at: Time.current)
    raise
  end

  private

  def plan
    @google = index_google_people
    @chatwoot = index_chatwoot_contacts
    @links = GoogleContactLink.where(account_id: @account.id).index_by(&:phone_key)
    @actions = { create_google: [], create_chatwoot: [], update_google: [], update_chatwoot: [], link: [] }

    (@google.keys | @chatwoot.keys).each { |key| plan_key(key) }
  end

  def plan_key(key)
    return if @duplicate_keys.include?(key)

    person = @google[key]
    contact = @chatwoot[key]
    link = @links[key]

    return plan_linked(key, person, contact, link) if link
    return @actions[:create_chatwoot] << [key, person] if contact.nil?
    return @actions[:create_google] << [key, contact] if person.nil?

    # First match: Google wins.
    @actions[:update_chatwoot] << [key, person, contact] if fingerprint_google(person) != fingerprint_contact(contact)
    @actions[:link] << [key, person, contact]
  end

  def plan_linked(key, person, contact, link)
    # Deleted on one side since the last sync: deletions are not mirrored.
    return if person.nil? || contact.nil?

    if fingerprint_google(person) != link.google_hash
      @actions[:update_chatwoot] << [key, person, contact]
    elsif fingerprint_contact(contact) != link.chatwoot_hash
      @actions[:update_google] << [key, person, contact]
    end
    @actions[:link] << [key, person, contact]
  end

  def apply
    create_in_chatwoot
    create_in_google
    update_chatwoot
    update_google
    save_links
  end

  def create_in_chatwoot
    @actions[:create_chatwoot].each do |key, person|
      contact = @account.contacts.create!(
        name: person_name(person).presence || GoogleContacts::PhoneNumber.parse(key).chatwoot_format,
        phone_number: phone_for(person).chatwoot_format,
        email: available_email(person_email(person))
      )
      @actions[:link] << [key, person, contact]
    end
  end

  def create_in_google
    return if @actions[:create_google].empty?

    group = @client.contact_group_resource_name
    persons = @actions[:create_google].map { |_key, contact| google_person(contact, group) }
    @client.create_people(persons).each do |person|
      key = phone_for(person)&.key
      contact = @chatwoot[key]
      @actions[:link] << [key, person, contact] if key && contact
    end
  end

  def update_chatwoot
    @actions[:update_chatwoot].each do |_key, person, contact|
      attributes = { name: person_name(person).presence || contact.name }
      email = person_email(person)
      attributes[:email] = available_email(email, contact) if email.present?
      contact.update!(attributes.compact)
    end
  end

  def update_google
    updates = @actions[:update_google].to_h do |_key, person, contact|
      [person['resourceName'], { etag: person['etag'], names: [{ unstructuredName: contact.name }],
                                 emailAddresses: contact.email.present? ? [{ value: contact.email }] : [] }]
    end
    @client.update_people(updates) if updates.any?
  end

  def save_links
    @actions[:link].each do |key, person, contact|
      link = GoogleContactLink.find_or_initialize_by(account_id: @account.id, phone_key: key)
      link.update!(contact_id: contact.id, resource_name: person['resourceName'],
                   google_hash: fingerprint_google(person), chatwoot_hash: fingerprint_contact(contact.reload))
    end
  end

  def finish
    summary = {
      dry_run: @connection.dry_run,
      counts: @actions.except(:link).transform_values(&:size),
      samples: {
        create_google: @actions[:create_google].first(SAMPLE_SIZE).map { |_key, contact| describe_contact(contact) },
        create_chatwoot: @actions[:create_chatwoot].first(SAMPLE_SIZE).map { |_key, person| describe_person(person) },
        update_google: @actions[:update_google].first(SAMPLE_SIZE).map { |_key, _person, contact| describe_contact(contact) },
        update_chatwoot: @actions[:update_chatwoot].first(SAMPLE_SIZE).map { |_key, person, _contact| describe_person(person) }
      },
      duplicates: @summary[:duplicates].first(SAMPLE_SIZE),
      invalid_phones: @summary[:invalid_phones].first(SAMPLE_SIZE)
    }
    @connection.update!(last_sync_summary: summary, last_error: nil, last_synced_at: Time.current)
  end

  def index_google_people
    index(@client.people, :google) { |person| phone_for(person) }
  end

  def index_chatwoot_contacts
    contacts = @account.contacts.where.not(phone_number: [nil, ''])
    index(contacts.find_each, :chatwoot) { |contact| GoogleContacts::PhoneNumber.parse(contact.phone_number) }
  end

  # Records with an unreadable phone or a phone shared by several records are skipped.
  def index(records, side)
    grouped = Hash.new { |hash, key| hash[key] = [] }
    records.each do |record|
      number = yield(record)
      next @summary[:invalid_phones] << { side: side, name: side == :google ? person_name(record) : record.name } if number.nil?

      grouped[number.key] << record
    end
    grouped.each_with_object({}) do |(key, list), result|
      if list.size > 1
        @duplicate_keys << key
        next @summary[:duplicates] << { side: side, phone: key, count: list.size }
      end

      result[key] = list.first
    end
  end

  def google_person(contact, group)
    {
      names: [{ unstructuredName: contact.name }],
      phoneNumbers: [{ value: GoogleContacts::PhoneNumber.parse(contact.phone_number).google_format }],
      emailAddresses: contact.email.present? ? [{ value: contact.email }] : [],
      memberships: [{ contactGroupMembership: { contactGroupResourceName: group } }]
    }
  end

  def phone_for(person)
    person['phoneNumbers'].to_a.lazy.filter_map { |phone| GoogleContacts::PhoneNumber.parse(phone['value']) }.first
  end

  def person_name(person)
    name = person['names'].to_a.first || {}
    (name['unstructuredName'] || name['displayName']).to_s.strip
  end

  def person_email(person)
    person['emailAddresses'].to_a.first&.dig('value').to_s.strip.downcase.presence
  end

  # Chatwoot keeps emails unique per account; skip an email another contact already uses.
  def available_email(email, contact = nil)
    return if email.blank?
    return email if contact&.email.to_s.casecmp?(email)

    @account.contacts.where('LOWER(email) = ?', email).where.not(id: contact&.id).exists? ? nil : email
  end

  def fingerprint_google(person)
    Digest::SHA1.hexdigest([person_name(person), person_email(person).to_s].join("\u0000"))
  end

  def fingerprint_contact(contact)
    Digest::SHA1.hexdigest([contact.name.to_s.strip, contact.email.to_s.strip.downcase].join("\u0000"))
  end

  def describe_contact(contact)
    { name: contact.name, phone: contact.phone_number }
  end

  def describe_person(person)
    { name: person_name(person), phone: person['phoneNumbers'].to_a.first&.dig('value') }
  end
end
