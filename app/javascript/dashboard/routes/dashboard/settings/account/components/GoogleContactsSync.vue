<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import GoogleContactsAPI from 'dashboard/api/googleContacts';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

// ALLChat: connect a Google account and follow the two-way contacts sync.
const POLL_INTERVAL_MS = 3000;
const POLL_TIMEOUT_MS = 120000;
const SIDES = ['chatwoot', 'google'];

const { t } = useI18n();

const status = ref(null);
const enabled = ref(true);
const dryRun = ref(true);
const conflictWinner = ref('google');
const choices = ref({});
const isBusy = ref(false);
const isSyncing = ref(false);
const showConflicts = ref(false);
let pollTimer = null;

const connection = computed(() => status.value?.connection);
const summary = computed(() => connection.value?.last_sync_summary || {});
const conflicts = computed(() => summary.value.conflicts || []);
const conflictCount = computed(
  () => summary.value.conflict_count ?? conflicts.value.length
);

const winnerOptions = computed(() => [
  { value: 'chatwoot', label: t('GOOGLE_CONTACTS_SYNC.SIDES.CHATWOOT') },
  { value: 'google', label: t('GOOGLE_CONTACTS_SYNC.SIDES.GOOGLE') },
  { value: 'newest', label: t('GOOGLE_CONTACTS_SYNC.SIDES.NEWEST') },
]);

const sideLabels = computed(() => ({
  chatwoot: t('GOOGLE_CONTACTS_SYNC.SIDES.CHATWOOT'),
  google: t('GOOGLE_CONTACTS_SYNC.SIDES.GOOGLE'),
}));

const counts = computed(() => {
  const value = summary.value.counts || {};
  return [
    [t('GOOGLE_CONTACTS_SYNC.COUNTS.CREATE_GOOGLE'), value.create_google],
    [t('GOOGLE_CONTACTS_SYNC.COUNTS.CREATE_CHATWOOT'), value.create_chatwoot],
    [t('GOOGLE_CONTACTS_SYNC.COUNTS.UPDATE_GOOGLE'), value.update_google],
    [t('GOOGLE_CONTACTS_SYNC.COUNTS.UPDATE_CHATWOOT'), value.update_chatwoot],
    [
      t('GOOGLE_CONTACTS_SYNC.COUNTS.DUPLICATES'),
      summary.value.duplicates?.length,
    ],
    [
      t('GOOGLE_CONTACTS_SYNC.COUNTS.INVALID_PHONES'),
      summary.value.invalid_phones?.length,
    ],
  ];
});

const savedChoices = computed(() => connection.value?.conflict_overrides || {});
const choicesChanged = computed(
  () => JSON.stringify(choices.value) !== JSON.stringify(savedChoices.value)
);

const effectiveWinner = conflict =>
  choices.value[conflict.key] || conflict.winner;

const applyStatus = data => {
  status.value = data;
  enabled.value = data.connection?.enabled ?? true;
  dryRun.value = data.connection?.dry_run ?? true;
  conflictWinner.value = data.connection?.conflict_winner ?? 'google';
  choices.value = { ...(data.connection?.conflict_overrides || {}) };
};

const run = async action => {
  isBusy.value = true;
  try {
    await action();
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        error?.response?.data?.message ||
        t('GOOGLE_CONTACTS_SYNC.API_ERROR')
    );
  } finally {
    isBusy.value = false;
  }
};

const fetchStatus = () =>
  run(async () => applyStatus((await GoogleContactsAPI.get()).data));

const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
  isSyncing.value = false;
};

// The sync runs in the background; poll until the last sync time changes.
const waitForSync = previous => {
  const startedAt = Date.now();
  isSyncing.value = true;
  const poll = async () => {
    try {
      const { data } = await GoogleContactsAPI.get();
      if (data.connection?.last_synced_at !== previous) {
        applyStatus(data);
        stopPolling();
        return;
      }
    } catch {
      // Keep polling until the timeout.
    }
    if (Date.now() - startedAt > POLL_TIMEOUT_MS) {
      stopPolling();
      useAlert(t('GOOGLE_CONTACTS_SYNC.SYNC_QUEUED'));
      return;
    }
    pollTimer = setTimeout(poll, POLL_INTERVAL_MS);
  };
  pollTimer = setTimeout(poll, POLL_INTERVAL_MS);
};

const startSync = async (apply = false) => {
  const previous = connection.value?.last_synced_at;
  await GoogleContactsAPI.sync({ apply });
  waitForSync(previous);
};

const connect = () =>
  run(async () => {
    const { data } = await GoogleContactsAPI.authorize();
    window.location.href = data.url;
  });

