# ALLChat: Chip is the company's AI. This service asks her whether a message a contact sent right
# after one of ours was written by a person or by an automatic responder (WhatsApp Business away
# message, a chatbot menu, "esta é uma mensagem automática"). Used by AutoReply::Guard.
#
# Chip runs on the LLM configured for Captain (CAPTAIN_OPEN_AI_API_KEY or the account OpenAI hook)
# and needs the captain_tasks feature on the account. Any error comes back as { error: ... } and
# the guard then treats the message as written by a person.
class Chip::AutoReplyClassifier < Captain::BaseTaskService
  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é a Chip, a IA da ALL Tecnologias, uma empresa de suporte técnico que atende clientes pelo WhatsApp.
    Muitos clientes têm resposta automática no WhatsApp (mensagem de ausência do WhatsApp Business,
    menu de robô, aviso de horário de atendimento, "esta é uma mensagem automática").
    Quando nós enviamos uma mensagem (finalização do atendimento, posição na fila, transmissão),
    essa resposta automática volta e reabre o atendimento sem que uma pessoa tenha escrito nada.

    Você recebe a nossa última mensagem, a resposta do cliente e quantos segundos ela levou para chegar.
    Decida se a resposta foi gerada automaticamente ou escrita por uma pessoa.

    Sinais de resposta automática: texto genérico que não responde ao que dissemos, saudação de empresa,
    horário de funcionamento, "no momento não podemos atender", "retornaremos em breve", menu com opções
    numeradas, aviso de mensagem automática, chegada em poucos segundos.
    Sinais de pessoa: responde ao conteúdo da nossa mensagem, faz pergunta ou pedido de suporte,
    agradece de forma curta ("ok", "obrigado", "valeu"), descreve um problema, cita algo específico.
    Na dúvida, responda que foi uma pessoa: segurar a mensagem de um cliente real é pior que deixar passar.

    Responda apenas com JSON, sem texto fora dele:
    {"automatica": true ou false, "motivo": "uma frase curta em português"}
  PROMPT

  pattr_initialize [:account!, :text!, { previous_text: nil, seconds: nil }]

  def perform
    response = make_api_call(
      feature: 'editor',
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: user_prompt }
      ]
    )
    return { error: response[:error] } if response[:error]

    build_result(response[:message])
  end

  private

  def user_prompt
    <<~PROMPT
      Nossa última mensagem:
      #{previous_text.presence || '(nenhuma)'}

      Resposta do cliente#{seconds ? " (chegou #{seconds} segundos depois)" : ''}:
      #{text}
    PROMPT
  end

  def build_result(content)
    parsed = parse_json(content)
    return { error: 'Invalid LLM response format' } unless parsed.is_a?(Hash) && [true, false].include?(parsed['automatica'])

    { auto_reply: parsed['automatica'], reason: parsed['motivo'].to_s.truncate(200) }
  end

  def parse_json(content)
    raw = content.to_s.strip
    json = raw.match(/```(?:json)?\s*(.*?)\s*```/m)&.captures&.first || raw
    JSON.parse(json)
  rescue JSON::ParserError
    nil
  end

  def event_name
    'chip_auto_reply_classification'
  end

  def use_account_openai_hook?
    true
  end

  # Internal housekeeping: does not consume the account's Captain responses.
  def counts_toward_usage?
    false
  end
end
