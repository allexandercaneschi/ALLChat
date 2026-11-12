# ALLChat: fills the {{nome}} variable of a broadcast with the contact's first name.
# Contacts are named "Name - Sector - Customer", so only the first word is used.
# Companies (attribute "empresa") and contacts without a usable name get the fallback.
class Broadcasts::Personalization
  NAME_VARIABLE = '{{nome}}'.freeze
  BIRTHDAY_ATTRIBUTE = 'data_nascimento'.freeze
  COMPANY_ATTRIBUTE = 'empresa'.freeze

  pattr_initialize [:contact!, :fallback!]

  def render(content)
    content.gsub(NAME_VARIABLE, first_name)
  end

  def first_name
    return fallback if company?

    name = contact.name.to_s.split.first.to_s.gsub(/\A[^[:alpha:]]+|[^[:alpha:]]+\z/, '')
    name.presence || fallback
  end

  private

  def company?
    contact.custom_attributes[COMPANY_ATTRIBUTE].to_s == 'true'
  end
end
