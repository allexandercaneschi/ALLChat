/* global axios */
import ApiClient from './ApiClient';

// ALLChat: internal team chat.
class InternalChatAPI extends ApiClient {
  constructor() {
    super('internal_chat', { accountScoped: true });
  }

  getChannels() {
    return axios.get(`${this.url}/channels`);
  }

  openChannel(params) {
    return axios.post(`${this.url}/channels`, params);
  }

  markRead(channelId) {
    return axios.post(`${this.url}/channels/${channelId}/read`);
  }

  getMessages(channelId, params = {}) {
    return axios.get(`${this.url}/channels/${channelId}/messages`, { params });
  }

  sendMessage(channelId, content) {
    return axios.post(`${this.url}/channels/${channelId}/messages`, {
      content,
    });
  }

  sendHelpRequest(params) {
    return axios.post(`${this.url}/help_requests`, params);
  }
}

export default new InternalChatAPI();
