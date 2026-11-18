import ApiClient from './ApiClient';

// ALLChat: immediate broadcast to every contact of a company.
class CompanyBroadcastsAPI extends ApiClient {
  constructor() {
    super('company_broadcasts', { accountScoped: true });
  }
}

export default new CompanyBroadcastsAPI();
