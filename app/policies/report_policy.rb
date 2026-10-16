class ReportPolicy < ApplicationPolicy
  def view?
    @account_user.administrator_or_supervisor?
  end
end

ReportPolicy.prepend_mod_with('ReportPolicy')
