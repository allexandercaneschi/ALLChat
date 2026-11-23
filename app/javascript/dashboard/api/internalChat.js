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

  // payload: { content, urgent, mentioned_user_ids } or { kind: 'nudge' }
  sendMessage(channelId, payload) {
    return axios.post(`${this.url}/channels/${channelId}/messages`, payload);
  }

  // params: recipient_id (one person) or team_id (the whole team), plus content and conversation_id
  sendHelpRequest(params) {
    return axios.post(`${this.url}/help_requests`, params);
  }

  claimHelpRequest(channelId, messageId) {
    return axios.post(
      `${this.url}/channels/${channelId}/messages/${messageId}/claim`
    );
  }

  resolveHelpRequest(channelId, messageId) {
    return axios.post(
      `${this.url}/channels/${channelId}/messages/${messageId}/resolve`
    );
  }

  // params: q, channel_id (optional, search inside one conversation), before_id
  search(params) {
    return axios.get(`${this.url}/search`, { params });
  }

  // Settings of the rooms (administrators only)
  getRooms() {
    return axios.get(`${this.url}/rooms`);
  }

  updateRoom(roomId, params) {
    return axios.patch(`${this.url}/rooms/${roomId}`, params);
  }

  getAuditChannels() {
    return axios.get(`${this.url}/audit`);
  }

  getAuditMessages(channelId, params = {}) {
    return axios.get(`${this.url}/audit/${channelId}`, { params });
  }
}

export default new InternalChatAPI();
