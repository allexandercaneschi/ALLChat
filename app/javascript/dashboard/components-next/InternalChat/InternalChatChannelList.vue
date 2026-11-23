<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useInternalChatStore } from 'dashboard/stores/internalChat';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { getChannelTitle, filterAgentsForChat } from './helpers';

const SEARCH_DEBOUNCE_MS = 300;
const MIN_SEARCH_LENGTH = 2;

const { t } = useI18n();
const store = useInternalChatStore();
const currentUser = useMapGetter('getCurrentUser');
const agents = useMapGetter('agents/getAgents');

const isStartingChat = ref(false);
const query = ref('');
const searchQuery = ref('');
const searchResults = ref([]);
const hasSearched = ref(false);

const candidates = computed(() =>
  filterAgentsForChat(agents.value, currentUser.value.id, query.value)
);

const preview = channel => {
  const message = channel.last_message;
  if (!message) return t('INTERNAL_CHAT.NO_MESSAGE_YET');
  const own = message.sender?.id === currentUser.value.id;
  return `${own ? `${t('INTERNAL_CHAT.YOU')}: ` : ''}${message.content}`;
};

const open = async openAction => {
  try {
    await openAction();
    isStartingChat.value = false;
    query.value = '';
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.OPEN'));
  }
};

const isSearching = computed(
  () => searchQuery.value.trim().length >= MIN_SEARCH_LENGTH
);

const runSearch = async () => {
  if (!isSearching.value) {
    searchResults.value = [];
    hasSearched.value = false;
    return;
  }
  try {
    const data = await store.search({ query: searchQuery.value.trim() });
    searchResults.value = data.payload;
    hasSearched.value = true;
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEARCH'));
  }
};
watch(searchQuery, useDebounceFn(runSearch, SEARCH_DEBOUNCE_MS));

const channelTitleFor = message => {
  const channel = store.channels[message.channel_id];
  return channel ? getChannelTitle(channel) : '';
};

const openResult = message => {
  searchQuery.value = '';
  return open(() => store.setActiveChannel(message.channel_id));
};

const openChannel = channel => open(() => store.setActiveChannel(channel.id));
const startDirect = agent => open(() => store.openDirect(agent.id));
</script>

<template>
  <div class="flex flex-col w-full min-h-0">
    <div class="flex items-center justify-between px-4 py-2">
      <span class="text-sm text-n-slate-11">
        {{ $t('INTERNAL_CHAT.NEW_CHAT') }}
      </span>
      <Button
        ghost
        slate
        sm
        :icon="isStartingChat ? 'i-lucide-x' : 'i-lucide-plus'"
        @click="isStartingChat = !isStartingChat"
      />
    </div>

    <div class="px-4 pb-2">
      <input
        v-model="searchQuery"
        type="search"
        class="w-full !mb-0 text-sm"
        :placeholder="$t('INTERNAL_CHAT.SEARCH.ALL')"
      />
    </div>

    <ul v-if="isSearching" class="flex flex-col flex-1 overflow-y-auto">
      <li
        v-if="hasSearched && !searchResults.length"
        class="px-4 py-6 text-sm text-center text-n-slate-11"
      >
        {{ $t('INTERNAL_CHAT.SEARCH.NO_RESULTS') }}
      </li>
      <li v-for="message in searchResults" :key="message.id">
        <button
          type="button"
          class="flex flex-col w-full gap-0.5 px-4 py-2.5 text-start hover:bg-n-alpha-2"
          @click="openResult(message)"
        >
          <span class="flex gap-1 text-xs text-n-slate-11">
            <span class="truncate">{{ channelTitleFor(message) }}</span>
            <span class="truncate">{{ message.sender?.name }}</span>
          </span>
          <span class="text-sm text-n-slate-12 line-clamp-2">
            {{ message.content }}
          </span>
        </button>
      </li>
    </ul>

    <div
      v-if="isStartingChat && !isSearching"
      class="flex flex-col gap-2 px-4 pb-3"
    >
      <input
        v-model="query"
        type="search"
        class="w-full !mb-0 text-sm"
        :placeholder="$t('INTERNAL_CHAT.SEARCH_AGENT')"
      />
      <ul class="flex flex-col max-h-48 overflow-y-auto">
        <li v-for="agent in candidates" :key="agent.id">
          <button
            type="button"
            class="flex items-center w-full gap-2 px-2 py-1.5 text-start rounded-lg hover:bg-n-alpha-2"
            @click="startDirect(agent)"
          >
            <Avatar :name="agent.name" :src="agent.thumbnail" :size="24" />
            <span class="text-sm truncate text-n-slate-12">
              {{ agent.name }}
            </span>
          </button>
        </li>
        <li
          v-if="!candidates.length"
          class="px-2 py-1.5 text-sm text-n-slate-11"
        >
          {{ $t('INTERNAL_CHAT.NO_AGENT_FOUND') }}
        </li>
      </ul>
    </div>

    <ul v-if="!isSearching" class="flex flex-col flex-1 overflow-y-auto">
      <li v-for="channel in store.channelList" :key="channel.id">
        <button
          type="button"
          class="flex items-center w-full gap-3 px-4 py-2.5 text-start hover:bg-n-alpha-2"
          @click="openChannel(channel)"
        >
          <Avatar
            v-if="channel.kind === 'direct'"
            :name="getChannelTitle(channel)"
            :src="channel.user?.thumbnail"
            :size="32"
          />
          <span
            v-else
            class="flex items-center justify-center rounded-full size-8 bg-n-alpha-2 text-n-slate-11"
            :title="$t('INTERNAL_CHAT.TEAM_ROOM')"
          >
            <span class="i-lucide-users size-4" />
          </span>
          <span class="flex flex-col flex-1 min-w-0">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ getChannelTitle(channel) }}
            </span>
            <span class="text-xs truncate text-n-slate-11">
              {{ preview(channel) }}
            </span>
          </span>
          <span
            v-if="channel.unread_count"
            class="flex items-center justify-center px-1.5 text-xs font-medium rounded-full min-w-5 h-5 bg-n-brand text-n-on-brand"
          >
            {{ channel.unread_count }}
          </span>
        </button>
      </li>
      <li
        v-if="!store.channelList.length"
        class="px-4 py-6 text-sm text-center text-n-slate-11"
      >
        {{ $t('INTERNAL_CHAT.NO_CHANNELS') }}
      </li>
    </ul>
  </div>
</template>
