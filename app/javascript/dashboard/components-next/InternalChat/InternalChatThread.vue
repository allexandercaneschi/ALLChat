<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import {
  CHANNEL_KINDS,
  useInternalChatStore,
} from 'dashboard/stores/internalChat';
import Button from 'dashboard/components-next/button/Button.vue';
import InternalChatMessageBubble from './InternalChatMessageBubble.vue';
import { getChannelTitle } from './helpers';

const SEARCH_DEBOUNCE_MS = 300;
const MIN_SEARCH_LENGTH = 2;
const CLOCK_TICK_MS = 1000;

const { t } = useI18n();
const store = useInternalChatStore();
const currentUser = useMapGetter('getCurrentUser');
const agents = useMapGetter('agents/getAgents');

const draft = ref('');
const isUrgent = ref(false);
const isSending = ref(false);
const messagesContainer = ref(null);
const mentions = ref([]);
const showMentions = ref(false);
const now = ref(Date.now());

const isSearching = ref(false);
const query = ref('');
const results = ref([]);
const hasSearched = ref(false);
const hasMoreResults = ref(false);

const channel = computed(() => store.activeChannel);
const messages = computed(() => store.messagesFor(channel.value.id));
const isDirect = computed(() => channel.value.kind === CHANNEL_KINDS.DIRECT);
const hasMore = computed(() => store.hasMoreMessages[channel.value.id]);
// A room can be restricted to administrators, or to administrators and supervisors.
const canPost = computed(() => channel.value.can_post !== false);
const canAskForHelp = computed(
  () => channel.value.kind !== CHANNEL_KINDS.COMPANY_ROOM
);
const canSend = computed(
  () => canPost.value && draft.value.trim() && !isSending.value
);
const mentionCandidates = computed(() =>
  agents.value.filter(agent => agent.id !== currentUser.value.id)
);
const nudgeSecondsLeft = computed(() => {
  const availableAt = store.nudgeAvailableAt[channel.value.id] || 0;
  return Math.max(0, Math.ceil((availableAt - now.value) / 1000));
});

const scrollToBottom = async () => {
  await nextTick();
  const container = messagesContainer.value;
  if (container) container.scrollTop = container.scrollHeight;
};

const run = async (action, errorMessage = t('INTERNAL_CHAT.ERRORS.SEND')) => {
  isSending.value = true;
  try {
    await action();
    return true;
  } catch (error) {
    useAlert(error.response?.data?.error || errorMessage);
    return false;
  } finally {
    isSending.value = false;
  }
};

const resetComposer = () => {
  draft.value = '';
  isUrgent.value = false;
  mentions.value = [];
  showMentions.value = false;
};

// Only the mentions still written in the text are sent.
const mentionedIds = () =>
  mentions.value
    .filter(mention => draft.value.includes(`@${mention.name}`))
    .map(mention => mention.id);

const sendMessage = async () => {
  if (!canSend.value) return;
  const sent = await run(() =>
    store.sendMessage(channel.value.id, {
      content: draft.value.trim(),
      urgent: isDirect.value && isUrgent.value,
      mentioned_user_ids: mentionedIds(),
    })
  );
  if (sent) resetComposer();
};

// To the one person of this direct chat, or to the whole team in a team room.
const askForHelp = async () => {
  if (!canSend.value) return;
  const audience = isDirect.value
    ? { recipientId: channel.value.user.id }
    : { teamId: channel.value.team.id };
  const sent = await run(() =>
    store.sendHelpRequest({ ...audience, content: draft.value.trim() })
  );
  if (sent) resetComposer();
};

const sendNudge = () =>
  run(() => store.sendNudge(channel.value.id), t('INTERNAL_CHAT.ERRORS.NUDGE'));

const claim = message =>
  run(async () => {
    const result = await store.claimHelpRequest(message);
    useAlert(
      result.joined_conversation
        ? t('INTERNAL_CHAT.HELP.TAKEN_JOINED')
        : t('INTERNAL_CHAT.HELP.TAKEN_NOT_JOINED')
    );
  }, t('INTERNAL_CHAT.ERRORS.CLAIM'));

const resolve = message =>
  run(() => store.resolveHelpRequest(message), t('INTERNAL_CHAT.ERRORS.CLAIM'));

