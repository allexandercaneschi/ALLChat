import { defineStore } from 'pinia';
import ConversationRequestsAPI from 'dashboard/api/conversationRequests';

// ALLChat: transfer and participation requests involving the current agent.
// Kept in sync by the `conversation_request.updated` websocket event.
export const REQUEST_STATUS = {
  PENDING: 'pending',
  ACCEPTED: 'accepted',
};

export const REQUEST_TYPES = {
  TRANSFER: 'transfer',
  PARTICIPATION: 'participation',
};

const isOpen = request =>
  request.status === REQUEST_STATUS.PENDING &&
  request.expires_at * 1000 > Date.now();

export const useConversationRequestsStore = defineStore(
  'conversationRequests',
  {
    state: () => ({
      records: {},
    }),

    getters: {
      incomingOpen: state => userId =>
        Object.values(state.records)
          .filter(request => request.target.id === userId && isOpen(request))
          .sort((a, b) => a.created_at - b.created_at),
      forConversation: state => conversationId =>
        Object.values(state.records).filter(
          request => request.conversation_id === conversationId
        ),
      openOutgoing: state => (conversationId, userId, requestType) =>
        Object.values(state.records).find(
          request =>
            request.conversation_id === conversationId &&
            request.requester.id === userId &&
            request.request_type === requestType &&
            isOpen(request)
        ),
      acceptedParticipation: state => (conversationId, userId, assigneeId) =>
        Object.values(state.records).some(
          request =>
            request.conversation_id === conversationId &&
            request.request_type === REQUEST_TYPES.PARTICIPATION &&
            request.status === REQUEST_STATUS.ACCEPTED &&
            request.requester.id === userId &&
            request.target.id === assigneeId
        ),
    },

    actions: {
      upsert(request) {
        this.records = { ...this.records, [request.id]: request };
      },

      async fetchMine() {
        const { data } = await ConversationRequestsAPI.get();
        data.payload.forEach(request => this.upsert(request));
      },

      async fetchForConversation(conversationId) {
        const { data } =
          await ConversationRequestsAPI.getForConversation(conversationId);
        data.payload.forEach(request => this.upsert(request));
      },

      async askParticipation(conversationId) {
        const { data } =
          await ConversationRequestsAPI.askParticipation(conversationId);
        this.upsert(data);
      },

      async respond(id, action) {
        const { data } = await ConversationRequestsAPI[action](id);
        this.upsert(data);
      },
    },
  }
);
