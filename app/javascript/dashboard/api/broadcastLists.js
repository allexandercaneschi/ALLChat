/* global axios */
import ApiClient from './ApiClient';

// ALLChat: broadcast lists and their contacts.
class BroadcastListsAPI extends ApiClient {
  constructor() {
    super('broadcast_lists', { accountScoped: true });
  }

  updateUsers(listId, userIds) {
    return axios.patch(`${this.url}/${listId}/users`, { user_ids: userIds });
  }

  getContacts(listId, { page = 1, q = '' } = {}) {
    return axios.get(`${this.url}/${listId}/contacts`, {
      params: { page, q: q || undefined },
    });
  }

  addContacts(listId, contactIds) {
    return axios.post(`${this.url}/${listId}/contacts`, {
      contact_ids: contactIds,
    });
  }

  removeContact(listId, contactId) {
    return axios.delete(`${this.url}/${listId}/contacts/${contactId}`);
  }

  importContacts(listId, content) {
    return axios.post(`${this.url}/${listId}/contacts/import`, { content });
  }
}

export default new BroadcastListsAPI();
