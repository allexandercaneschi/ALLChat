# ALLChat: fills the variables of a broadcast: {{nome}} with the contact's first name and
# {{empresa}} with the company registered on the contact ("Empresa" field).
# Contacts are named "Name - Sector - Customer", so only the first word is used.
# Companies (attribute "empresa") and contacts without a usable name get the fallback.
class Broadcasts::Personalization
  NAME_VARIABLE = '{{nome}}'.freeze
  BIRTHDAY_ATTRIBUTE = 'data_nascimento'.freeze
  COMPANY_ATTRIBUTE = 'empresa'.freeze
  COMPANY_VARIABLE = '{{empresa}}'.freeze
  COMPANY_FALLBACK = 'sua empresa'.freeze

  pattr_initialize [:contact!, :fallback!]

  def render(content)
    content.gsub(NAME_VARIABLE, first_name).gsub(COMPANY_VARIABLE, company_name)
  end

  def first_name
    return fallback if company?

    name = contact.name.to_s.split.first.to_s.gsub(/\A[^[:alpha:]]+|[^[:alpha:]]+\z/, '')
    name.presence || fallback
  end

  def company_name
    contact.additional_attributes['company_name'].to_s.squish.presence || COMPANY_FALLBACK
  end

  private

  def company?
    contact.custom_attributes[COMPANY_ATTRIBUTE].to_s == 'true'
  end
end
