<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();
const store = useStore();
const dialogRef = ref(null);
const selectedUserIds = ref([]);

const agents = useMapGetter('agents/getAgents');

// Administrators already use every list, so only the other users are offered.
const options = computed(() =>
  (agents.value || [])
    .filter(agent => agent.role !== 'administrator')
    .map(agent => ({ value: agent.id, label: agent.name }))
);

const open = list => {
  selectedUserIds.value = [...(list?.user_ids || [])];
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

onMounted(() => store.dispatch('agents/get'));

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('BROADCAST_LISTS.USERS.TITLE')"
    :description="t('BROADCAST_LISTS.USERS.DESCRIPTION')"
    :confirm-button-label="t('BROADCAST_LISTS.FORM.SAVE')"
    :is-loading="isLoading"
    overflow-y-auto
    @confirm="emit('submit', selectedUserIds)"
  >
    <TagMultiSelectComboBox
      v-model="selectedUserIds"
      :options="options"
      :placeholder="t('BROADCAST_LISTS.USERS.PLACEHOLDER')"
    />
  </Dialog>
</template>
