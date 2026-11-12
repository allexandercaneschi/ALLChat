# == Schema Information
#
# Table name: broadcast_lists
#
#  id          :bigint           not null, primary key
#  description :text
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  label_id    :bigint           not null
#
# Indexes
#
#  index_broadcast_lists_on_account_id_and_name  (account_id,name) UNIQUE
#  index_broadcast_lists_on_label_id             (label_id) UNIQUE
#

# ALLChat: a broadcast list. Its members are the contacts tagged with the list's
# label (lista-<name>), so a contact shows which lists it belongs to and tagging
# a contact anywhere in the dashboard also adds it to the list.
# Administrators see and manage every list; other users only the lists they
# were authorized on.
class BroadcastList < ApplicationRecord
  LABEL_PREFIX = 'lista-'.freeze
  LABEL_COLOR = '#35A8E0'.freeze

  belongs_to :account
  belongs_to :label
  has_many :broadcast_list_users, dependent: :delete_all
  has_many :users, through: :broadcast_list_users
  has_many :broadcast_messages, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :label_id, uniqueness: true

  before_validation :sync_label

  scope :visible_to, lambda { |account_user|
    next all if account_user.administrator?

    where(id: BroadcastListUser.where(user_id: account_user.user_id).select(:broadcast_list_id))
  }

  def self.label_title_for(name)
    "#{LABEL_PREFIX}#{name.to_s.parameterize}"
  end

  def contacts
    account.contacts.tagged_with(label.title, on: :labels)
  end

  def authorized?(account_user)
    account_user.administrator? || broadcast_list_users.exists?(user_id: account_user.user_id)
  end

  def as_json_for(account_user)
    {
      id: id,
      name: name,
      description: description,
      label: label.title,
      contacts_count: contacts.count,
      user_ids: account_user.administrator? ? user_ids : [],
      can_manage: account_user.administrator?,
      created_at: created_at.to_i
    }
  end

  private

  # Creating or renaming a list creates or renames its label; Label renames
  # retag contacts and conversations through Labels::UpdateJob.
  def sync_label
    return if name.blank? || account.blank?

    title = self.class.label_title_for(name)
    if label.nil?
      self.label = account.labels.create_with(color: LABEL_COLOR, description: name).find_or_create_by!(title: title)
    elsif label.title != title
      label.update!(title: title, description: name)
    end
  end
end
