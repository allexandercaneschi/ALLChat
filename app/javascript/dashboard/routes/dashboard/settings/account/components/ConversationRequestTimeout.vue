<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import NextInput from 'next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

// ALLChat: minutes an agent has to accept a transfer or participation request.
const DEFAULT_TIMEOUT_MINUTES = 60;
const MAX_TIMEOUT_MINUTES = 1440; // keep in sync with the input's max

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();

const minutes = ref(DEFAULT_TIMEOUT_MINUTES);
const isUpdating = ref(false);

watch(
  currentAccount,
  () => {
    const { conversation_request_timeout: timeout } =
      currentAccount.value?.settings || {};
    minutes.value = timeout || DEFAULT_TIMEOUT_MINUTES;
  },
  { deep: true, immediate: true }
);

const isValid = computed(() => {
  const value = Number(minutes.value);
  return Number.isInteger(value) && value >= 1 && value <= MAX_TIMEOUT_MINUTES;
});

const save = async () => {
  if (!isValid.value) return;
  isUpdating.value = true;
  try {
    await updateAccount({
      conversation_request_timeout: Number(minutes.value),
    });
    useAlert(t('CONVERSATION_REQUESTS.SETTINGS.SUCCESS'));
  } catch (error) {
    useAlert(t('CONVERSATION_REQUESTS.SETTINGS.FAILED'));
  } finally {
    isUpdating.value = false;
  }
};
</script>

<template>
  <SectionLayout
    :title="t('CONVERSATION_REQUESTS.SETTINGS.TITLE')"
    :description="t('CONVERSATION_REQUESTS.SETTINGS.NOTE')"
    with-border
  >
    <form class="flex items-end gap-2" @submit.prevent="save">
      <NextInput
        id="conversation-request-timeout"
        v-model="minutes"
        class="w-48"
        type="number"
        min="1"
        max="1440"
        :label="t('CONVERSATION_REQUESTS.SETTINGS.LABEL')"
        :message="isValid ? '' : t('CONVERSATION_REQUESTS.SETTINGS.ERROR')"
        :message-type="isValid ? 'info' : 'error'"
      />
      <NextButton
        blue
        type="submit"
        :is-loading="isUpdating"
        :disabled="!isValid"
        :label="t('CONVERSATION_REQUESTS.SETTINGS.SAVE')"
      />
    </form>
  </SectionLayout>
</template>
