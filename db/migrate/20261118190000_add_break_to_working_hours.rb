# Each working hour (one row per inbox and weekday) can now have a break, such as a lunch hour.
# The four columns are either all filled or all empty, and the model validates that.
class AddBreakToWorkingHours < ActiveRecord::Migration[7.1]
  def change
    change_table :working_hours, bulk: true do |t|
      t.integer :break_start_hour
      t.integer :break_start_minutes
      t.integer :break_end_hour
      t.integer :break_end_minutes
    end
  end
end
