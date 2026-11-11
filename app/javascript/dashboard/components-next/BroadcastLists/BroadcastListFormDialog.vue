<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { labelTitleFor } from './labelTitle';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();
const dialogRef = ref(null);
const isEditing = ref(false);
const form = reactive({ name: '', description: '' });

const isFormInvalid = computed(() => !form.name.trim());
const labelPreview = computed(() => labelTitleFor(form.name));

const open = (list = null) => {
  isEditing.value = !!list;
  form.name = list?.name || '';
  form.description = list?.description || '';
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (isFormInvalid.value) return;
  emit('submit', {
    name: form.name.trim(),
    description: form.description.trim() || null,
  });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      isEditing
        ? t('BROADCAST_LISTS.FORM.TITLE_EDIT')
        : t('BROADCAST_LISTS.FORM.TITLE_NEW')
    "
    :confirm-button-label="t('BROADCAST_LISTS.FORM.SAVE')"
    :disable-confirm-button="isFormInvalid"
    :is-loading="isLoading"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('BROADCAST_LISTS.FORM.NAME')"
        :disabled="isLoading"
        :message="
          labelPreview
            ? t('BROADCAST_LISTS.FORM.LABEL_HINT', { label: labelPreview })
            : ''
        "
        autofocus
      />
      <TextArea
        v-model="form.description"
        :label="t('BROADCAST_LISTS.FORM.DESCRIPTION')"
        :disabled="isLoading"
      />
    </div>
  </Dialog>
</template>
