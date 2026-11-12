# == Schema Information
#
# Table name: broadcast_messages
#
#  id                  :bigint           not null, primary key
#  active              :boolean          default(TRUE), not null
#  content             :text             not null
#  day                 :integer
#  last_run_on         :date
#  month               :integer
#  name                :string           not null
#  name_fallback       :string           default("cliente"), not null
#  resolve_after_hours :integer          default(24), not null
#  run_at              :datetime
#  schedule_kind       :integer          default("once"), not null
#  send_email          :boolean          default(FALSE), not null
#  send_time           :string           default("09:00"), not null
#  week_of_month       :integer
#  weekday             :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  broadcast_list_id   :bigint           not null
#  created_by_id       :bigint
#  inbox_id            :bigint           not null
#  team_id             :bigint
#
# Indexes
#
#  index_broadcast_messages_on_account_id         (account_id)
#  index_broadcast_messages_on_broadcast_list_id  (broadcast_list_id)
#

# ALLChat: a scheduled broadcast of a list. It can run once on a date, every year
# on a fixed date (e.g. 8 March), every year on a movable date (e.g. 2nd Sunday
# of May) or every day for the contacts having a birthday that day.
class BroadcastMessage < ApplicationRecord
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  SEND_TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  belongs_to :account
  belongs_to :broadcast_list
  belongs_to :inbox
  belongs_to :team, optional: true

  enum schedule_kind: { once: 0, yearly_fixed: 1, yearly_weekday: 2, birthday: 3 }

  validates :name, :content, presence: true
  validates :send_time, format: { with: SEND_TIME_FORMAT }
  validates :resolve_after_hours, numericality: { only_integer: true, greater_than: 0 }
  validates :run_at, presence: true, if: :once?
  validates :month, inclusion: { in: 1..12 }, if: -> { yearly_fixed? || yearly_weekday? }
  validates :day, inclusion: { in: 1..31 }, if: :yearly_fixed?
  validates :weekday, inclusion: { in: 0..6 }, if: :yearly_weekday?
  validates :week_of_month, inclusion: { in: 1..5 }, if: :yearly_weekday?

  scope :active, -> { where(active: true) }

  def self.local_now
    Time.current.in_time_zone(TIME_ZONE)
  end

  # Date of this year's occurrence for the yearly kinds, nil for the others.
  def occurrence_on(year)
    if yearly_fixed?
      Date.new(year, month, day)
    elsif yearly_weekday?
      first = Date.new(year, month, 1)
      first + ((weekday - first.wday) % 7) + (7 * (week_of_month - 1))
    end
  rescue Date::Error
    nil
  end

  def due?(now = self.class.local_now)
    return last_run_on.nil? && run_at <= now if once?
    return false if last_run_on == now.to_date || now.strftime('%H:%M') < send_time

    birthday? || occurrence_on(now.year) == now.to_date
  end

  # Contacts that receive this broadcast today.
  def recipients(today = self.class.local_now.to_date)
    contacts = broadcast_list.contacts
    return contacts unless birthday?

    contacts.where("RIGHT(contacts.custom_attributes->>'#{Broadcasts::Personalization::BIRTHDAY_ATTRIBUTE}', 5) = ?", today.strftime('%m-%d'))
  end

  def delivery_options
    {
      'content' => content, 'inbox_id' => inbox_id, 'team_id' => team_id, 'name_fallback' => name_fallback,
      'send_email' => send_email, 'resolve_after_hours' => resolve_after_hours, 'subject' => name
    }
  end

  def as_json_for_dashboard
    as_json(except: [:created_at, :updated_at, :account_id]).merge(list_name: broadcast_list.name)
  end
end
