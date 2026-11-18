# The "resolve without reply" time of a broadcast is now set in minutes, with 30 as the default.
# Existing schedules move to 30 minutes too.
class RenameBroadcastMessagesResolveAfterHoursToMinutes < ActiveRecord::Migration[7.1]
  def up
    rename_column :broadcast_messages, :resolve_after_hours, :resolve_after_minutes
    change_column_default :broadcast_messages, :resolve_after_minutes, from: 24, to: 30
    execute 'UPDATE broadcast_messages SET resolve_after_minutes = 30'
  end

  def down
    execute 'UPDATE broadcast_messages SET resolve_after_minutes = 24'
    change_column_default :broadcast_messages, :resolve_after_minutes, from: 30, to: 24
    rename_column :broadcast_messages, :resolve_after_minutes, :resolve_after_hours
  end
end
