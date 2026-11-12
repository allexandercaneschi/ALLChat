# ALLChat: resolves, without a closing message, the broadcast conversations the
# contact never answered. encerramento_tipo makes the n8n closing flow skip them.
class Broadcasts::AutoResolveJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Conversation.open.where("custom_attributes->>'transmissao' = 'aguardando'")
                .where("(custom_attributes->>'transmissao_resolver_em')::timestamptz <= ?", Time.current).find_each do |conversation|
      attributes = conversation.custom_attributes.merge('transmissao' => 'encerrada', 'encerramento_tipo' => 'sem_mensagem')
      conversation.update!(status: :resolved, custom_attributes: attributes.except('transmissao_resolver_em'))
    end
  end
end
