/* global axios */
import ApiClient from './ApiClient';

// ALLChat: transfer and participation requests.
class ConversationRequestsAPI extends ApiClient {
  constructor() {
    super('conversation_requests', { accountScoped: true });
  }

  accept(id) {
    return axios.post(`${this.url}/${id}/accept`);
  }

  decline(id) {
    return axios.post(`${this.url}/${id}/decline`);
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }

  getForConversation(conversationId) {
    return axios.get(this.conversationRequestsUrl(conversationId));
  }

  askParticipation(conversationId) {
    return axios.post(this.conversationRequestsUrl(conversationId));
  }

  conversationRequestsUrl(conversationId) {
    return `${this.baseUrl()}/conversations/${conversationId}/requests`;
  }
}

export default new ConversationRequestsAPI();
