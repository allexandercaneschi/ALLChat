# ALLChat: two-way sync between Chatwoot contacts and the connected Google account.
#
# - Contacts match by phone (GoogleContacts::PhoneNumber key).
# - Contacts that exist on one side only are created on the other side.
#   New Google contacts get the "Chatwoot" label.
# - For linked contacts, the side that changed since the last sync wins.
# - A conflict is a first match whose data differ, or a linked pair where both
#   sides changed. The winner comes from the per-contact choice made on the
#   settings screen, else from the account rule (google, chatwoot or newest).
# - Only name and email are synced after the first match, phones are never
#   rewritten. A blank field never erases the other side's value.
# - Deletions are not mirrored: a link whose contact disappeared on one side
#   is left alone.
# - In dry run nothing is written; the summary lists what would happen,
#   including every conflict so it can be reviewed contact by contact.
#   `apply: true` writes once even when the connection is in dry run.
# - A contact Chatwoot refuses to save (e.g. invalid phone) is skipped and
#   listed under invalid_phones instead of aborting the whole sync.
class GoogleContacts::SyncService
  include GoogleContacts::PersonFields

  SAMPLE_SIZE = 50
  CONFLICT_LIMIT = 500

  def initialize(connection, apply: false)
    @connection = connection
    @account = connection.account
    @client = GoogleContacts::Client.new(connection)
    @write = apply || !connection.dry_run
    @summary = Hash.new { |hash, key| hash[key] = [] }
    @duplicate_keys = Set.new
    @updated_people = {}
  end

  def perform
    plan
    apply if @write
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
    @conflicts = []

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

    plan_conflict(key, person, contact, nil) if fingerprint_google(person) != fingerprint_contact(contact)
    @actions[:link] << [key, person, contact]
  end

  def plan_linked(key, person, contact, link)
    # Deleted on one side since the last sync: deletions are not mirrored.
    return if person.nil? || contact.nil?

    google_changed = fingerprint_google(person) != link.google_hash
    chatwoot_changed = fingerprint_contact(contact) != link.chatwoot_hash

    if google_changed && chatwoot_changed
      plan_conflict(key, person, contact, link)
    elsif google_changed
      @actions[:update_chatwoot] << [key, person, contact]
    elsif chatwoot_changed
      @actions[:update_google] << [key, person, contact]
    end
    @actions[:link] << [key, person, contact]
  end

  def plan_conflict(key, person, contact, link)
    choice = @connection.conflict_overrides[key]
    winner = choice || rule_winner(person, contact, link)
    @actions[winner == 'google' ? :update_chatwoot : :update_google] << [key, person, contact]
    @conflicts << {
      key: key, phone: contact.phone_number, winner: winner, chosen: choice.present?,
      chatwoot: { name: contact.name, email: contact.email.presence },
      google: { name: person_name(person), email: person_email(person) }
    }
  end

  def rule_winner(person, contact, link)
    return @connection.conflict_winner unless @connection.conflict_winner == 'newest'

    google_time = google_updated_at(person)
    chatwoot_time = link ? link.chatwoot_changed_at || link.updated_at : contact.updated_at
    google_time.nil? || google_time >= chatwoot_time ? 'google' : 'chatwoot'
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
    rescue ActiveRecord::RecordInvalid => e
      skip_record(:google, person_name(person), person['phoneNumbers'].to_a.first&.dig('value'), e)
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
    rescue ActiveRecord::RecordInvalid => e
      skip_record(:chatwoot, contact.name, contact.phone_number, e)
      @actions[:link].reject! { |_k, _p, linked| linked == contact }
    end
  end

  def update_google
    updates = @actions[:update_google].to_h do |_key, person, contact|
      email = contact.email.presence || person_email(person)
      [person['resourceName'], { etag: person['etag'], names: [{ unstructuredName: contact.name.presence || person_name(person) }],
                                 emailAddresses: email ? [{ value: email }] : [] }]
    end
    @updated_people = @client.update_people(updates) if updates.any?
  end

  def save_links
    @actions[:link].each do |key, person, contact|
      person = @updated_people[person['resourceName']] || person
      link = GoogleContactLink.find_or_initialize_by(account_id: @account.id, phone_key: key)
      link.update!(contact_id: contact.id, resource_name: person['resourceName'], chatwoot_changed_at: nil,
                   google_hash: fingerprint_google(person), chatwoot_hash: fingerprint_contact(contact.reload))
    end
  end

  def finish
    summary = {
      dry_run: !@write,
      counts: @actions.except(:link).transform_values(&:size),
      samples: samples,
      conflicts: @conflicts.first(CONFLICT_LIMIT),
      conflict_count: @conflicts.size,
      duplicates: @summary[:duplicates].first(SAMPLE_SIZE),
      invalid_phones: @summary[:invalid_phones].first(SAMPLE_SIZE)
    }
    attributes = { last_sync_summary: summary, last_error: nil, last_synced_at: Time.current }
    # Choices are consumed by the run that writes them.
    attributes[:conflict_overrides] = {} if @write
    @connection.update!(attributes)
  end

  def samples
    {
      create_google: @actions[:create_google].first(SAMPLE_SIZE).map { |_key, contact| describe_contact(contact) },
      create_chatwoot: @actions[:create_chatwoot].first(SAMPLE_SIZE).map { |_key, person| describe_person(person) },
      update_google: @actions[:update_google].first(SAMPLE_SIZE).map { |_key, _person, contact| describe_contact(contact) },
      update_chatwoot: @actions[:update_chatwoot].first(SAMPLE_SIZE).map { |_key, person, _contact| describe_person(person) }
    }
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

  def skip_record(side, name, phone, error)
    @summary[:invalid_phones] << { side: side, name: name, phone: phone, error: error.record.errors.full_messages.to_sentence }
  end

  # Chatwoot keeps emails unique per account; skip an email another contact already uses.
  def available_email(email, contact = nil)
    return if email.blank?
    return email if contact&.email.to_s.casecmp?(email)

    @account.contacts.where('LOWER(email) = ?', email).where.not(id: contact&.id).exists? ? nil : email
  end
end
