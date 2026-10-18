# ALLChat: minimal Google People API client for the contacts sync.
class GoogleContacts::Client
  API = 'https://people.googleapis.com/v1'.freeze
  PERSON_FIELDS = 'names,phoneNumbers,emailAddresses,memberships,metadata'.freeze
  UPDATE_FIELDS = 'names,emailAddresses'.freeze
  BATCH_SIZE = 200
  GROUP_NAME = 'Chatwoot'.freeze

  def initialize(connection)
    @connection = connection
  end

  def people
    results = []
    page_token = nil
    loop do
      params = { personFields: PERSON_FIELDS, pageSize: 1000, pageToken: page_token }.compact
      body = token.get("#{API}/people/me/connections", params: params).parsed
      results.concat(body['connections'] || [])
      page_token = body['nextPageToken']
      break if page_token.blank?
    end
    results
  end

  def create_people(persons)
    persons.each_slice(BATCH_SIZE).flat_map do |batch|
      body = { contacts: batch.map { |person| { contactPerson: person } }, readMask: PERSON_FIELDS }
      post('people:batchCreateContacts', body)['createdPeople'].to_a.pluck('person')
    end
  end

  # Returns the updated people by resource name.
  def update_people(persons_by_resource_name)
    persons_by_resource_name.each_slice(BATCH_SIZE).each_with_object({}) do |batch, updated|
      body = post('people:batchUpdateContacts', { contacts: batch.to_h, updateMask: UPDATE_FIELDS, readMask: PERSON_FIELDS })
      body['updateResult'].to_h.each { |resource_name, result| updated[resource_name] = result['person'] }
    end
  end

  def contact_group_resource_name
    return @connection.contact_group_resource_name if @connection.contact_group_resource_name.present?

    groups = token.get("#{API}/contactGroups", params: { pageSize: 1000 }).parsed['contactGroups'].to_a
    group = groups.find { |g| g['name'] == GROUP_NAME } || post('contactGroups', { contactGroup: { name: GROUP_NAME } })
    @connection.update!(contact_group_resource_name: group['resourceName'])
    group['resourceName']
  end

  private

  def post(path, body)
    token.post("#{API}/#{path}", body: body.to_json, headers: { 'Content-Type' => 'application/json' }).parsed
  end

  def token
    @token ||= begin
      access = OAuth2::AccessToken.new(
        GoogleContacts::Oauth.client, @connection.access_token,
        refresh_token: @connection.refresh_token, expires_at: @connection.expires_at&.to_i
      )
      access.expired? ? refresh(access) : access
    end
  end

  def refresh(access)
    fresh = access.refresh!
    @connection.update!(access_token: fresh.token, expires_at: Time.zone.at(fresh.expires_at))
    fresh
  end
end
