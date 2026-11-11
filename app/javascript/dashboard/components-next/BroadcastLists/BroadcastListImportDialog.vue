<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const ACCEPTED_FILES = '.txt,.csv,text/plain,text/csv';
const UTF8_REPLACEMENT_CHAR = '�';

const { t } = useI18n();
const dialogRef = ref(null);
const fileInputRef = ref(null);
const file = ref(null);

// Spreadsheets exported on Windows are often Windows-1252, not UTF-8.
const readFile = async selected => {
  const buffer = await selected.arrayBuffer();
  const text = new TextDecoder('utf-8').decode(buffer);
  if (!text.includes(UTF8_REPLACEMENT_CHAR)) return text;
  return new TextDecoder('windows-1252').decode(buffer);
};

const onFileChange = event => {
  [file.value] = event.target.files;
};

const open = () => {
  file.value = null;
  if (fileInputRef.value) fileInputRef.value.value = '';
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const handleConfirm = async () => {
  if (!file.value) return;
  emit('submit', await readFile(file.value));
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('BROADCAST_LISTS.IMPORT.TITLE')"
    :description="t('BROADCAST_LISTS.IMPORT.DESCRIPTION')"
    :confirm-button-label="t('BROADCAST_LISTS.IMPORT.CONFIRM')"
    :disable-confirm-button="!file"
    :is-loading="isLoading"
    @confirm="handleConfirm"
  >
    <div class="flex items-center gap-3">
      <input
        ref="fileInputRef"
        type="file"
        :accept="ACCEPTED_FILES"
        class="hidden"
        @change="onFileChange"
      />
      <Button
        :label="t('BROADCAST_LISTS.IMPORT.SELECT_FILE')"
        icon="i-lucide-file-up"
        variant="outline"
        color="slate"
        size="sm"
        @click="fileInputRef?.click()"
      />
      <span class="text-sm truncate text-n-slate-11">
        {{ file ? file.name : t('BROADCAST_LISTS.IMPORT.NO_FILE') }}
      </span>
    </div>
  </Dialog>
</template>
