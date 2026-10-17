# Databases created before the ALLChat fork keep Chatwoot's branding values, because ConfigLoader only adds new keys.
# Replace them with the ALLChat defaults, but only where the value is still Chatwoot's default (Super Admin edits stay).
class ApplyAllchatBrandingDefaults < ActiveRecord::Migration[7.1]
  BRANDING = {
    'INSTALLATION_NAME' => %w[Chatwoot ALLChat],
    'BRAND_NAME' => ['Chatwoot', 'ALL Tecnologias'],
    'BRAND_URL' => %w[https://www.chatwoot.com https://alltecnologias.com.br],
    'WIDGET_BRAND_URL' => %w[https://www.chatwoot.com https://alltecnologias.com.br]
  }.freeze

  def up
    BRANDING.each do |name, (chatwoot_default, allchat_default)|
      config = InstallationConfig.find_by(name: name)
      next unless config&.value == chatwoot_default

      config.value = allchat_default
      config.save!
    end
    GlobalConfig.clear_cache
  end

  def down; end
end