const updateSettings = attributes =>
  run(async () => {
    const { data } = await GoogleContactsAPI.update(attributes);
    status.value = { ...status.value, connection: data };
  });

const updateSwitches = () =>
  updateSettings({ enabled: enabled.value, dry_run: dryRun.value });

const updateWinner = value => updateSettings({ conflict_winner: value });

const syncNow = () => run(() => startSync());

const choose = (conflict, side) => {
  choices.value = { ...choices.value, [conflict.key]: side };
};

const chooseAll = side => {
  choices.value = Object.fromEntries(
    conflicts.value.map(conflict => [conflict.key, side])
  );
};

const clearChoices = () => {
  choices.value = {};
};

// Saves the choices and simulates again so the counts reflect them.
const saveChoices = () =>
  run(async () => {
    const { data } = await GoogleContactsAPI.update({
      conflict_overrides: choices.value,
    });
    status.value = { ...status.value, connection: data };
    await startSync();
  });

const applyNow = () => {
  const value = summary.value.counts || {};
  const message = t('GOOGLE_CONTACTS_SYNC.CONFIRM_APPLY', {
    createGoogle: value.create_google || 0,
    createChatwoot: value.create_chatwoot || 0,
    updateGoogle: value.update_google || 0,
    updateChatwoot: value.update_chatwoot || 0,
  });
  // eslint-disable-next-line no-alert
  if (!window.confirm(message)) return;
  run(() => startSync(true));
};

const disconnect = () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('GOOGLE_CONTACTS_SYNC.CONFIRM_DISCONNECT'))) return;
  run(async () => {
    await GoogleContactsAPI.disconnect();
    status.value = { ...status.value, connection: null };
  });
};

