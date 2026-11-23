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
  por usuário), `Message` (texto ou pedido de ajuda). Tabelas `internal_chat_*`, sem chave estrangeira no banco.
- **Visibilidade** (`app/policies/internal_chat/`): conversa direta só para os dois participantes; sala de time só
  para membros do time; **administradores não leem conversas diretas nem salas de times de que não são membros**.
- **API** (`/api/v1/accounts/:id/internal_chat/...`):
  `GET channels`, `POST channels` (`kind: direct, user_id` ou `kind: team_room, team_id`),
  `POST channels/:id/read`, `GET|POST channels/:id/messages`, `POST help_requests`.
- **Tempo real**: evento `internal_chat.message.created`, enviado só aos `pubsub_token`s dos membros do canal.
- **Não lidas**: contador por canal (ponteiro de leitura) e total no botão da coluna.
- **Front**: coluna lateral direita (`components-next/InternalChat/`) que alterna com contato e copilot, atalho
  `Alt+I`, lançador flutuante quando não há conversa aberta, alerta in-app e store Pinia (`stores/internalChat.js`).
- **Push**: `InternalChat::PushNotificationService` herda de `Notification::PushNotificationService`
  (browser push, FCM, relay e limpeza de assinaturas reaproveitados) e respeita a preferência `push_internal_message`
  (nova linha na tela de preferências do perfil).
- **Pedir ajuda**: `POST help_requests` com `recipient_id` único. Cria a mensagem do tipo `help_request` no canal
  direto entre os dois. Não existe parâmetro para time ou lista de pessoas; o modelo recusa pedido de ajuda fora de
  canal direto. Na tela há um botão "Pedir ajuda" no canal direto.
- **Retenção**: configuração por conta `internal_chat_retention_days` (padrão 90). `InternalChat::Message.past_retention`
  só define o que um futuro job removeria. Nada é apagado.

## O que falta

- Anexos e arquivos, busca, supervisor/transmissões, app móvel (fora do escopo deste corte).
- Job de limpeza pela retenção (hoje só existe o escopo `past_retention`).
- Urgência fora do expediente (ponto de extensão: `InternalChat::PushNotificationService#mobile_push_allowed?`).
- E-mail para mensagens internas (a linha de preferências mostra a coluna de e-mail, mas ela não faz nada).
- Limpeza dos dados quando uma conta ou um usuário é apagado (hoje a mensagem fica órfã de remetente e o
  `push_event_data` já tolera isso, mas não há remoção).
- Presença (bolinha online) e "digitando" na coluna.
- Menu fixo na barra lateral (hoje: botão ao lado das mensagens, lançador flutuante e `Alt+I`).
- Aviso in-app só aparece nas telas de conversas e inbox (onde a coluna existe). Em outras telas só há o push.

## Decisões pendentes para o dono

1. **Retenção**: 90 dias por padrão, configurável por conta (`internal_chat_retention_days`). Falta decidir se
   apaga, arquiva ou exporta, e se o limite vale também para o que o usuário vê na tela.
2. **Visibilidade**: conversa direta só dos dois; sala de time só dos membros; administrador **não** lê conversa
   direta. Se for preciso auditoria, falta decidir quem, como e com aviso aos envolvidos.
3. **Push ligado por padrão?** Hoje a flag `push_internal_message` nasce **desligada** (como as outras, só
   `conversation_assignment` nasce ligada). Cada agente precisa marcar em Perfil > Notificações. Alternativa:
   ligar para todos por padrão (migração de dados).
4. **Push fora do expediente**: hoje chega sempre (se a preferência estiver ligada). Falta definir qual expediente
   vale (o do ALLChat é por caixa) e o que é "urgente" (por exemplo, só `help_request`).
5. **Quem pode receber pedido de ajuda**: hoje qualquer agente da conta, escolhido pelo remetente. Pode-se limitar a
   supervisores e administradores, ou a quem está online.
6. **Salas de time**: criadas na primeira listagem de um membro. Quem entra no time depois não vê o histórico como
   não lido, mas o histórico continua visível para ele. Falta decidir se vê o que veio antes de entrar.
