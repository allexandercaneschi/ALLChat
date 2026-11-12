// ALLChat: schedule kinds of a broadcast and the defaults of its form.
export const SCHEDULE_KINDS = {
  ONCE: 'once',
  YEARLY_FIXED: 'yearly_fixed',
  YEARLY_WEEKDAY: 'yearly_weekday',
  BIRTHDAY: 'birthday',
};

export const DEFAULT_NAME_FALLBACK = 'cliente';
export const DEFAULT_RESOLVE_AFTER_HOURS = 24;
export const DEFAULT_SEND_TIME = '09:00';
export const NAME_VARIABLE = '{{nome}}';
export const SENDING_CHANNELS = ['Channel::Api', 'Channel::Whatsapp'];
export const WEEKS_OF_MONTH = [1, 2, 3, 4, 5];

export const emptyBroadcastForm = () => ({
  name: '',
  broadcastListId: '',
  content: '',
  inboxId: '',
  teamId: '',
  nameFallback: DEFAULT_NAME_FALLBACK,
  resolveAfterHours: DEFAULT_RESOLVE_AFTER_HOURS,
  sendEmail: false,
  subject: '',
  scheduleKind: SCHEDULE_KINDS.ONCE,
  runAt: '',
  month: 1,
  day: 1,
  weekday: 0,
  weekOfMonth: 1,
  sendTime: DEFAULT_SEND_TIME,
  active: true,
});

// The API sends snake_case and an ISO date; the datetime-local input needs
// "YYYY-MM-DDTHH:mm" in the user's own time zone.
const toLocalInput = isoDate => {
  if (!isoDate) return '';
  const date = new Date(isoDate);
  const pad = value => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

export const formFromBroadcast = broadcast => ({
  name: broadcast.name,
  broadcastListId: broadcast.broadcast_list_id,
  content: broadcast.content,
  inboxId: broadcast.inbox_id,
  teamId: broadcast.team_id || '',
  nameFallback: broadcast.name_fallback,
  resolveAfterHours: broadcast.resolve_after_hours,
  sendEmail: broadcast.send_email,
  subject: broadcast.name,
  scheduleKind: broadcast.schedule_kind,
  runAt: toLocalInput(broadcast.run_at),
  month: broadcast.month || 1,
  day: broadcast.day || 1,
  weekday: broadcast.weekday ?? 0,
  weekOfMonth: broadcast.week_of_month || 1,
  sendTime: broadcast.send_time,
  active: broadcast.active,
});

export const deliveryPayload = form => ({
  content: form.content.trim(),
  inbox_id: form.inboxId,
  team_id: form.teamId || undefined,
  name_fallback: form.nameFallback.trim() || DEFAULT_NAME_FALLBACK,
  resolve_after_hours: form.resolveAfterHours,
  send_email: form.sendEmail,
  subject: form.sendEmail ? form.subject.trim() : undefined,
});

export const schedulePayload = form => {
  const payload = {
    name: form.name.trim(),
    broadcast_list_id: form.broadcastListId,
    content: form.content.trim(),
    inbox_id: form.inboxId,
    team_id: form.teamId || null,
    name_fallback: form.nameFallback.trim() || DEFAULT_NAME_FALLBACK,
    resolve_after_hours: form.resolveAfterHours,
    send_email: form.sendEmail,
    schedule_kind: form.scheduleKind,
    send_time: form.sendTime,
    active: form.active,
  };
  if (form.scheduleKind === SCHEDULE_KINDS.ONCE) {
    payload.run_at = new Date(form.runAt).toISOString();
  }
  if (form.scheduleKind === SCHEDULE_KINDS.YEARLY_FIXED) {
    payload.month = form.month;
    payload.day = form.day;
  }
  if (form.scheduleKind === SCHEDULE_KINDS.YEARLY_WEEKDAY) {
    payload.month = form.month;
    payload.weekday = form.weekday;
    payload.week_of_month = form.weekOfMonth;
  }
  return payload;
};
