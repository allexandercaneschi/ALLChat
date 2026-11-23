<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import NextInput from 'next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

// ALLChat: how long internal chat messages and resolved customer conversations are kept.
// Keep the defaults and limits in sync with InternalChat on the server.
const DEFAULT_RETENTION_DAYS = 365;
const MAX_RETENTION_DAYS = 3650;

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();

const internalDays = ref(DEFAULT_RETENTION_DAYS);
const conversationDays = ref(DEFAULT_RETENTION_DAYS);
const cleanupEnabled = ref(false);
const isUpdating = ref(false);

watch(
  currentAccount,
  () => {
    const settings = currentAccount.value?.settings || {};
    internalDays.value =
      settings.internal_chat_retention_days || DEFAULT_RETENTION_DAYS;
    conversationDays.value =
      settings.conversation_retention_days || DEFAULT_RETENTION_DAYS;
    cleanupEnabled.value = settings.retention_cleanup_enabled === true;
  },
  { deep: true, immediate: true }
);

const isValidDays = value => {
  const days = Number(value);
  return Number.isInteger(days) && days >= 1 && days <= MAX_RETENTION_DAYS;
};
const isValid = computed(
  () => isValidDays(internalDays.value) && isValidDays(conversationDays.value)
);

const save = async () => {
  if (!isValid.value) return;
  isUpdating.value = true;
  try {
    await updateAccount({
      internal_chat_retention_days: Number(internalDays.value),
      conversation_retention_days: Number(conversationDays.value),
      retention_cleanup_enabled: cleanupEnabled.value,
    });
    useAlert(t('INTERNAL_CHAT.DATA_RETENTION.SUCCESS'));
  } catch (error) {
    useAlert(t('INTERNAL_CHAT.DATA_RETENTION.FAILED'));
  } finally {
    isUpdating.value = false;
  }
};
</script>

<template>
  <SectionLayout
    :title="t('INTERNAL_CHAT.DATA_RETENTION.TITLE')"
    :description="t('INTERNAL_CHAT.DATA_RETENTION.NOTE')"
    with-border
  >
    <form class="flex flex-col gap-4" @submit.prevent="save">
      <div class="flex flex-wrap items-end gap-2">
        <NextInput
          id="internal-chat-retention-days"
          v-model="internalDays"
          class="w-56"
          type="number"
          min="1"
          :max="MAX_RETENTION_DAYS"
          :label="t('INTERNAL_CHAT.DATA_RETENTION.INTERNAL_LABEL')"
          :message="
            isValidDays(internalDays)
              ? ''
              : t('INTERNAL_CHAT.DATA_RETENTION.ERROR')
          "
          :message-type="isValidDays(internalDays) ? 'info' : 'error'"
        />
        <NextInput
          id="conversation-retention-days"
          v-model="conversationDays"
          class="w-64"
          type="number"
          min="1"
          :max="MAX_RETENTION_DAYS"
          :label="t('INTERNAL_CHAT.DATA_RETENTION.CONVERSATIONS_LABEL')"
          :message="
            isValidDays(conversationDays)
              ? ''
              : t('INTERNAL_CHAT.DATA_RETENTION.ERROR')
          "
          :message-type="isValidDays(conversationDays) ? 'info' : 'error'"
        />
      </div>
      <label class="flex items-start gap-2 text-sm text-n-slate-12">
        <input v-model="cleanupEnabled" type="checkbox" class="mt-1" />
        <span class="flex flex-col">
          {{ t('INTERNAL_CHAT.DATA_RETENTION.CLEANUP_LABEL') }}
          <span class="text-xs text-n-slate-11">
            {{ t('INTERNAL_CHAT.DATA_RETENTION.CLEANUP_NOTE') }}
          </span>
        </span>
      </label>
      <NextButton
        blue
        type="submit"
        class="self-start"
        :is-loading="isUpdating"
        :disabled="!isValid"
        :label="t('INTERNAL_CHAT.DATA_RETENTION.SAVE')"
      />
    </form>
  </SectionLayout>
</template>