const addMention = agent => {
  if (!mentions.value.some(mention => mention.id === agent.id)) {
    mentions.value.push({ id: agent.id, name: agent.name });
  }
  draft.value = `${draft.value}${draft.value && !draft.value.endsWith(' ') ? ' ' : ''}@${agent.name} `;
  showMentions.value = false;
};

const loadOlder = () =>
  store.fetchMessages(channel.value.id, messages.value[0]?.id);

const onKeydown = event => {
  if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
  event.preventDefault();
  sendMessage();
};

const search = async beforeId => {
  const text = query.value.trim();
  if (text.length < MIN_SEARCH_LENGTH) {
    results.value = [];
    hasSearched.value = false;
    return;
  }
  try {
    const data = await store.search({
      query: text,
      channelId: channel.value.id,
      beforeId,
    });
    results.value = beforeId
      ? [...results.value, ...data.payload]
      : data.payload;
    hasMoreResults.value = data.meta.has_more;
    hasSearched.value = true;
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEARCH'));
  }
};
const debouncedSearch = useDebounceFn(() => search(), SEARCH_DEBOUNCE_MS);
const showMoreResults = () =>
  search(results.value[results.value.length - 1]?.id);

const toggleSearch = () => {
  isSearching.value = !isSearching.value;
  query.value = '';
  results.value = [];
  hasSearched.value = false;
};

let clock = null;
onMounted(() => {
  store.viewingChannelId = channel.value.id;
  scrollToBottom();
  clock = setInterval(() => {
    now.value = Date.now();
  }, CLOCK_TICK_MS);
});
onBeforeUnmount(() => {
  store.viewingChannelId = null;
  clearInterval(clock);
});
watch(() => messages.value[messages.value.length - 1]?.id, scrollToBottom);
watch(
  () => channel.value.id,
  id => {
    store.viewingChannelId = id;
    resetComposer();
    isSearching.value = false;
  }
);
watch(query, debouncedSearch);
</script>

