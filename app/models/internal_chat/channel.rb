# == Schema Information
#
# Table name: internal_chat_channels
#
#  id         :bigint           not null, primary key
#  direct_key :string
#  kind       :integer          default("direct"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  team_id    :bigint
#
# Indexes
#
#  index_internal_chat_channels_on_account_and_direct_key  (account_id,direct_key) UNIQUE WHERE (direct_key IS NOT NULL)
#  index_internal_chat_channels_on_account_and_team        (account_id,team_id) UNIQUE WHERE (team_id IS NOT NULL)
#

# A direct conversation between two agents, or the room of a team.
# Visibility: a direct channel is visible only to its two participants and a team room only to the
# members of the team. Administrators get no special access.
class InternalChat::Channel < ApplicationRecord
  belongs_to :account
  belongs_to :team, optional: true
  has_many :participants, class_name: 'InternalChat::Participant', dependent: :destroy_async
  has_many :messages, class_name: 'InternalChat::Message', dependent: :destroy_async

  # company_room: the single room of the account, with every user of the account as member.
  enum kind: { direct: 0, team_room: 1, company_room: 2 }
  # Who can send messages in a room. Direct conversations always are everyone.
  enum posting_policy: { everyone: 0, admins_only: 1, admins_and_supervisors: 2 }, _prefix: :posting

  validates :direct_key, presence: true, if: :direct?
  validates :team, presence: true, if: :team_room?
  validates :posting_policy, inclusion: { in: ['everyone'] }, if: :direct?
  validate :team_belongs_to_account

  # Channels the user can see: direct channels they take part in, the rooms of their teams and the company room.
  scope :visible_to, lambda { |user, account|
    where(account: account).where(
      '(internal_chat_channels.kind = :direct AND ' \
      'internal_chat_channels.id IN (SELECT channel_id FROM internal_chat_participants WHERE user_id = :user_id)) OR ' \
      'internal_chat_channels.kind = :company OR ' \
      'internal_chat_channels.team_id IN (SELECT team_id FROM team_members WHERE user_id = :user_id)',
      user_id: user.id, direct: kinds[:direct], company: kinds[:company_room]
    )
  }

  # Conversations an auditor may read (besides their own):
  # - administrators: every channel of the account;
  # - supervisors: the rooms of the teams they belong to and the direct conversations where at least
  #   one of the two people belongs to one of those teams.
  scope :auditable_by, lambda { |user, account_user, account|
    channels = where(account: account)
    next channels if account_user.administrator?
    next none unless account_user.supervisor?

    team_ids = TeamMember.where(user_id: user.id).select(:team_id)
    channels.where(
      'internal_chat_channels.team_id IN (:team_ids) OR (internal_chat_channels.kind = :direct AND internal_chat_channels.id IN (' \
      'SELECT channel_id FROM internal_chat_participants WHERE user_id IN (SELECT user_id FROM team_members WHERE team_id IN (:team_ids))))',
      team_ids: team_ids, direct: kinds[:direct]
    )
  }

  def self.direct_key_for(user_a_id, user_b_id)
    [user_a_id, user_b_id].sort.join(':')
  end

  def self.find_or_create_direct!(account, user_a, user_b)
    key = direct_key_for(user_a.id, user_b.id)
    channel = direct.find_or_create_by!(account: account, direct_key: key)
    [user_a, user_b].each { |user| channel.participants.find_or_create_by!(user: user) }
    channel
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Unread messages per channel id for a user: messages from others after their read pointer.
  def self.unread_counts_for(user, channel_ids)
    InternalChat::Message
      .joins("INNER JOIN internal_chat_participants p ON p.channel_id = internal_chat_messages.channel_id AND p.user_id = #{user.id.to_i}")
      .where(channel_id: channel_ids)
      .where('internal_chat_messages.id > p.last_read_message_id')
      .where.not(sender_id: user.id)
      .group('internal_chat_messages.channel_id').count
  end

  def self.find_or_create_for_team!(account, team)
    team_room.find_or_create_by!(account: account, team: team)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.find_or_create_company_room!(account)
    company_room.find_or_create_by!(account: account)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def direct_user_ids
    direct_key.to_s.split(':').map(&:to_i)
  end

  # Users who receive the messages of this channel.
  def members
    return User.where(id: direct_user_ids) if direct?
    return User.where(id: AccountUser.where(account_id: account_id).select(:user_id)) if company_room?

    User.where(id: TeamMember.where(team_id: team_id).select(:user_id))
  end

  def member?(user)
    return direct_user_ids.include?(user.id) if direct?
    return AccountUser.exists?(account_id: account_id, user_id: user.id) if company_room?

    TeamMember.exists?(team_id: team_id, user_id: user.id)
  end

  # Whether a member can send messages here, by the posting policy of the room.
  def can_post?(account_user)
    return true if direct? || posting_everyone?
    return account_user.administrator? if posting_admins_only?

    account_user.administrator_or_supervisor?
  end

  # Team rooms have no fixed list of participants: read pointers are created when needed, starting
  # at the current end of the conversation so the existing history does not show up as unread.
  def ensure_participants!(users = members)
    existing = participants.where(user: users).pluck(:user_id)
    last_id = messages.maximum(:id) || 0
    (users.pluck(:id) - existing).each do |user_id|
      participants.create!(user_id: user_id, last_read_message_id: last_id)
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end

  # Channel as the given user sees it: the other person of a direct channel, the team or the company.
  def push_event_data_for(user, unread_count:, last_message:, can_post:)
    other = direct? ? User.find_by(id: direct_user_ids - [user.id]) : nil
    {
      id: id,
      kind: kind,
      team: team_room? ? { id: team.id, name: team.name } : nil,
      name: company_room? ? account.name : nil,
      posting_policy: posting_policy,
      can_post: can_post,
      user: other&.push_event_data,
      unread_count: unread_count,
      last_message: last_message&.push_event_data,
      last_activity_at: (last_message&.created_at || created_at).to_i
    }
  end

  private

  def team_belongs_to_account
    errors.add(:team, 'must belong to the account') if team && team.account_id != account_id
  end
end
