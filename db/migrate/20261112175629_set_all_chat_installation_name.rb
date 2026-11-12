# The first branding migration did not stick on the production database, which still shows "Chatwoot" in the browser tab.
# Set the final names, but only where the value is still Chatwoot's or the previous ALLChat default (Super Admin edits stay).
class SetAllChatInstallationName < ActiveRecord::Migration[7.1]
  BRANDING = {
    'INSTALLATION_NAME' => [%w[Chatwoot ALLChat], 'ALL Chat'],
    'BRAND_NAME' => [['Chatwoot'], 'ALL Tecnologias'],
    'BRAND_URL' => [['https://www.chatwoot.com'], 'https://alltecnologias.com.br'],
    'WIDGET_BRAND_URL' => [['https://www.chatwoot.com'], 'https://alltecnologias.com.br']
  }.freeze

  def up
    BRANDING.each do |name, (old_values, new_value)|
      config = InstallationConfig.find_by(name: name)
      next unless config && old_values.include?(config.value)

      config.value = new_value
      config.save!
    end
    GlobalConfig.clear_cache
  end

  def down; end
end
