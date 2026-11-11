# ALLChat: adds the contacts of a text file to a broadcast list.
#
# One contact per line as "name,phone" (the format saved by the old
# "ALL Mensagens" app); ";" and tab also separate the fields and the phone is
# always the last field. Phones follow GoogleContacts::PhoneNumber, so mobiles
# are stored without the 9th digit like WhatsApp contacts from Evolution.
# Existing contacts are matched by phone; the others are created.
class BroadcastLists::ImportService
  SEPARATOR = /[,;\t]/

  pattr_initialize [:broadcast_list!, :content!]

  def perform
    result = { added: 0, created: 0, already_in_list: 0, invalid_lines: [] }
    content.each_line.with_index(1) do |line, line_number|
      import_line(line.strip, line_number, result)
    end
    result
  end

  private

  def import_line(line, line_number, result)
    return if line.blank?

    name, phone = split(line)
    number = GoogleContacts::PhoneNumber.parse(phone)
    # A first line without digits is a header ("nome,telefone").
    return if number.nil? && line_number == 1 && phone.to_s.match?(/\A\D*\z/)
    return result[:invalid_lines] << line_number if number.nil?

    contact = find_contact(number) || create_contact(name, number, result)
    add_to_list(contact, result)
  end

  def split(line)
    parts = line.split(SEPARATOR)
    return [nil, parts.first] if parts.one?

    [parts[0..-2].join(' ').strip, parts.last.strip]
  end

  def find_contact(number)
    account.contacts.find_by(phone_number: [number.chatwoot_format, number.google_format].uniq)
  end

  def create_contact(name, number, result)
    result[:created] += 1
    account.contacts.create!(name: name.presence || number.chatwoot_format, phone_number: number.chatwoot_format)
  end

  def add_to_list(contact, result)
    return result[:already_in_list] += 1 if contact.label_list.include?(label_title)

    contact.label_list.add(label_title)
    contact.save!
    result[:added] += 1
  end

  def label_title
    @label_title ||= broadcast_list.label.title
  end

  def account
    broadcast_list.account
  end
end
