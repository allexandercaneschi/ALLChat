<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import BroadcastListsAPI from 'dashboard/api/broadcastLists';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BroadcastListFormDialog from 'dashboard/components-next/BroadcastLists/BroadcastListFormDialog.vue';

const { t } = useI18n();
const router = useRouter();
const { isAdmin } = useAdmin();

const lists = ref([]);
const isFetching = ref(true);
const isSaving = ref(false);
const formDialogRef = ref(null);

const emptyMessage = computed(() =>
  isAdmin.value
    ? t('BROADCAST_LISTS.EMPTY')
    : t('BROADCAST_LISTS.EMPTY_AGENT')
);

const fetchLists = async () => {
  isFetching.value = true;
  try {
    const { data } = await BroadcastListsAPI.get();
    lists.value = data.payload;
  } catch {
    useAlert(t('BROADCAST_LISTS.FETCH_ERROR'));
  } finally {
    isFetching.value = false;
  }
};

const showList = listId => {
  router.push({ name: 'broadcast_lists_show', params: { listId } });
};

const createList = async attributes => {
  isSaving.value = true;
  try {
    const { data } = await BroadcastListsAPI.create({
      broadcast_list: attributes,
    });
    formDialogRef.value?.close();
    useAlert(t('BROADCAST_LISTS.MESSAGES.CREATED'));
    showList(data.id);
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('BROADCAST_LISTS.MESSAGES.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

onMounted(fetchLists);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="px-6">
      <div
        class="flex items-center justify-between w-full h-20 max-w-5xl gap-2 mx-auto"
      >
        <span class="text-heading-1 text-n-slate-12">
          {{ t('BROADCAST_LISTS.HEADER') }}
        </span>
        <Button
          v-if="isAdmin"
          :label="t('BROADCAST_LISTS.NEW')"
          icon="i-lucide-plus"
          size="sm"
          @click="formDialogRef?.open()"
        />
      </div>
    </header>
    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-5xl py-4 mx-auto">
        <div
          v-if="isFetching"
          class="flex items-center justify-center py-10 text-n-slate-11"
        >
          <Spinner />
        </div>
        <p
          v-else-if="!lists.length"
          class="py-10 text-base text-center text-n-slate-11"
        >
          {{ emptyMessage }}
        </p>
        <div v-else class="flex flex-col gap-3">
          <button
            v-for="list in lists"
            :key="list.id"
            type="button"
            class="flex items-center justify-between w-full gap-4 px-5 py-4 text-start rounded-xl outline outline-1 outline-n-container bg-n-solid-2 hover:bg-n-alpha-1"
            @click="showList(list.id)"
          >
            <div class="flex flex-col min-w-0 gap-1">
              <span class="text-base font-medium truncate text-n-slate-12">
                {{ list.name }}
              </span>
              <span
                v-if="list.description"
                class="text-sm truncate text-n-slate-11"
              >
                {{ list.description }}
              </span>
              <span class="text-xs text-n-slate-10">
                {{ t('BROADCAST_LISTS.LABEL', { label: list.label }) }}
              </span>
            </div>
            <span class="text-sm shrink-0 text-n-slate-11">
              {{
                t('BROADCAST_LISTS.CONTACTS_COUNT', {
                  count: list.contacts_count,
                })
              }}
            </span>
          </button>
        </div>
      </div>
    </main>
    <BroadcastListFormDialog
      ref="formDialogRef"
      :is-loading="isSaving"
      @submit="createList"
    />
  </section>
</template>
