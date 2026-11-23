# Chat interno da equipe (ALLChat)

Chat interno nativo do ALLChat: conversa direta (1:1) entre dois agentes da mesma conta e sala por time,
em tempo real, com contador de não lidas, push e a estrutura de "pedir ajuda". Tudo vive em arquivos
novos sob o namespace `InternalChat` para facilitar as atualizações do upstream (Chatwoot).

Base do trabalho: branch `allchat` (inclui `feat/intervalo-expediente`, já mergeada via PR #11).

## Mapa do código existente (Etapa 1)

### Usuários, times, conta, papéis e presença

| Arquivo | O que é |
| --- | --- |
| `app/models/user.rb` | Usuário (`pubsub_token`, `push_event_data`, `teams` via `team_members`). |
| `app/models/account.rb` | Conta; `settings` (jsonb) guarda configurações por conta. |
| `app/models/account_user.rb` | Vínculo usuário-conta: `role` (`agent: 0`, `administrator: 1`), `availability` (online/offline/busy) e, no ALLChat, a flag `supervisor` (agente com permissões extras; `administrator_or_supervisor?`). |
| `app/models/team.rb`, `app/models/team_member.rb` | Times e membros. |
| `lib/online_status_tracker.rb` | Presença: sorted set no Redis por conta (`update_presence`, janela `PRESENCE_DURATION`, 20 s) e hash com o status escolhido (`set_status`). `get_available_users` devolve os agentes online. |
| `app/channels/room_channel.rb` | A cada 20 s o front chama `update_presence`; o canal atualiza a presença e faz broadcast de `presence.update`. |

### Tempo real

| Arquivo | O que é |
| --- | --- |
| `app/channels/room_channel.rb` | Cada conexão assina o stream do `pubsub_token` do usuário e o stream `account_<id>` (esse é de toda a conta: **não usar para chat privado**). |
| `app/listeners/action_cable_listener.rb` | Transmite eventos do domínio para uma lista de `pubsub_token`s. |
| `app/jobs/action_cable_broadcast_job.rb` | Faz o `ActionCable.server.broadcast` para cada token. O chat interno usa esse job direto (como `ConversationRequest`), só com os tokens dos membros do canal. |
| `app/javascript/shared/helpers/BaseActionCableConnector.js` | Cria o consumer, assina `RoomChannel` e despacha `received` para o mapa `events`. |
| `app/javascript/dashboard/helper/actionCable.js` | Mapa `events` do dashboard (um handler por evento). O evento do chat interno entra aqui. |

### Push

| Arquivo | O que é |
| --- | --- |
| `app/services/notification/push_notification_service.rb` | Entrega browser push (WebPush/VAPID) e push de celular (FCM direto ou relay do Chatwoot Hub). Remove assinaturas expiradas. Na `allchat` já segura o push de celular fora do expediente da caixa (`mobile_push_allowed?`). |
| `app/models/notification.rb` | `NOTIFICATION_TYPES` (enum). Cada tipo vira uma flag `push_<tipo>` / `email_<tipo>` em `NotificationSetting`. **É aqui que um novo tipo é registrado.** |
| `app/models/notification_setting.rb` | Preferências por usuário e conta (flags em bitmask, `flag_shih_tzu`). |
| `app/controllers/api/v1/accounts/notification_settings_controller.rb` | API das preferências. |
| `app/javascript/dashboard/routes/dashboard/settings/profile/constants.js` + `NotificationPreferences.vue` | Lista de tipos na tela de preferências do perfil. |
| `app/services/notification/fcm_service.rb`, `NotificationSubscription` | Cliente FCM e dispositivos inscritos (`browser_push`, `fcm`). |

Observação: o serviço de push depende de `notification.conversation` (título, link, horário da caixa).
Por isso o chat interno herda dele (`InternalChat::PushNotificationService`) em vez de criar `Notification`
com ator conversa.

Observação sobre "urgência": o briefing dizia que não há gancho de notificação urgente, mas a `allchat`
tem um stub `urgent_notification?` (sempre `false`) no serviço de push de conversas. O chat interno não o
usa; o ponto de extensão do chat interno é `InternalChat::PushNotificationService#mobile_push_allowed?`.

### Tela de conversas e coluna lateral direita

| Arquivo | O que é |
| --- | --- |
| `app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue` | Layout: `ChatList` + `ConversationBox` + coluna direita (`ConversationSidebar`). |
| `app/javascript/dashboard/routes/dashboard/inbox/InboxView.vue` | Mesmo layout na visão Inbox. |
| `app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue` | Coluna direita (320/360 px; fixa e sobreposta em telas pequenas). Mostra o `ContactPanel.vue`. |
| `app/javascript/dashboard/components-next/Conversation/SidepanelSwitch.vue` | Botões flutuantes que alternam as colunas (`is_contact_sidebar_open`, `is_copilot_panel_open` em `ui_settings`). |
| `app/javascript/dashboard/composables/useUISettings.js` | Lê e grava `ui_settings` do usuário (persiste no servidor). |

A alternância já funciona assim: cada coluna tem uma flag em `ui_settings` e abrir uma zera as outras. O chat
interno segue o mesmo padrão com `is_internal_chat_open`.

### Expediente (`feat/intervalo-expediente`)

Já mergeada na `allchat`. Faz o horário de atendimento da **caixa de entrada** ter intervalo (almoço):
`app/models/working_hour.rb` (`break_*`, `on_break_at?`, `open_at?`), `app/models/concerns/out_of_offisable.rb`
(`out_of_office?`, `working_now?`), SLA (`business_hours_service`), widget (`availabilityHelpers.js`),
tela da caixa (`BusinessDay.vue`) e o push de celular só dentro do expediente (`mobile_push_allowed?` em
`push_notification_service.rb`).
Como reaproveitar: o expediente é **por caixa**, não por conta nem por agente. Para decidir urgência fora do
expediente no chat interno é preciso definir qual caixa vale (por exemplo, qualquer caixa do agente aberta
agora) e consultar `inbox.out_of_office?`. A decisão fica em `InternalChat::PushNotificationService#mobile_push_allowed?`.

### Convenções do projeto

- Rotas da API: `config/routes.rb`, dentro de `resources :accounts` → `scope module: :accounts`.
  Controllers em `app/controllers/api/v1/accounts/` herdando de `Api::V1::Accounts::BaseController`.
- Políticas (Pundit): `app/policies/`, `ApplicationPolicy` recebe `{ user:, account:, account_user: }`.
  `Pundit::NotAuthorizedError` vira 401 em `Api::BaseController`.
- Migrations: `bundle exec rails g migration`; `db/schema.rb` é versionado.
- Specs Ruby: `spec/models`, `spec/policies`, `spec/services`, `spec/jobs`, `spec/controllers/api/v1/accounts/*_spec.rb`
  (request specs). Specs front (Vitest): `*.spec.js` ao lado do código (`specs/`) com `pnpm test`.
- i18n: backend `config/locales/en.yml` e `pt_BR.yml`; front `app/javascript/dashboard/i18n/locale/<idioma>/*.json`
  registrados em `index.js` do idioma.

## O que foi implementado

- **Modelo** (`app/models/internal_chat/`): `Channel` (direto ou sala de time), `Participant` (ponteiro de leitura
  por usuário), `Message` (texto, pedido de ajuda ou "chamar atenção") e `AuditLog`. Tabelas `internal_chat_*`, sem
  chave estrangeira no banco. Uma conversa contínua por pessoa ou time (como Spark e WhatsApp); só o pedido de ajuda
  tem estado (aberto, assumido, resolvido).
- **Sala da empresa** (`kind: company_room`): uma por conta, com todos os usuários da conta (agentes, supervisores
  e administradores) como membros. Criada na primeira listagem. Não aceita pedido de ajuda, urgente nem chamar atenção.
  Push: só para quem foi mencionado; se a sala for restrita (aviso), todos são notificados.
- **Configuração das salas** (Configurações > Conta > Salas do chat, só administrador): para a sala da empresa e a
  sala de cada time, define **quem pode enviar**: todos, só administradores, ou administradores e supervisores.
  Todos os membros continuam podendo ler. A regra vale para mensagens e pedidos de ajuda. A API é
  `GET /internal_chat/rooms` e `PATCH /internal_chat/rooms/:id` (`posting_policy`).
- **Visibilidade** (`app/policies/internal_chat/`): conversa direta só para os dois participantes; sala de time só
  para membros do time. A leitura de conversas de outros só existe pela auditoria (abaixo).
- **API** (`/api/v1/accounts/:id/internal_chat/...`): `channels` (GET/POST), `channels/:id/read`,
  `channels/:id/messages` (GET/POST, com `urgent`, `mentioned_user_ids` e `kind: nudge`),
  `channels/:id/messages/:id/claim` e `/resolve`, `help_requests` (POST, `recipient_id` **ou** `team_id`),
  `search` (`q`, `channel_id` opcional) e `audit` (GET lista, GET `audit/:id`).
- **Tempo real**: eventos `internal_chat.message.created` e `internal_chat.message.updated`, enviados só aos
  `pubsub_token`s dos membros do canal.
- **Push**: `InternalChat::PushNotificationService` herda de `Notification::PushNotificationService`. A preferência
  `push_internal_message` **nasce ligada** para todos (migração de dados para quem já existe e padrão para novos).
- **Fora do expediente** (`InternalChat::Availability`): o agente está fora do expediente quando todas as caixas de
  que é membro e que têm horário configurado estão fechadas ou em intervalo. Nesse caso o push só chega para:
  `@menção` (sala de time ou conversa direta), mensagem marcada como **urgente** numa conversa direta e o botão
  **chamar atenção**. Push urgente sai com prioridade alta e `channel_id: urgent` (Android) e
  `interruption-level: time-sensitive` (iOS); o app móvel precisa criar o canal `urgent` e o som correspondente.
- **Chamar atenção** (estilo MSN): só em conversa direta, com intervalo de 60 s por pessoa e conversa
  (`InternalChat::NUDGE_COOLDOWN`); antes disso a API responde 429 com `retry_after`. No computador: som, título da
  aba piscando e notificação do navegador que não some sozinha (`attention.js`).
- **Pedir ajuda**: para uma pessoa (conversa direta) ou para o time todo (sala do time). Quem sabe ajudar clica em
  **Assumir** (o primeiro vence): abre a conversa direta com quem pediu e entra como participante na conversa do
  cliente, se houver uma ligada ao pedido e a pessoa tiver acesso à caixa. A troca de responsável pela conversa do
  cliente continua pelo fluxo de transferência já existente. Quem pediu ou quem assumiu marca como resolvido.
- **Busca**: dentro da conversa (ícone de lupa no topo) e em todas as conversas do agente (campo na lista).
  Usa `ILIKE` com índice `pg_trgm` e só alcança conversas de que o agente participa.
- **Auditoria**: administradores veem todas as conversas da conta; cada supervisor vê as salas dos times de que é
  membro e as conversas diretas em que ao menos uma das duas pessoas é de um time dele. Cada leitura de conversa é
  gravada em `internal_chat_audit_logs` (quem, qual conversa, quando). Na tela: ícone de escudo no topo da coluna,
  só para administrador e supervisor.
- **Retenção**: padrão de **365 dias** para o chat interno (`internal_chat_retention_days`) e para conversas
  resolvidas de clientes (`conversation_retention_days`), editáveis em Configurações > Conta > Retenção de dados.
  A limpeza (`Retention::PurgeExpiredJob`, diária às 03:00 UTC) **só roda nas contas em que
  `retention_cleanup_enabled` está ligado (desligado por padrão)** e só remove conversas de clientes **resolvidas**.
  `bundle exec rails retention:report` mostra, por conta, o que seria removido, sem apagar nada.
- **Front**: coluna lateral direita (`components-next/InternalChat/`) que alterna com contato e copilot, atalho
  `Alt+I`, lançador flutuante quando não há conversa aberta, alertas in-app, store Pinia (`stores/internalChat.js`).

## O que falta

- Anexos e arquivos, supervisor/transmissões e o app móvel (fora do escopo). O app móvel precisa do canal de
  notificação `urgent` e de tratar o campo `urgent` do payload FCM.
- Aviso de privacidade aos agentes de que as conversas podem ser auditadas (recomendado; hoje a tela de auditoria
  só avisa quem audita).
- Tela para consultar o log de auditoria (a tabela e a gravação existem).
- Busca geral do Chatwoot (`/search`) ainda não inclui o chat interno; a busca está na própria coluna.
- E-mail para mensagens internas (a linha de preferências mostra a coluna de e-mail, mas ela não faz nada).
- Limpeza dos dados quando uma conta ou um usuário é apagado.
- Presença (bolinha online) e "digitando" na coluna.
- Expediente por agente (hoje é derivado das caixas) e janela do `chamar atenção` configurável.

## Decisões já tomadas pelo dono

1. Retenção de 365 dias (chat interno e clientes), editável nas configurações.
2. Auditoria total para administradores e por time para cada supervisor.
3. Push ligado por padrão.
4. Fora do expediente só chega `@menção`, urgente em conversa privada e "chamar atenção" (com intervalo).
5. O pedido de ajuda pode ir ao time todo; quem souber assume. Assumir não troca o responsável do cliente.
6. Histórico completo em salas de time e conversas diretas, com busca.
7. Uma sala para toda a empresa e uma configuração das salas com a regra de quem pode enviar (todos, só
   administradores, ou administradores e supervisores).

## Pontos para o dono confirmar

- **Sala da empresa e push:** com a sala aberta para todos enviarem, só quem foi mencionado recebe push (senão uma
  mensagem acordaria a empresa toda). Se a sala for restrita a administradores (ou a supervisores), vira aviso e
  todos recebem. Não existe ainda "silenciar sala" por pessoa.
- **Sala restrita bloqueia também o pedido de ajuda** daquela sala (é uma mensagem na sala). Se quiser deixar o
  pedido de ajuda livre nas salas de time mesmo quando restritas, é uma exceção pequena.
- **Mais opções por sala** (renomear, arquivar, criar outras salas, escolher membros) não existem; hoje a
  configuração é só a regra de envio.

- **Apagar clientes:** a limpeza de conversas de clientes está pronta, mas desligada. Rode `retention:report` antes
  de ligar em uma conta e avalie o impacto em relatórios (conversas apagadas somem de contagens históricas).
- **Auditoria e privacidade (LGPD):** recomenda-se avisar os agentes por escrito de que as conversas internas
  podem ser auditadas, e definir quem acessa o log de auditoria.
- **Intervalo do "chamar atenção":** 60 segundos por pessoa e conversa. Ajustável em `InternalChat::NUDGE_COOLDOWN`
  e `NUDGE_COOLDOWN_SECONDS` (front).
- **Entrada no time:** quem entra depois no time vê o histórico anterior da sala (só não conta como não lido).
- **Quem assume:** qualquer membro da sala, menos quem pediu.
