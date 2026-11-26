# ALLChat: Chip is the company's AI and she lives in n8n. Each Chip service is an n8n webhook under
# CHIP_N8N_URL (e.g. https://n8n.example.com/webhook/chip/<service>) protected by the X-Chip-Token
# header (CHIP_N8N_TOKEN). Both are set in Super Admin > Settings > Chip. Which LLM answers (Gemini,
# Ollama...) is decided in the n8n flow, not here.
class Chip::Client
  TOKEN_HEADER = 'X-Chip-Token'.freeze
  # Gemini retries before n8n falls back to Ollama, which runs on CPU: give the flow time.
  TIMEOUT = 90

  class << self
    def configured?
      base_url.present? && token.present?
    end

    def base_url
      config('CHIP_N8N_URL').chomp('/')
    end

    def token
      config('CHIP_N8N_TOKEN')
    end

    private

    def config(name)
      InstallationConfig.find_by(name: name)&.value.to_s.strip
    end
  end

  # The JSON object the service answered with (string keys), or { error: } on any failure.
  def post(service, payload)
    response = HTTParty.post("#{self.class.base_url}/#{service}", body: payload.to_json, headers: headers, timeout: TIMEOUT)
    return { error: "Chip answered HTTP #{response.code}" } unless response.success?

    body = response.parsed_response
    body = JSON.parse(body) if body.is_a?(String)
    body.is_a?(Hash) ? body : { error: 'Invalid Chip response' }
  rescue StandardError => e
    { error: e.message }
  end

  private

  def headers
    { 'Content-Type' => 'application/json', TOKEN_HEADER => self.class.token }
  end
end
