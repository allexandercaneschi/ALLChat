<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BroadcastListsAPI from 'dashboard/api/broadcastLists';
import BroadcastMessagesAPI from 'dashboard/api/broadcastMessages';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BroadcastMessageFormDialog from 'dashboard/components-next/BroadcastLists/BroadcastMessageFormDialog.vue';
import {
  SCHEDULE_KINDS,
  formFromBroadcast,
  schedulePayload,
} from 'dashboard/components-next/BroadcastLists/broadcastSchedule';

const { t, locale } = useI18n();

const broadcasts = ref([]);
const lists = ref([]);
const isFetching = ref(true);
const isSaving = ref(false);
const editingId = ref(null);
const pendingDelete = ref(null);
const formDialogRef = ref(null);
const deleteDialogRef = ref(null);

const errorMessage = error =>
  error?.response?.data?.message ||
  error?.response?.data?.error ||
  t('BROADCAST_MESSAGES.ERROR');

const monthName = month =>
  new Date(2000, month - 1, 1).toLocaleString(locale.value, { month: 'long' });

const weekdayName = weekday =>
  new Date(2023, 0, 1 + weekday).toLocaleString(locale.value, {
    weekday: 'long',
  });

const scheduleSummary = broadcast => {
  switch (broadcast.schedule_kind) {
    case SCHEDULE_KINDS.ONCE:
      return t('BROADCAST_MESSAGES.SUMMARY.ONCE', {
        date: new Date(broadcast.run_at).toLocaleString(locale.value),
      });
    case SCHEDULE_KINDS.YEARLY_FIXED:
      return t('BROADCAST_MESSAGES.SUMMARY.YEARLY_FIXED', {
        day: broadcast.day,
        month: monthName(broadcast.month),
        time: broadcast.send_time,
      });
    case SCHEDULE_KINDS.YEARLY_WEEKDAY:
      return t('BROADCAST_MESSAGES.SUMMARY.YEARLY_WEEKDAY', {
        week: broadcast.week_of_month,
        weekday: weekdayName(broadcast.weekday),
        month: monthName(broadcast.month),
        time: broadcast.send_time,
      });
    default:
      return t('BROADCAST_MESSAGES.SUMMARY.BIRTHDAY', {
        time: broadcast.send_time,
      });
  }
};

const hasBroadcasts = computed(() => broadcasts.value.length > 0);

const fetchAll = async () => {
  isFetching.value = true;
  try {
    const [broadcastsResponse, listsResponse] = await Promise.all([
      BroadcastMessagesAPI.get(),
      BroadcastListsAPI.get(),
    ]);
    broadcasts.value = broadcastsResponse.data.payload;
    lists.value = listsResponse.data.payload;
  } catch {
    useAlert(t('BROADCAST_MESSAGES.FETCH_ERROR'));
  } finally {
    isFetching.value = false;
  }
};

const openNew = () => {
  editingId.value = null;
  formDialogRef.value?.open();
};

const openEdit = broadcast => {
  editingId.value = broadcast.id;
  formDialogRef.value?.open(formFromBroadcast(broadcast));
};

const save = async form => {
  isSaving.value = true;
  const attributes = { broadcast_message: schedulePayload(form) };
  try {
    if (editingId.value) {
      await BroadcastMessagesAPI.update(editingId.value, attributes);
    } else {
      await BroadcastMessagesAPI.create(attributes);
    }
    formDialogRef.value?.close();
    useAlert(t('BROADCAST_MESSAGES.SAVED'));
    await fetchAll();
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSaving.value = false;
  }
};

const confirmDelete = broadcast => {
  pendingDelete.value = broadcast;
  deleteDialogRef.value?.open();
};

const remove = async () => {
  isSaving.value = true;
  try {
    await BroadcastMessagesAPI.delete(pendingDelete.value.id);
    deleteDialogRef.value?.close();
    useAlert(t('BROADCAST_MESSAGES.DELETED'));
    await fetchAll();
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSaving.value = false;
  }
};

onMounted(fetchAll);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="px-6">
      <div
        class="flex items-center justify-between w-full h-20 max-w-5xl gap-2 mx-auto"
      >
        <span class="text-heading-1 text-n-slate-12">
          {{ t('BROADCAST_MESSAGES.HEADER') }}
        </span>
        <Button
          :label="t('BROADCAST_MESSAGES.NEW')"
          icon="i-lucide-plus"
          size="sm"
          @click="openNew"
        />
      </div>
    </header>
    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-5xl mx-auto pb-6">
        <div v-if="isFetching" class="flex items-center justify-center py-10">
          <Spinner />
        </div>
        <p v-else-if="!hasBroadcasts" class="py-10 text-center text-n-slate-11">
          {{ t('BROADCAST_MESSAGES.EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="broadcast in broadcasts"
            :key="broadcast.id"
            class="flex flex-wrap items-center justify-between gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <div class="flex flex-col min-w-0 gap-1">
              <span class="text-heading-3 text-n-slate-12">
                {{ broadcast.name }}
              </span>
              <span class="text-sm text-n-slate-11">
                {{ broadcast.list_name }} · {{ scheduleSummary(broadcast) }}
              </span>
              <span class="text-xs text-n-slate-10">
                {{
                  broadcast.active
                    ? t('BROADCAST_MESSAGES.ACTIVE')
                    : t('BROADCAST_MESSAGES.INACTIVE')
                }}
              </span>
            </div>
            <div class="flex gap-2">
              <Button
                :label="t('BROADCAST_MESSAGES.EDIT')"
                icon="i-lucide-pencil"
                variant="outline"
                color="slate"
                size="sm"
                @click="openEdit(broadcast)"
              />
              <Button
                :label="t('BROADCAST_MESSAGES.DELETE')"
                icon="i-lucide-trash-2"
                variant="outline"
                color="ruby"
                size="sm"
                @click="confirmDelete(broadcast)"
              />
            </div>
          </li>
        </ul>
      </div>
    </main>
    <BroadcastMessageFormDialog
      ref="formDialogRef"
      mode="schedule"
      :lists="lists"
      :is-loading="isSaving"
      @submit="save"
    />
    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="
        t('BROADCAST_MESSAGES.DELETE_TITLE', { name: pendingDelete?.name })
      "
      :description="t('BROADCAST_MESSAGES.DELETE_DESCRIPTION')"
      :confirm-button-label="t('BROADCAST_MESSAGES.DELETE')"
      :is-loading="isSaving"
      @confirm="remove"
    />
  </section>
</template>
