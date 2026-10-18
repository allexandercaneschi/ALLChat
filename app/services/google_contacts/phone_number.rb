# ALLChat: Brazilian phone handling for the Google Contacts sync.
#
# WhatsApp via Evolution stores mobile numbers without the 9th digit in Chatwoot,
# while Google keeps them with it. Both map to the same key:
#   key      55 + DDD + last 8 digits
#   chatwoot +55 DDD 8 digits      (never the 9th digit)
#   google   +55 DDD 9 + 8 digits  (mobiles; landlines unchanged)
# Non-Brazilian numbers keep their digits as key and their original format.
# Old Brazilian formats are accepted: trunk prefix 0 ("(032) 99999-8888",
# "0xx32 ..."), carrier code ("0 21 32 ...") and "+55 (032) ...".
# Anything that cannot become a valid E.164 number returns nil.
class GoogleContacts::PhoneNumber
  BRAZIL = '55'.freeze
  MOBILE_FIRST_DIGITS = %w[6 7 8 9].freeze

  attr_reader :key, :chatwoot_format, :google_format

  def self.parse(raw)
    number = new(raw)
    number.key.present? ? number : nil
  end

  def initialize(raw)
    international = raw.to_s.strip.start_with?('+', '00')
    digits = raw.to_s.gsub(/\D/, '').delete_prefix('00')
    digits = international ? strip_brazilian_trunk(digits) : strip_local_prefixes(digits)
    # A local number (DDD + number) without country code is Brazilian.
    digits = "#{BRAZIL}#{digits}" if !international && [10, 11].include?(digits.length)
    brazilian?(digits) ? parse_brazilian(digits) : parse_international(digits)
  end

  private

  # 0 + DDD + number, or 0 + carrier (2 digits) + DDD + number.
  def strip_local_prefixes(digits)
    return digits unless digits.start_with?('0')
    return digits[1..] if [11, 12].include?(digits.length)
    return digits[3..] if [13, 14].include?(digits.length)

    digits
  end

  # "+55 (032) ..." carries the trunk 0 after the country code.
  def strip_brazilian_trunk(digits)
    return digits unless digits.start_with?("#{BRAZIL}0") && [13, 14].include?(digits.length)

    "#{BRAZIL}#{digits[3..]}"
  end

  def brazilian?(digits)
    digits.start_with?(BRAZIL) && [12, 13].include?(digits.length)
  end

  def parse_brazilian(digits)
    ddd = digits[2, 2]
    local = digits[4..]
    # DDDs go from 11 to 99 and never end in 0; numbers never start with 0 or 1.
    return unless ddd.match?(/\A[1-9]{2}\z/)
    return if local.length == 9 && local[0] != '9'
    return if %w[0 1].include?(local[-8])

    last_eight = local[-8..]
    mobile = MOBILE_FIRST_DIGITS.include?(last_eight[0])
    @key = "#{BRAZIL}#{ddd}#{last_eight}"
    @chatwoot_format = "+#{@key}"
    @google_format = mobile ? "+#{BRAZIL}#{ddd}9#{last_eight}" : @chatwoot_format
  end

  def parse_international(digits)
    return if digits.length < 8 || digits.length > 15 || digits.start_with?('0')

    @key = digits
    @chatwoot_format = "+#{digits}"
    @google_format = @chatwoot_format
  end
end