<template>
  <div class="flex flex-col flex-1 w-full min-h-0">
    <div class="flex items-center gap-2 px-2 py-2 border-b border-n-weak">
      <Button
        ghost
        slate
        sm
        icon="i-lucide-arrow-left"
        :aria-label="$t('INTERNAL_CHAT.BACK')"
        @click="store.setActiveChannel(null)"
      />
      <span class="flex-1 text-sm font-medium truncate text-n-slate-12">
        {{ getChannelTitle(channel) }}
      </span>
      <Button
        ghost
        slate
        sm
        :icon="isSearching ? 'i-lucide-x' : 'i-lucide-search'"
        :aria-label="
          isSearching
            ? $t('INTERNAL_CHAT.SEARCH.CLOSE')
            : $t('INTERNAL_CHAT.SEARCH.OPEN')
        "
        @click="toggleSearch"
      />
    </div>

    <div v-if="isSearching" class="flex flex-col flex-1 min-h-0">
      <div class="p-3">
        <input
          v-model="query"
          type="search"
          class="w-full !mb-0 text-sm"
          :placeholder="$t('INTERNAL_CHAT.SEARCH.ONE')"
        />
      </div>
      <ul class="flex flex-col flex-1 gap-3 p-3 overflow-y-auto">
        <li
          v-if="hasSearched && !results.length"
          class="text-sm text-center text-n-slate-11"
        >
          {{ $t('INTERNAL_CHAT.SEARCH.NO_RESULTS') }}
        </li>
        <li v-for="message in results" :key="message.id">
          <InternalChatMessageBubble
            :message="message"
            :is-own="message.sender?.id === currentUser.id"
            show-sender
            read-only
          />
        </li>
        <li v-if="hasMoreResults" class="self-center">
          <Button
            ghost
            slate
            xs
            :label="$t('INTERNAL_CHAT.SEARCH.MORE')"
            @click="showMoreResults"
          />
        </li>
      </ul>
    </div>

    <template v-else>
      <div
        ref="messagesContainer"
        class="flex flex-col flex-1 gap-3 p-4 overflow-y-auto"
      >
        <Button
          v-if="hasMore"
          ghost
          slate
          xs
          class="self-center"
          :label="$t('INTERNAL_CHAT.LOAD_OLDER')"
          @click="loadOlder"
        />
        <p
          v-if="!messages.length"
          class="my-auto text-sm text-center text-n-slate-11"
        >
          {{ $t('INTERNAL_CHAT.NO_MESSAGES') }}
        </p>
        <InternalChatMessageBubble
          v-for="message in messages"
          :key="message.id"
          :message="message"
          :is-own="message.sender?.id === currentUser.id"
          :current-user-id="currentUser.id"
          :show-sender="!isDirect"
          @claim="claim"
          @resolve="resolve"
        />
      </div>

      <p
        v-if="!canPost"
        class="px-4 py-3 text-sm text-center border-t border-n-weak text-n-slate-11"
      >
        {{
          channel.posting_policy === 'admins_only'
            ? $t('INTERNAL_CHAT.POSTING.ADMINS_ONLY_NOTE')
            : $t('INTERNAL_CHAT.POSTING.ADMINS_AND_SUPERVISORS_NOTE')
        }}
      </p>
      <div v-else class="flex flex-col gap-2 p-3 border-t border-n-weak">
        <ul
          v-if="showMentions"
          class="flex flex-col overflow-y-auto border rounded-lg max-h-32 border-n-weak"
        >
          <li v-for="agent in mentionCandidates" :key="agent.id">
            <button
              type="button"
              class="w-full px-3 py-1.5 text-sm text-start hover:bg-n-alpha-2 text-n-slate-12"
              @click="addMention(agent)"
            >
              {{ agent.name }}
            </button>
          </li>
          <li class="px-3 py-1.5 text-xs text-n-slate-11">
            {{ $t('INTERNAL_CHAT.MENTION.NOTIFIES') }}
          </li>
        </ul>
        <textarea
          v-model="draft"
          rows="2"
          class="w-full !mb-0 text-sm resize-none"
          :placeholder="$t('INTERNAL_CHAT.MESSAGE_PLACEHOLDER')"
          @keydown="onKeydown"
        />
        <div class="flex flex-wrap items-center gap-1">
          <Button
            v-tooltip.top="$t('INTERNAL_CHAT.MENTION.BUTTON')"
            data-testid="mention-button"
            ghost
            slate
            xs
            icon="i-lucide-at-sign"
            @click="showMentions = !showMentions"
          />
          <Button
            v-if="isDirect"
            v-tooltip.top="$t('INTERNAL_CHAT.URGENT.TOOLTIP')"
            :faded="isUrgent"
            :ghost="!isUrgent"
            :ruby="isUrgent"
            :slate="!isUrgent"
            xs
            icon="i-lucide-siren"
            :label="$t('INTERNAL_CHAT.URGENT.LABEL')"
            @click="isUrgent = !isUrgent"
          />
          <Button
            v-if="isDirect"
            v-tooltip.top="$t('INTERNAL_CHAT.NUDGE.TOOLTIP')"
            ghost
            amber
            xs
            icon="i-lucide-bell-ring"
            :label="
              nudgeSecondsLeft
                ? $t('INTERNAL_CHAT.NUDGE.WAIT', { seconds: nudgeSecondsLeft })
                : $t('INTERNAL_CHAT.NUDGE.BUTTON')
            "
            :disabled="nudgeSecondsLeft > 0 || isSending"
            @click="sendNudge"
          />
        </div>
        <div class="flex items-center justify-between gap-2">
          <Button
            v-if="canAskForHelp"
            v-tooltip.top="
              isDirect
                ? $t('INTERNAL_CHAT.ASK_HELP_TOOLTIP', {
                    name: channel.user?.name,
                  })
                : $t('INTERNAL_CHAT.HELP.ASK_TEAM')
            "
            faded
            amber
            sm
            icon="i-lucide-life-buoy"
            :label="
              isDirect
                ? $t('INTERNAL_CHAT.ASK_HELP')
                : $t('INTERNAL_CHAT.HELP.ASK_TEAM')
            "
            :disabled="!canSend"
            @click="askForHelp"
          />
          <Button
            solid
            blue
            sm
            class="ms-auto"
            icon="i-lucide-send"
            :label="$t('INTERNAL_CHAT.SEND')"
            :is-loading="isSending"
            :disabled="!canSend"
            @click="sendMessage"
          />
        </div>
      </div>
    </template>
  </div>
</template>