onMounted(fetchStatus);
onBeforeUnmount(stopPolling);
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
          <Switch v-model="enabled" @change="updateSwitches" />
        </label>
        <label class="flex items-center justify-between gap-4">
          <span>{{ t('GOOGLE_CONTACTS_SYNC.DRY_RUN') }}</span>
          <Switch v-model="dryRun" @change="updateSwitches" />
        </label>
        <div class="flex flex-wrap items-center justify-between gap-4">
          <div class="flex flex-col gap-0.5">
            <span>{{ t('GOOGLE_CONTACTS_SYNC.CONFLICT_WINNER') }}</span>
            <span class="text-xs text-n-slate-11">
              {{ t('GOOGLE_CONTACTS_SYNC.CONFLICT_WINNER_HELP') }}
            </span>
          </div>
          <Select
            v-model="conflictWinner"
            :options="winnerOptions"
            :disabled="isBusy"
            :aria-label="t('GOOGLE_CONTACTS_SYNC.CONFLICT_WINNER')"
            @update:model-value="updateWinner"
          />
        </div>

        <div class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-n-slate-11">
              <template v-if="isSyncing">
                {{ t('GOOGLE_CONTACTS_SYNC.SYNCING') }}
              </template>
              <template v-else>
                {{
                  connection.last_synced_at
                    ? t('GOOGLE_CONTACTS_SYNC.LAST_SYNC', {
                        time: dynamicTime(connection.last_synced_at),
                      })
                    : t('GOOGLE_CONTACTS_SYNC.NEVER_SYNCED')
                }}
              </template>
            </span>
            <div class="flex flex-wrap gap-2">
              <NextButton
                faded
                sm
                :is-loading="isBusy || isSyncing"
                :label="t('GOOGLE_CONTACTS_SYNC.SYNC_NOW')"
                @click="syncNow"
              />
              <NextButton
                v-if="connection.dry_run && summary.dry_run && summary.counts"
                blue
                sm
                :disabled="isBusy || isSyncing || choicesChanged"
                :label="t('GOOGLE_CONTACTS_SYNC.APPLY_NOW')"
                @click="applyNow"
              />
            </div>
          </div>
          <p v-if="summary.dry_run" class="m-0 text-n-amber-11">
            {{ t('GOOGLE_CONTACTS_SYNC.LAST_RUN_DRY') }}
          </p>
          <dl
            v-if="summary.counts"
            class="grid grid-cols-2 gap-x-4 gap-y-1 m-0"
          >
            <template v-for="[label, value] in counts" :key="label">
              <dt class="text-n-slate-11">{{ label }}</dt>
              <dd class="m-0 font-medium text-end tabular-nums">
                {{ value || 0 }}
              </dd>
            </template>
            <dt class="text-n-slate-11">
              {{ t('GOOGLE_CONTACTS_SYNC.COUNTS.CONFLICTS') }}
            </dt>
            <dd class="m-0 font-medium text-end tabular-nums">
              {{ conflictCount }}
            </dd>
          </dl>
          <p v-if="connection.last_error" class="m-0 text-n-ruby-11">
            {{
              t('GOOGLE_CONTACTS_SYNC.ERROR', { error: connection.last_error })
            }}
          </p>

          <template v-if="conflicts.length">
            <div class="flex flex-wrap items-center justify-between gap-2 pt-2">
              <NextButton
                slate
                link
                sm
                :label="
                  showConflicts
                    ? t('GOOGLE_CONTACTS_SYNC.HIDE_CONFLICTS')
                    : t('GOOGLE_CONTACTS_SYNC.REVIEW_CONFLICTS', {
                        count: conflictCount,
                      })
                "
                @click="showConflicts = !showConflicts"
              />
              <div v-if="showConflicts" class="flex flex-wrap gap-2">
                <NextButton
                  slate
                  faded
                  xs
                  :label="t('GOOGLE_CONTACTS_SYNC.ALL_CHATWOOT')"
                  @click="chooseAll('chatwoot')"
                />
                <NextButton
                  slate
                  faded
                  xs
                  :label="t('GOOGLE_CONTACTS_SYNC.ALL_GOOGLE')"
                  @click="chooseAll('google')"
                />
                <NextButton
                  slate
                  ghost
                  xs
                  :label="t('GOOGLE_CONTACTS_SYNC.CLEAR_CHOICES')"
                  @click="clearChoices"
                />
              </div>
            </div>

            <template v-if="showConflicts">
              <p class="m-0 text-xs text-n-slate-11">
                {{ t('GOOGLE_CONTACTS_SYNC.CONFLICTS_HELP') }}
              </p>
              <p
                v-if="conflictCount > conflicts.length"
                class="m-0 text-xs text-n-amber-11"
              >
                {{
                  t('GOOGLE_CONTACTS_SYNC.CONFLICTS_TRUNCATED', {
                    shown: conflicts.length,
                    total: conflictCount,
                  })
                }}
              </p>
              <ul
                class="flex flex-col gap-2 p-0 m-0 list-none max-h-[30rem] overflow-y-auto"
              >
                <li
                  v-for="conflict in conflicts"
                  :key="conflict.key"
                  class="flex flex-col gap-1.5 p-2 rounded-lg bg-n-alpha-1"
                >
                  <div class="flex items-center justify-between gap-2 text-xs">
                    <span class="font-medium tabular-nums">
                      {{ conflict.phone }}
                    </span>
                    <span
                      :class="
                        choices[conflict.key]
                          ? 'text-n-blue-11'
                          : 'text-n-slate-11'
                      "
                    >
                      {{
                        choices[conflict.key]
                          ? t('GOOGLE_CONTACTS_SYNC.CHOSEN')
                          : t('GOOGLE_CONTACTS_SYNC.BY_RULE')
                      }}
                    </span>
                  </div>
                  <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                    <button
                      v-for="side in SIDES"
                      :key="side"
                      type="button"
                      class="flex flex-col gap-0.5 p-2 text-start rounded-lg outline outline-1 -outline-offset-1 transition-colors"
                      :class="
                        effectiveWinner(conflict) === side
                          ? 'outline-n-brand bg-n-blue-3'
                          : 'outline-n-weak bg-n-solid-1 hover:outline-n-slate-6'
                      "
                      :aria-pressed="effectiveWinner(conflict) === side"
                      @click="choose(conflict, side)"
                    >
                      <span class="text-xs text-n-slate-11">
                        {{
                          effectiveWinner(conflict) === side
                            ? t('GOOGLE_CONTACTS_SYNC.PREVAILS', {
                                side: sideLabels[side],
                              })
                            : sideLabels[side]
                        }}
                      </span>
                      <span class="font-medium break-words">
                        {{
                          conflict[side].name ||
                          t('GOOGLE_CONTACTS_SYNC.NO_NAME')
                        }}
                      </span>
                      <span class="text-xs text-n-slate-11 break-all">
                        {{
                          conflict[side].email ||
                          t('GOOGLE_CONTACTS_SYNC.NO_EMAIL')
                        }}
                      </span>
                    </button>
                  </div>
                </li>
              </ul>
              <div class="flex justify-end">
                <NextButton
                  blue
                  sm
                  :disabled="!choicesChanged || isSyncing"
                  :is-loading="isBusy"
                  :label="t('GOOGLE_CONTACTS_SYNC.SAVE_CHOICES')"
                  @click="saveChoices"
                />
              </div>
            </template>
          </template>
        </div>
      </template>
    </div>
  </SectionLayout>
</template>
