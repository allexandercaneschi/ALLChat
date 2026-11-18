# The "resolve without reply" time of a broadcast is now set in minutes. Existing schedules keep their time.
class RenameBroadcastMessagesResolveAfterHoursToMinutes < ActiveRecord::Migration[7.1]
  def up
    rename_column :broadcast_messages, :resolve_after_hours, :resolve_after_minutes
    change_column_default :broadcast_messages, :resolve_after_minutes, from: 24, to: 30
    execute 'UPDATE broadcast_messages SET resolve_after_minutes = resolve_after_minutes * 60'
  end

  def down
    execute 'UPDATE broadcast_messages SET resolve_after_minutes = resolve_after_minutes / 60'
    change_column_default :broadcast_messages, :resolve_after_minutes, from: 30, to: 24
    rename_column :broadcast_messages, :resolve_after_minutes, :resolve_after_hours
  end
end
