# frozen_string_literal: true

module OutOfOffisable
  extend ActiveSupport::Concern

  OFFISABLE_ATTRS = %w[day_of_week closed_all_day open_hour open_minutes close_hour close_minutes open_all_day
                       break_start_hour break_start_minutes break_end_hour break_end_minutes].freeze
  DEFAULT_WORKING_HOURS = [
    { day_of_week: 0, closed_all_day: true, open_all_day: false },
    { day_of_week: 1, open_hour: 9, open_minutes: 0, close_hour: 17, close_minutes: 0, open_all_day: false },
    { day_of_week: 2, open_hour: 9, open_minutes: 0, close_hour: 17, close_minutes: 0, open_all_day: false },
    { day_of_week: 3, open_hour: 9, open_minutes: 0, close_hour: 17, close_minutes: 0, open_all_day: false },
    { day_of_week: 4, open_hour: 9, open_minutes: 0, close_hour: 17, close_minutes: 0, open_all_day: false },
    { day_of_week: 5, open_hour: 9, open_minutes: 0, close_hour: 17, close_minutes: 0, open_all_day: false },
    { day_of_week: 6, closed_all_day: true, open_all_day: false }
  ].map(&:freeze).freeze

  included do
    has_many :working_hours, dependent: :destroy_async
    after_create :create_default_working_hours
  end

  def out_of_office?
    working_hours_enabled? && working_hours.today.closed_now?
  end

  def working_now?
    !out_of_office?
  end

  def weekly_schedule
    working_hours.sort_by(&:day_of_week).map do |wh|
      {
        'day_of_week' => wh.day_of_week,
        'closed_all_day' => wh.closed_all_day,
        'open_hour' => wh.open_hour,
        'open_minutes' => wh.open_minutes,
        'close_hour' => wh.close_hour,
        'close_minutes' => wh.close_minutes,
        'open_all_day' => wh.open_all_day,
        'break_start_hour' => wh.break_start_hour,
        'break_start_minutes' => wh.break_start_minutes,
        'break_end_hour' => wh.break_end_hour,
        'break_end_minutes' => wh.break_end_minutes
      }
    end
  end

  # accepts an array of hashes similiar to the format of weekly_schedule
  #  [
  #    { "day_of_week"=>1,
  #      "closed_all_day"=>false,
  #      "open_hour"=>9,
  #      "open_minutes"=>0,
  #      "close_hour"=>17,
  #      "close_minutes"=>0,
  #      "open_all_day=>false",
  #      "break_start_hour"=>12,    # optional break, all four fields or none
  #      "break_start_minutes"=>0,
  #      "break_end_hour"=>13,
  #      "break_end_minutes"=>0 },...]
  def update_working_hours(params)
    ActiveRecord::Base.transaction do
      params.each do |working_hour|
        working_hours.find_by(day_of_week: working_hour['day_of_week']).update(working_hour.slice(*OFFISABLE_ATTRS))
      end
    end
  end

  private

  def create_default_working_hours
    DEFAULT_WORKING_HOURS.each { |attributes| working_hours.create!(attributes) }
  end
end
