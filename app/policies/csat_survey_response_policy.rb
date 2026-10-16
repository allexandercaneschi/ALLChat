class CsatSurveyResponsePolicy < ApplicationPolicy
  def index?
    @account_user.administrator_or_supervisor?
  end

  def metrics?
    @account_user.administrator_or_supervisor?
  end

  def download?
    @account_user.administrator_or_supervisor?
  end
end

CsatSurveyResponsePolicy.prepend_mod_with('CsatSurveyResponsePolicy')
