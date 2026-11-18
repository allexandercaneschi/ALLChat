<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CompanyBroadcastsAPI from 'dashboard/api/companyBroadcasts';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BroadcastMessageFormDialog from 'dashboard/components-next/BroadcastLists/BroadcastMessageFormDialog.vue';
import { deliveryPayload } from 'dashboard/components-next/BroadcastLists/broadcastSchedule';

const { t } = useI18n();

const companies = ref([]);
const selected = ref(null);
const isFetching = ref(true);
const isSaving = ref(false);
const sendDialogRef = ref(null);

const sendDescription = computed(() =>
  selected.value
    ? t('BROADCAST_COMPANIES.SEND_DESCRIPTION', {
        count: selected.value.contacts_count,
        company: selected.value.name,
      })
    : ''
);

const errorMessage = error =>
  error?.response?.data?.message ||
  error?.response?.data?.error ||
  t('BROADCAST_MESSAGES.ERROR');

const fetchCompanies = async () => {
  isFetching.value = true;
  try {
    const { data } = await CompanyBroadcastsAPI.get();
    companies.value = data.payload;
  } catch {
    useAlert(t('BROADCAST_COMPANIES.FETCH_ERROR'));
  } finally {
    isFetching.value = false;
  }
};

const openSend = company => {
  selected.value = company;
  sendDialogRef.value?.open();
};

const send = async form => {
  isSaving.value = true;
  try {
    const { data } = await CompanyBroadcastsAPI.create({
      company: selected.value.name,
      ...deliveryPayload(form),
    });
    sendDialogRef.value?.close();
    useAlert(t('BROADCAST_MESSAGES.QUEUED', { count: data.queued }));
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSaving.value = false;
  }
};

onMounted(fetchCompanies);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="px-6">
      <div
        class="flex flex-col justify-center w-full h-20 max-w-5xl gap-1 mx-auto"
      >
        <span class="text-heading-1 text-n-slate-12">
          {{ t('BROADCAST_COMPANIES.HEADER') }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ t('BROADCAST_COMPANIES.DESCRIPTION') }}
        </span>
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
          v-else-if="!companies.length"
          class="py-10 text-base text-center text-n-slate-11"
        >
          {{ t('BROADCAST_COMPANIES.EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="company in companies"
            :key="company.name"
            class="flex items-center justify-between gap-4 px-5 py-4 rounded-xl outline outline-1 outline-n-container bg-n-solid-2"
          >
            <div class="flex flex-col min-w-0 gap-1">
              <span class="text-base font-medium truncate text-n-slate-12">
                {{ company.name }}
              </span>
              <span class="text-sm text-n-slate-11">
                {{
                  t(
                    'BROADCAST_COMPANIES.CONTACTS_COUNT',
                    { count: company.contacts_count },
                    company.contacts_count
                  )
                }}
              </span>
            </div>
            <Button
              :label="t('BROADCAST_COMPANIES.SEND')"
              icon="i-lucide-send"
              size="sm"
              @click="openSend(company)"
            />
          </li>
        </ul>
      </div>
    </main>
    <BroadcastMessageFormDialog
      ref="sendDialogRef"
      mode="send"
      :description="sendDescription"
      :is-loading="isSaving"
      @submit="send"
    />
  </section>
</template>
