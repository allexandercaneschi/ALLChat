# ALLChat: companies registered on the contacts (free text "Empresa" field).
# Spelling variants (case, accents, extra spaces) are treated as one company.
class Broadcasts::Companies
  pattr_initialize [:account!]

  def self.key(name)
    I18n.transliterate(name.to_s).squish.downcase
  end

  def summary
    companies = groups.values.map do |rows|
      { name: rows.map { |row| row.last.squish }.tally.max_by(&:last).first, contacts_count: rows.size }
    end
    companies.sort_by { |company| self.class.key(company[:name]) }
  end

  def contacts(name)
    account.contacts.where(id: groups.fetch(self.class.key(name), []).map(&:first))
  end

  private

  def groups
    @groups ||= account.contacts
                       .where("btrim(coalesce(additional_attributes->>'company_name', '')) <> ''")
                       .pluck(:id, Arel.sql("additional_attributes->>'company_name'"))
                       .group_by { |_id, name| self.class.key(name) }
  end
end
