# == Schema Information
#
# Table name: internal_chat_audit_logs
#
#  id         :bigint           not null, primary key
#  action     :string           not null
#  created_at :datetime         not null
#  account_id :bigint           not null
#  auditor_id :bigint           not null
#  channel_id :bigint           not null
#
# Indexes
#
#  index_internal_chat_audit_logs_on_account_id_and_created_at  (account_id,created_at)
#  index_internal_chat_audit_logs_on_channel_id                 (channel_id)
#

# Who read which conversation through the audit endpoints. Written on every audit read.
class InternalChat::AuditLog < ApplicationRecord
  belongs_to :account
  belongs_to :auditor, class_name: 'User'
  belongs_to :channel, class_name: 'InternalChat::Channel'
end
