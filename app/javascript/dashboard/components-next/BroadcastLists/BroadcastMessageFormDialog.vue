<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import {
  NAME_VARIABLE,
  SCHEDULE_KINDS,
  SENDING_CHANNELS,
  WEEKS_OF_MONTH,
  emptyBroadcastForm,
} from './broadcastSchedule';

const props = defineProps({
  // 'send' is the quick send of one list, 'schedule' creates or edits an agenda item.
  mode: { type: String, default: 'send' },
  lists: { type: Array, default: () => [] },
  recipientCount: { type: Number, default: 0 },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const { t, locale } = useI18n();
// vue-i18n uses pt_BR, but Intl only accepts BCP 47 tags such as pt-BR.
const intlLocale = computed(() => locale.value.replace('_', '-'));
const store = useStore();
const dialogRef = ref(null);
const form = reactive(emptyBroadcastForm());

const isSchedule = computed(() => props.mode === 'schedule');
const inboxes = useMapGetter('inboxes/getInboxes');
const teams = useMapGetter('teams/getTeams');

const inboxOptions = computed(() =>
  (inboxes.value || [])
    .filter(inbox => SENDING_CHANNELS.includes(inbox.channel_type))
    .map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const teamOptions = computed(() => [
  { value: '', label: t('BROADCAST_MESSAGES.FORM.NO_TEAM') },
  ...(teams.value || []).map(team => ({ value: team.id, label: team.name })),
]);
const listOptions = computed(() =>
  props.lists.map(list => ({ value: list.id, label: list.name }))
);
const kindOptions = Object.values(SCHEDULE_KINDS).map(kind => ({
  value: kind,
  label: t(`BROADCAST_MESSAGES.KINDS.${kind.toUpperCase()}`),
}));
const monthOptions = computed(() =>
  Array.from({ length: 12 }, (_, index) => ({
    value: index + 1,
    label: new Date(2000, index, 1).toLocaleString(intlLocale.value, {
      month: 'long',
    }),
  }))
);
// 2023-01-01 is a Sunday, so day 1 + weekday is the matching weekday.
const weekdayOptions = computed(() =>
  Array.from({ length: 7 }, (_, index) => ({
    value: index,
    label: new Date(2023, 0, 1 + index).toLocaleString(intlLocale.value, {
      weekday: 'long',
    }),
  }))
);
const weekOfMonthOptions = WEEKS_OF_MONTH.map(week => ({
  value: week,
  label: t('BROADCAST_MESSAGES.FORM.WEEK_OF_MONTH_OPTION', { count: week }),
}));

const isOnce = computed(() => form.scheduleKind === SCHEDULE_KINDS.ONCE);
const isYearlyFixed = computed(
  () => form.scheduleKind === SCHEDULE_KINDS.YEARLY_FIXED
);
const isYearlyWeekday = computed(
  () => form.scheduleKind === SCHEDULE_KINDS.YEARLY_WEEKDAY
);

const isFormInvalid = computed(() => {
  const missingBase =
    !form.content.trim() ||
    !form.inboxId ||
    !form.resolveAfterHours ||
    (form.sendEmail && !isSchedule.value && !form.subject.trim());
  if (!isSchedule.value) return missingBase;
  return (
    missingBase ||
    !form.name.trim() ||
    !form.broadcastListId ||
    (isOnce.value && !form.runAt)
  );
});

const insertNameVariable = () => {
  form.content = `${form.content}${NAME_VARIABLE}`;
};

const open = (initial = null) => {
  Object.assign(form, emptyBroadcastForm(), initial || {});
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (isFormInvalid.value) return;
  emit('submit', { ...form });
};

onMounted(() => {
  store.dispatch('inboxes/get');
  store.dispatch('teams/get');
});

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      isSchedule
        ? t('BROADCAST_MESSAGES.FORM.TITLE_SCHEDULE')
        : t('BROADCAST_MESSAGES.FORM.TITLE_SEND')
    "
    :description="
      isSchedule
        ? ''
        : t('BROADCAST_MESSAGES.FORM.DESCRIPTION_SEND', {
            count: recipientCount,
          })
    "
    :confirm-button-label="
      isSchedule
        ? t('BROADCAST_MESSAGES.FORM.SAVE')
        : t('BROADCAST_MESSAGES.FORM.SEND')
    "
    :disable-confirm-button="isFormInvalid"
    :is-loading="isLoading"
    overflow-y-auto
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <template v-if="isSchedule">
        <Input
          v-model="form.name"
          :label="t('BROADCAST_MESSAGES.FORM.NAME')"
          :disabled="isLoading"
        />
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">
            {{ t('BROADCAST_MESSAGES.FORM.LIST') }}
          </label>
          <Select v-model="form.broadcastListId" :options="listOptions" />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">
            {{ t('BROADCAST_MESSAGES.FORM.KIND') }}
          </label>
          <Select v-model="form.scheduleKind" :options="kindOptions" />
        </div>
        <Input
          v-if="isOnce"
          v-model="form.runAt"
          type="datetime-local"
          :label="t('BROADCAST_MESSAGES.FORM.RUN_AT')"
          :disabled="isLoading"
        />
        <div
          v-if="isYearlyFixed || isYearlyWeekday"
          class="flex flex-wrap items-end gap-3"
        >
          <template v-if="isYearlyFixed">
            <Input
              v-model="form.day"
              type="number"
              min="1"
              max="31"
              :label="t('BROADCAST_MESSAGES.FORM.DAY')"
              class="w-24"
            />
          </template>
          <template v-else>
            <div class="flex flex-col gap-1">
              <label class="text-label text-n-slate-12">
                {{ t('BROADCAST_MESSAGES.FORM.WEEK_OF_MONTH') }}
              </label>
              <Select
                v-model="form.weekOfMonth"
                :options="weekOfMonthOptions"
              />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-label text-n-slate-12">
                {{ t('BROADCAST_MESSAGES.FORM.WEEKDAY') }}
              </label>
              <Select v-model="form.weekday" :options="weekdayOptions" />
            </div>
          </template>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">
              {{ t('BROADCAST_MESSAGES.FORM.MONTH') }}
            </label>
            <Select v-model="form.month" :options="monthOptions" />
          </div>
        </div>
        <Input
          v-if="!isOnce"
          v-model="form.sendTime"
          type="time"
          :label="t('BROADCAST_MESSAGES.FORM.SEND_TIME')"
          :message="
            form.scheduleKind === SCHEDULE_KINDS.BIRTHDAY
              ? t('BROADCAST_MESSAGES.FORM.BIRTHDAY_HINT')
              : ''
          "
          :disabled="isLoading"
        />
      </template>

      <div class="flex flex-col gap-1">
        <TextArea
          v-model="form.content"
          :label="t('BROADCAST_MESSAGES.FORM.CONTENT')"
          :max-length="4000"
          :disabled="isLoading"
          auto-height
          min-height="8rem"
        />
        <Button
          :label="
            t('BROADCAST_MESSAGES.FORM.INSERT_NAME', {
              variable: NAME_VARIABLE,
            })
          "
          icon="i-lucide-user"
          variant="link"
          color="slate"
          size="xs"
          class="self-start"
          @click="insertNameVariable"
        />
      </div>
      <Input
        v-model="form.nameFallback"
        :label="t('BROADCAST_MESSAGES.FORM.NAME_FALLBACK')"
        :message="t('BROADCAST_MESSAGES.FORM.NAME_FALLBACK_HINT')"
        :disabled="isLoading"
      />
      <div class="flex flex-col gap-1">
        <label class="text-label text-n-slate-12">
          {{ t('BROADCAST_MESSAGES.FORM.INBOX') }}
        </label>
        <Select
          v-model="form.inboxId"
          :options="inboxOptions"
          :placeholder="t('BROADCAST_MESSAGES.FORM.INBOX_PLACEHOLDER')"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-label text-n-slate-12">
          {{ t('BROADCAST_MESSAGES.FORM.TEAM') }}
        </label>
        <Select v-model="form.teamId" :options="teamOptions" />
        <span class="text-xs text-n-slate-10">
          {{ t('BROADCAST_MESSAGES.FORM.TEAM_HINT') }}
        </span>
      </div>
      <Input
        v-model="form.resolveAfterHours"
        type="number"
        min="1"
        :label="t('BROADCAST_MESSAGES.FORM.RESOLVE_AFTER_HOURS')"
        :message="t('BROADCAST_MESSAGES.FORM.RESOLVE_AFTER_HOURS_HINT')"
        :disabled="isLoading"
      />
      <div class="flex items-center gap-2">
        <Switch v-model="form.sendEmail" />
        <span class="text-sm text-n-slate-12">
          {{ t('BROADCAST_MESSAGES.FORM.SEND_EMAIL') }}
        </span>
      </div>
      <Input
        v-if="form.sendEmail && !isSchedule"
        v-model="form.subject"
        :label="t('BROADCAST_MESSAGES.FORM.SUBJECT')"
        :disabled="isLoading"
      />
      <div v-if="isSchedule" class="flex items-center gap-2">
        <Switch v-model="form.active" />
        <span class="text-sm text-n-slate-12">
          {{ t('BROADCAST_MESSAGES.FORM.ACTIVE') }}
        </span>
      </div>
    </div>
  </Dialog>
</template>
