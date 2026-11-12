import ApiClient from './ApiClient';

// ALLChat: scheduled broadcasts (agenda).
class BroadcastMessagesAPI extends ApiClient {
  constructor() {
    super('broadcast_messages', { accountScoped: true });
  }
}

export default new BroadcastMessagesAPI();
