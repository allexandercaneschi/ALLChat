import { defineStore } from 'pinia';
import InternalChatAPI from 'dashboard/api/internalChat';

// ALLChat: internal team chat. Channels and messages are kept in sync by the
// `internal_chat.message.created` and `internal_chat.message.updated` websocket events.
export const CHANNEL_KINDS = {
  DIRECT: 'direct',
  TEAM_ROOM: 'team_room',
  COMPANY_ROOM: 'company_room',
};

export const MESSAGE_KINDS = {
  TEXT: 'text',
  HELP_REQUEST: 'help_request',
  NUDGE: 'nudge',
};

// Keep in sync with InternalChat::NUDGE_COOLDOWN on the server.
export const NUDGE_COOLDOWN_SECONDS = 60;

const sortByActivity = (a, b) => b.last_activity_at - a.last_activity_at;

// A message that must call attention: a nudge, a message marked as urgent or a mention of the agent.
export const isAttentionMessage = (message, currentUserId) =>
  message.kind === MESSAGE_KINDS.NUDGE ||
  message.urgent === true ||
  (message.mentioned_user_ids || []).includes(currentUserId);

export const useInternalChatStore = defineStore('internalChat', {
  state: () => ({
    channels: {},
    messages: {},
    hasMoreMessages: {},
    activeChannelId: null,
    // Channel currently on screen in the open panel. Messages that arrive in it are read right away.
    viewingChannelId: null,
    isFetchingChannels: false,
    hasLoadedChannels: false,
    // Timestamp (ms) when the attention nudge can be used again, per channel.
    nudgeAvailableAt: {},
    // Audit mode (administrators and supervisors): read-only conversations of others.
    audit: { channels: [], activeChannel: null, messages: [] },
  }),

  getters: {
    channelList: state => Object.values(state.channels).sort(sortByActivity),
    totalUnread: state =>
      Object.values(state.channels).reduce(
        (total, channel) => total + channel.unread_count,
        0
      ),
    activeChannel: state => state.channels[state.activeChannelId] || null,
    messagesFor: state => channelId => state.messages[channelId] || [],
  },

  actions: {
    upsertChannel(channel) {
      this.channels = { ...this.channels, [channel.id]: channel };
    },

    appendMessage(message) {
      const current = this.messages[message.channel_id] || [];
      if (current.some(item => item.id === message.id)) return;
      this.messages = {
        ...this.messages,
        [message.channel_id]: [...current, message],
      };
    },

    // A message changed (a help request was taken or resolved).
    replaceMessage(message) {
      const current = this.messages[message.channel_id];
      if (!current) return;
      this.messages = {
        ...this.messages,
        [message.channel_id]: current.map(item =>
          item.id === message.id ? message : item
        ),
      };
    },

    async fetchChannels() {
      this.isFetchingChannels = true;
      try {
        const { data } = await InternalChatAPI.getChannels();
        this.channels = Object.fromEntries(
          data.payload.map(channel => [channel.id, channel])
        );
        this.hasLoadedChannels = true;
      } finally {
        this.isFetchingChannels = false;
      }
    },

    async fetchMessages(channelId, beforeId) {
      const params = beforeId ? { before_id: beforeId } : {};
      const { data } = await InternalChatAPI.getMessages(channelId, params);
      const current = beforeId ? this.messages[channelId] || [] : [];
      this.messages = {
        ...this.messages,
        [channelId]: [...data.payload, ...current],
      };
      this.hasMoreMessages = {
        ...this.hasMoreMessages,
        [channelId]: data.meta.has_more,
      };
    },

    async openChannel(params) {
      const { data } = await InternalChatAPI.openChannel(params);
      this.upsertChannel(data);
      await this.setActiveChannel(data.id);
    },

    openDirect(userId) {
      return this.openChannel({ kind: CHANNEL_KINDS.DIRECT, user_id: userId });
    },

    openTeamRoom(teamId) {
      return this.openChannel({
        kind: CHANNEL_KINDS.TEAM_ROOM,
        team_id: teamId,
      });
    },

    async setActiveChannel(channelId) {
      this.activeChannelId = channelId;
      if (channelId === null) return;
      await this.fetchMessages(channelId);
      await this.markRead(channelId);
    },

    async markRead(channelId) {
      const channel = this.channels[channelId];
      if (!channel) return;
      // Zero it first so the badge does not wait for the request.
      this.upsertChannel({ ...channel, unread_count: 0 });
      await InternalChatAPI.markRead(channelId);
    },

    // payload: { content, urgent, mentioned_user_ids }
    async sendMessage(channelId, payload) {
      const { data } = await InternalChatAPI.sendMessage(channelId, payload);
      this.registerMessage(data);
    },

    // The server refuses a second nudge too soon: the button waits for `retry_after` seconds.
    async sendNudge(channelId) {
      try {
        const { data } = await InternalChatAPI.sendMessage(channelId, {
          kind: MESSAGE_KINDS.NUDGE,
        });
        this.registerMessage(data);
        this.setNudgeCooldown(channelId, NUDGE_COOLDOWN_SECONDS);
      } catch (error) {
        const retryAfter = error.response?.data?.retry_after;
        if (retryAfter) this.setNudgeCooldown(channelId, retryAfter);
        throw error;
      }
    },

    setNudgeCooldown(channelId, seconds) {
      this.nudgeAvailableAt = {
        ...this.nudgeAvailableAt,
        [channelId]: Date.now() + seconds * 1000,
      };
    },

    // params: { recipientId } for one person or { teamId } for the whole team, plus content.
    async sendHelpRequest({ recipientId, teamId, content, conversationId }) {
      const { data } = await InternalChatAPI.sendHelpRequest({
        recipient_id: recipientId,
        team_id: teamId,
        content,
        conversation_id: conversationId,
      });
      if (!this.channels[data.channel_id]) await this.fetchChannels();
      this.registerMessage(data);
    },

    // Takes a help request. Opens the direct conversation with who asked.
    async claimHelpRequest(message) {
      const { data } = await InternalChatAPI.claimHelpRequest(
        message.channel_id,
        message.id
      );
      this.replaceMessage(data.message);
      await this.fetchChannels();
      await this.setActiveChannel(data.channel_id);
      return data;
    },

    async resolveHelpRequest(message) {
      const { data } = await InternalChatAPI.resolveHelpRequest(
        message.channel_id,
        message.id
      );
      this.replaceMessage(data);
    },

    // Message created by the current agent: shows in the thread and moves the channel up.
    registerMessage(message) {
      this.appendMessage(message);
      const channel = this.channels[message.channel_id];
      if (!channel) return;
      this.upsertChannel({
        ...channel,
        last_message: message,
        last_activity_at: message.created_at,
      });
    },

    // Message from the websocket. Returns what the screen should do about it:
    // alert (a new message is not on screen) and attention (nudge, urgent or mention).
    async receiveMessage(message, currentUserId) {
      this.appendMessage(message);
      const isOwn = message.sender?.id === currentUserId;
      const attention = !isOwn && isAttentionMessage(message, currentUserId);
      const channel = this.channels[message.channel_id];
      if (!channel) {
        // First message of a conversation somebody just opened with us.
        await this.fetchChannels();
        return { alert: !isOwn, attention };
      }

      const isOnScreen = this.viewingChannelId === message.channel_id;
      this.upsertChannel({
        ...channel,
        last_message: message,
        last_activity_at: message.created_at,
        unread_count:
          isOwn || isOnScreen ? channel.unread_count : channel.unread_count + 1,
      });
      if (isOnScreen && !isOwn) await this.markRead(message.channel_id);
      return { alert: !isOwn && !isOnScreen, attention };
    },

    // Search. Without channelId it searches in all the conversations of the agent.
    async search({ query, channelId, beforeId }) {
      const { data } = await InternalChatAPI.search({
        q: query,
        channel_id: channelId,
        before_id: beforeId,
      });
      return data;
    },

    async fetchAuditChannels() {
      const { data } = await InternalChatAPI.getAuditChannels();
      this.audit = { ...this.audit, channels: data.payload };
    },

    async openAuditChannel(channelId) {
      const { data } = await InternalChatAPI.getAuditMessages(channelId);
      this.audit = {
        ...this.audit,
        activeChannel: data.channel,
        messages: data.payload,
      };
    },

    closeAuditChannel() {
      this.audit = { ...this.audit, activeChannel: null, messages: [] };
    },
  },
});
