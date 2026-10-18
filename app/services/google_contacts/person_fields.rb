# ALLChat: reads and fingerprints the fields the Google Contacts sync works with.
module GoogleContacts::PersonFields
  private

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

  def google_updated_at(person)
    time = person.dig('metadata', 'sources').to_a.find { |source| source['type'] == 'CONTACT' }&.dig('updateTime')
    Time.zone.parse(time) if time
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
