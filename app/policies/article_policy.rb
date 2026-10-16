class ArticlePolicy < ApplicationPolicy
  def index?
    @account.users.include?(@user)
  end

  def update?
    @account_user.administrator_or_supervisor?
  end

  def show?
    @account_user.administrator_or_supervisor?
  end

  def edit?
    @account_user.administrator_or_supervisor?
  end

  def create?
    @account_user.administrator_or_supervisor?
  end

  def destroy?
    @account_user.administrator_or_supervisor?
  end

  def reorder?
    @account_user.administrator_or_supervisor?
  end
end

ArticlePolicy.prepend_mod_with('ArticlePolicy')
