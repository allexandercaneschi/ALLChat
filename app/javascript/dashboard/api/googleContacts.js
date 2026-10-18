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

  // apply: write this run even when the sync is in simulation mode.
  sync({ apply = false } = {}) {
    return axios.post(`${this.url}/sync`, { apply });
  }

  disconnect() {
    return axios.delete(this.url);
  }
}

export default new GoogleContactsAPI();
