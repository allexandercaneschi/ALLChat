# ALLChat: creates the agent on the first OIDC login (OIDC_AUTO_CREATE_USERS=true).
# The role comes from the provider groups: OIDC_ADMIN_GROUPS and OIDC_SUPERVISOR_GROUPS.
class Oidc::UserProvisioner
  pattr_initialize [:auth_hash!]

  def perform
    account = Account.find(OidcLogin.account_id)
    password = "1!aA#{SecureRandom.alphanumeric(16)}"

    ActiveRecord::Base.transaction do
      user = User.new(email: email, name: name, password: password, password_confirmation: password)
      user.skip_confirmation!
      user.save!
      AccountUser.create!(account: account, user: user, role: administrator? ? :administrator : :agent, supervisor: supervisor?)
      user
    end
  end

  private

  def email
    auth_hash.dig('info', 'email')
  end

  def name
    auth_hash.dig('info', 'name').presence || email.split('@').first
  end

  def groups
    Array(auth_hash.dig('info', 'groups'))
  end

  def administrator?
    groups.intersect?(OidcLogin.admin_groups)
  end

  def supervisor?
    !administrator? && groups.intersect?(OidcLogin.supervisor_groups)
  end
end
