/* global axios */
import ApiClient from './ApiClient';

// ALLChat: Google Contacts sync settings.
class GoogleContactsAPI extends ApiClient {
  constructor() {
    super('google_contacts', { accountScoped: true });
  }

  update(data) {
    return axios.patch(this.url, data);
  }

  authorize() {
    return axios.post(`${this.url}/authorization`);
  }

  sync() {
    return axios.post(`${this.url}/sync`);
  }

  disconnect() {
    return axios.delete(this.url);
  }
}

export default new GoogleContactsAPI();
