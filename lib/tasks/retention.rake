# ALLChat: data retention
namespace :retention do
  desc 'Shows, per account, how many internal chat messages and customer conversations are past the retention period (deletes nothing)'
  task report: :environment do
    Account.find_each do |account|
      counts = Retention::PurgeExpiredJob.report(account)
      status = InternalChat.retention_cleanup_enabled?(account) ? 'cleanup ON' : 'cleanup off'
      puts "account #{account.id} (#{status}): #{counts[:internal_chat_messages]} internal messages, #{counts[:conversations]} resolved conversations"
    end
  end
end
