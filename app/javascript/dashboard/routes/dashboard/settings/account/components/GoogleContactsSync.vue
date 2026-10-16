<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import GoogleContactsAPI from 'dashboard/api/googleContacts';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

// ALLChat: connect a Google account and follow the two-way contacts sync.
const { t } = useI18n();

const status = ref(null);
const enabled = ref(true);
const dryRun = ref(true);
const isBusy = ref(false);

const connection = computed(() => status.value?.connection);
const summary = computed(() => connection.value?.last_sync_summary || {});

const counts = computed(() => {
  const value = summary.value.counts || {};
  return [
    [t('GOOGLE_CONTACTS_SYNC.COUNTS.CREATE_GOOGLE'), value.create_google],
    [t('GOOGLE_CONTACTS_SYNC.COUNTS.CREATE_CHATWOOT'), value.create_chatwoot],
    [t('GOOGLE_CONTACTS_SYNC.COUNTS.UPDATE_GOOGLE'), value.update_google],
    [t('GOOGLE_CONTACTS_SYNC.COUNTS.UPDATE_CHATWOOT'), value.update_chatwoot],
    [t('GOOGLE_CONTACTS_SYNC.COUNTS.DUPLICATES'), summary.value.duplicates?.length],
    [
      t('GOOGLE_CONTACTS_SYNC.COUNTS.INVALID_PHONES'),
      summary.value.invalid_phones?.length,
    ],
  ];
});

const applyStatus = data => {
  status.value = data;
  enabled.value = data.connection?.enabled ?? true;
  dryRun.value = data.connection?.dry_run ?? true;
};

const run = async action => {
  isBusy.value = true;
  try {
    await action();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('GOOGLE_CONTACTS_SYNC.API_ERROR')
    );
  } finally {
    isBusy.value = false;
  }
};

const fetchStatus = () =>
  run(async () => applyStatus((await GoogleContactsAPI.get()).data));

const connect = () =>
  run(async () => {
    const { data } = await GoogleContactsAPI.authorize();
    window.location.href = data.url;
  });

const updateSettings = () =>
  run(async () => {
    const { data } = await GoogleContactsAPI.update({
      enabled: enabled.value,
      dry_run: dryRun.value,
    });
    status.value = { ...status.value, connection: data };
  });

const syncNow = () =>
  run(async () => {
    await GoogleContactsAPI.sync();
    useAlert(t('GOOGLE_CONTACTS_SYNC.SYNC_QUEUED'));
  });

const disconnect = () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('GOOGLE_CONTACTS_SYNC.CONFIRM_DISCONNECT'))) return;
  run(async () => {
    await GoogleContactsAPI.disconnect();
    status.value = { ...status.value, connection: null };
  });
};

onMounted(fetchStatus);
</script>

<template>
  <SectionLayout
    :title="t('GOOGLE_CONTACTS_SYNC.TITLE')"
    :description="t('GOOGLE_CONTACTS_SYNC.NOTE')"
    with-border
  >
    <div v-if="status" class="flex flex-col gap-4 text-sm text-n-slate-12">
      <p v-if="!status.configured" class="m-0 text-n-slate-11 break-all">
        {{
          t('GOOGLE_CONTACTS_SYNC.NOT_CONFIGURED', {
            uri: status.redirect_uri,
          })
        }}
      </p>

      <div v-else-if="!connection">
        <NextButton
          blue
          :is-loading="isBusy"
          :label="t('GOOGLE_CONTACTS_SYNC.CONNECT')"
          @click="connect"
        />
      </div>

      <template v-else>
        <div class="flex flex-wrap items-center justify-between gap-2">
          <span class="font-medium">
            {{
              t('GOOGLE_CONTACTS_SYNC.CONNECTED_AS', {
                email: connection.email,
              })
            }}
          </span>
          <NextButton
            ruby
            ghost
            sm
            :disabled="isBusy"
            :label="t('GOOGLE_CONTACTS_SYNC.DISCONNECT')"
            @click="disconnect"
          />
        </div>

        <label class="flex items-center justify-between gap-4">
          <span>{{ t('GOOGLE_CONTACTS_SYNC.ENABLED') }}</span>
          <Switch v-model="enabled" @change="updateSettings" />
        </label>
        <label class="flex items-center justify-between gap-4">
          <span>{{ t('GOOGLE_CONTACTS_SYNC.DRY_RUN') }}</span>
          <Switch v-model="dryRun" @change="updateSettings" />
        </label>

        <div class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-n-slate-11">
              {{
                connection.last_synced_at
                  ? t('GOOGLE_CONTACTS_SYNC.LAST_SYNC', {
                      time: dynamicTime(connection.last_synced_at),
                    })
                  : t('GOOGLE_CONTACTS_SYNC.NEVER_SYNCED')
              }}
            </span>
            <NextButton
              faded
              sm
              :is-loading="isBusy"
              :label="t('GOOGLE_CONTACTS_SYNC.SYNC_NOW')"
              @click="syncNow"
            />
          </div>
          <p v-if="summary.dry_run" class="m-0 text-n-amber-11">
            {{ t('GOOGLE_CONTACTS_SYNC.LAST_RUN_DRY') }}
          </p>
          <dl v-if="summary.counts" class="grid grid-cols-2 gap-x-4 gap-y-1 m-0">
            <template v-for="[label, value] in counts" :key="label">
              <dt class="text-n-slate-11">{{ label }}</dt>
              <dd class="m-0 font-medium text-end tabular-nums">
                {{ value || 0 }}
              </dd>
            </template>
          </dl>
          <p v-if="connection.last_error" class="m-0 text-n-ruby-11">
            {{
              t('GOOGLE_CONTACTS_SYNC.ERROR', { error: connection.last_error })
            }}
          </p>
        </div>
      </template>
    </div>
  </SectionLayout>
</template>
