<script setup>
import { computed, onMounted, onBeforeUnmount, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import {
  useConversationRequestsStore,
  REQUEST_STATUS,
  REQUEST_TYPES,
} from 'dashboard/stores/conversationRequests';
import Button from 'dashboard/components-next/button/Button.vue';

// ALLChat: incoming transfer / participation requests for the current agent,
// plus toasts when the agent's own requests are answered or expire.
const CLOCK_TICK_MS = 30000;

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const requests = useConversationRequestsStore();

const now = ref(Date.now());
const busyId = ref(null);
let clock = null;

const incoming = computed(() => {
  // `now` keeps the list in step with expirations.
  return now.value && requests.incomingOpen(currentUser.value?.id);
});

const minutesLeft = request =>
  Math.max(1, Math.ceil((request.expires_at * 1000 - now.value) / 60000));

const title = request =>
  request.request_type === REQUEST_TYPES.TRANSFER
    ? t('CONVERSATION_REQUESTS.PROMPT.TRANSFER', {
        name: request.requester.name,
        id: request.conversation_id,
      })
    : t('CONVERSATION_REQUESTS.PROMPT.PARTICIPATION', {
        name: request.requester.name,
        id: request.conversation_id,
      });

const openConversation = request => {
  router.push(
    frontendURL(
      conversationUrl({
        accountId: accountId.value,
        id: request.conversation_id,
      })
    )
  );
};

const respond = async (request, action) => {
  busyId.value = request.id;
  try {
    await requests.respond(request.id, action);
    if (action === 'accept') openConversation(request);
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CONVERSATION_REQUESTS.PROMPT.ERROR')
    );
  } finally {
    busyId.value = null;
  }
};

// Toast the requester when one of their requests is answered.
const outcomeMessage = (request, params) => {
  if (request.status === REQUEST_STATUS.ACCEPTED) {
    return request.request_type === REQUEST_TYPES.TRANSFER
      ? t('CONVERSATION_REQUESTS.OUTCOME.TRANSFER_ACCEPTED', params)
      : t('CONVERSATION_REQUESTS.OUTCOME.PARTICIPATION_ACCEPTED', params);
  }
  if (request.status === 'declined') {
    return t('CONVERSATION_REQUESTS.OUTCOME.DECLINED', params);
  }
  if (request.status === 'expired') {
    return t('CONVERSATION_REQUESTS.OUTCOME.EXPIRED', params);
  }
  return '';
};
const seenStatus = {};

watch(
  () => requests.records,
  records => {
    Object.values(records).forEach(request => {
      const previous = seenStatus[request.id];
      seenStatus[request.id] = request.status;
      if (previous !== REQUEST_STATUS.PENDING) return;
      if (request.requester.id !== currentUser.value?.id) return;

      const message = outcomeMessage(request, {
        name: request.target.name,
        id: request.conversation_id,
      });
      if (message) useAlert(message);
    });
  },
  { deep: true }
);

onMounted(() => {
  requests.fetchMine().catch(() => {});
  clock = setInterval(() => {
    now.value = Date.now();
  }, CLOCK_TICK_MS);
});

onBeforeUnmount(() => clearInterval(clock));
</script>

<template>
  <div
    v-show="incoming.length"
    class="fixed z-50 flex flex-col gap-2 ltr:right-4 rtl:left-4 bottom-4 w-[22rem] max-w-[calc(100vw-2rem)]"
  >
    <div
      v-for="request in incoming"
      :key="request.id"
      class="flex flex-col gap-3 p-4 border rounded-xl bg-n-solid-2 border-n-strong shadow-lg"
    >
      <div class="flex flex-col gap-1">
        <p class="m-0 text-sm font-medium text-n-slate-12">
          {{ title(request) }}
        </p>
        <p v-if="request.contact_name" class="m-0 text-xs text-n-slate-11">
          {{
            $t('CONVERSATION_REQUESTS.PROMPT.CONTACT', {
              name: request.contact_name,
            })
          }}
        </p>
        <p class="m-0 text-xs text-n-amber-11">
          {{
            $t('CONVERSATION_REQUESTS.PROMPT.EXPIRES_IN', {
              minutes: minutesLeft(request),
            })
          }}
        </p>
      </div>
      <div class="flex items-center justify-between gap-2">
        <Button
          link
          sm
          :label="$t('CONVERSATION_REQUESTS.PROMPT.VIEW')"
          @click="openConversation(request)"
        />
        <div class="flex items-center gap-2">
          <Button
            faded
            slate
            sm
            :disabled="busyId === request.id"
            :label="$t('CONVERSATION_REQUESTS.PROMPT.DECLINE')"
            @click="respond(request, 'decline')"
          />
          <Button
            sm
            :is-loading="busyId === request.id"
            :label="$t('CONVERSATION_REQUESTS.PROMPT.ACCEPT')"
            @click="respond(request, 'accept')"
          />
        </div>
      </div>
    </div>
  </div>
</template>
