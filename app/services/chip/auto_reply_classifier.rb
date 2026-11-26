# ALLChat: asks Chip (the company's AI, see Chip::Client) whether a message a contact sent right after
# one of ours was written by a person or by an automatic responder (WhatsApp Business away message,
# a chatbot menu, "esta é uma mensagem automática"). Used by AutoReply::Guard.
#
# The prompt and the model live in the n8n flow "Chip - Resposta automática" (POST
# <CHIP_N8N_URL>/resposta-automatica with texto, ultima_mensagem and segundos; it answers
# { automatica, motivo }). Any failure comes back as { error: ... } and the guard then treats the
# message as written by a person.
class Chip::AutoReplyClassifier
  SERVICE = 'resposta-automatica'.freeze

  pattr_initialize [:account!, :text!, { previous_text: nil, seconds: nil }]

  def perform
    return { error: 'Chip is not configured (CHIP_N8N_URL / CHIP_N8N_TOKEN)' } unless Chip::Client.configured?

    response = Chip::Client.new.post(SERVICE, texto: text, ultima_mensagem: previous_text, segundos: seconds)
    return { error: response[:error] } if response[:error]

    build_result(response)
  end

  private

  def build_result(body)
    return { error: 'Invalid Chip response format' } unless [true, false].include?(body['automatica'])

    { auto_reply: body['automatica'], reason: body['motivo'].to_s.truncate(200) }
  end
end
