# == Schema Information
#
# Table name: working_hours
#
#  id                  :bigint           not null, primary key
#  break_end_hour      :integer
#  break_end_minutes   :integer
#  break_start_hour    :integer
#  break_start_minutes :integer
#  close_hour          :integer
#  close_minutes       :integer
#  closed_all_day      :boolean          default(FALSE)
#  day_of_week         :integer          not null
#  open_all_day        :boolean          default(FALSE)
#  open_hour           :integer
#  open_minutes        :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint
#  inbox_id            :bigint
#
# Indexes
#
#  index_working_hours_on_account_id  (account_id)
#  index_working_hours_on_inbox_id    (inbox_id)
#
class WorkingHour < ApplicationRecord
  belongs_to :inbox

  BREAK_ATTRS = %i[break_start_hour break_start_minutes break_end_hour break_end_minutes].freeze

  before_validation :ensure_open_all_day_hours
  before_validation :clear_break_when_closed_all_day
  before_save :assign_account

  validates :open_hour,     presence: true, unless: :closed_all_day?
  validates :open_minutes,  presence: true, unless: :closed_all_day?
  validates :close_hour,    presence: true, unless: :closed_all_day?
  validates :close_minutes, presence: true, unless: :closed_all_day?

  validates :open_hour,     inclusion: 0..23, unless: :closed_all_day?
  validates :close_hour,    inclusion: 0..23, unless: :closed_all_day?
  validates :open_minutes,  inclusion: 0..59, unless: :closed_all_day?
  validates :close_minutes, inclusion: 0..59, unless: :closed_all_day?

  validate :close_after_open, unless: :closed_all_day?
  validate :break_is_complete_and_valid
  validate :open_all_day_and_closed_all_day

  def self.today
    # While getting the day of the week, consider the timezone as well. `first` would
    # return the first working hour from the list of working hours available per week.
    inbox = first.inbox
    find_by(day_of_week: Time.zone.now.in_time_zone(inbox.timezone).to_date.wday)
  end

  def open_at?(time)
    return false if closed_all_day?
    return true if open_all_day?

    return false unless time.between?(inbox_time_at(open_hour, open_minutes), inbox_time_at(close_hour, close_minutes))

    !on_break_at?(time)
  end

  # The break starts at break_start and ends right before break_end,
  # so at exactly break_end the inbox is open again.
  def on_break_at?(time)
    return false unless break?

    time >= inbox_time_at(break_start_hour, break_start_minutes) && time < inbox_time_at(break_end_hour, break_end_minutes)
  end

  def break?
    BREAK_ATTRS.all? { |attr| self[attr].present? }
  end

  def open_now?
    inbox_time = Time.zone.now.in_time_zone(inbox.timezone)
    open_at?(inbox_time)
  end

  def closed_now?
    !open_now?
  end

  private

  def inbox_time_at(hour, minutes)
    Time.zone.now.in_time_zone(inbox.timezone).change({ hour: hour, min: minutes })
  end

  def assign_account
    self.account_id = inbox.account_id
  end

  def close_after_open
    return unless open_hour.hours + open_minutes.minutes >= close_hour.hours + close_minutes.minutes

    errors.add(:close_hour, 'Closing time cannot be before opening time')
  end

  def break_minutes_of_day(hour, minutes)
    (hour * 60) + minutes
  end

  # The break is optional, but its four fields come together: all filled or all empty.
  def break_is_complete_and_valid
    filled = BREAK_ATTRS.count { |attr| self[attr].present? }
    return if filled.zero? || closed_all_day?

    return errors.add(:base, 'Break needs a start and an end time') unless filled == BREAK_ATTRS.size
    return errors.add(:base, 'Break time is out of range') unless break_in_range?

    validate_break_inside_working_period
  end

  def break_in_range?
    [break_start_hour, break_end_hour].all? { |hour| (0..23).cover?(hour) } &&
      [break_start_minutes, break_end_minutes].all? { |minutes| (0..59).cover?(minutes) }
  end

  def validate_break_inside_working_period
    # Missing opening or closing times already have their own validation errors.
    return if [open_hour, open_minutes, close_hour, close_minutes].any?(&:nil?)

    start = break_minutes_of_day(break_start_hour, break_start_minutes)
    finish = break_minutes_of_day(break_end_hour, break_end_minutes)
    return errors.add(:base, 'Break end cannot be before break start') if start >= finish
    return if start > break_minutes_of_day(open_hour, open_minutes) && finish < break_minutes_of_day(close_hour, close_minutes)

    errors.add(:base, 'Break must be inside the working hours')
  end

  def clear_break_when_closed_all_day
    return unless closed_all_day?

    BREAK_ATTRS.each { |attr| self[attr] = nil }
  end

  def ensure_open_all_day_hours
    return unless open_all_day?

    self.open_hour = 0
    self.open_minutes = 0
    self.close_hour = 23
    self.close_minutes = 59
  end

  def open_all_day_and_closed_all_day
    return unless open_all_day? && closed_all_day?

    errors.add(:base, 'open_all_day and closed_all_day cannot be true at the same time')
  end
end
