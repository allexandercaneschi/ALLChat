import { defineStore } from 'pinia';
import InternalChatAPI from 'dashboard/api/internalChat';

// ALLChat: internal team chat. Channels and messages are kept in sync by the
// `internal_chat.message.created` websocket event.
export const CHANNEL_KINDS = {
  DIRECT: 'direct',
  TEAM_ROOM: 'team_room',
};

export const MESSAGE_KINDS = {
  TEXT: 'text',
  HELP_REQUEST: 'help_request',
};

const sortByActivity = (a, b) => b.last_activity_at - a.last_activity_at;

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

    async sendMessage(channelId, content) {
      const { data } = await InternalChatAPI.sendMessage(channelId, content);
      this.registerMessage(data);
    },

    async sendHelpRequest({ recipientId, content, conversationId }) {
      const { data } = await InternalChatAPI.sendHelpRequest({
        recipient_id: recipientId,
        content,
        conversation_id: conversationId,
      });
      if (!this.channels[data.channel_id]) await this.fetchChannels();
      this.registerMessage(data);
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

    // Message from the websocket. Returns true when it is worth alerting the agent.
    async receiveMessage(message, currentUserId) {
      this.appendMessage(message);
      const channel = this.channels[message.channel_id];
      if (!channel) {
        // First message of a conversation somebody just opened with us.
        await this.fetchChannels();
        return message.sender?.id !== currentUserId;
      }

      const isOwn = message.sender?.id === currentUserId;
      const isOnScreen = this.viewingChannelId === message.channel_id;
      this.upsertChannel({
        ...channel,
        last_message: message,
        last_activity_at: message.created_at,
        unread_count:
          isOwn || isOnScreen ? channel.unread_count : channel.unread_count + 1,
      });
      if (isOnScreen && !isOwn) await this.markRead(message.channel_id);
      return !isOwn && !isOnScreen;
    },
  },
});
