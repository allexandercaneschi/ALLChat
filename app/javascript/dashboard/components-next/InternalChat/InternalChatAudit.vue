<script setup>
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useInternalChatStore } from 'dashboard/stores/internalChat';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import InternalChatMessageBubble from './InternalChatMessageBubble.vue';

const emit = defineEmits(['close']);
// Audit mode for administrators (every conversation) and supervisors (the ones of their teams).
// Read only. Each conversation opened here is recorded on the server.
const { t } = useI18n();
const store = useInternalChatStore();

const titleFor = channel => {
  if (channel.kind === 'team_room') {
    return t('INTERNAL_CHAT.AUDIT.TEAM_ROOM', { name: channel.team?.name });
  }
  const [first, second] = channel.participants;
  return t('INTERNAL_CHAT.AUDIT.BETWEEN', {
    first: first?.name,
    second: second?.name,
  });
};

const open = async channel => {
  try {
    await store.openAuditChannel(channel.id);
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.LOAD'));
  }
};

const back = () => {
  if (store.audit.activeChannel) store.closeAuditChannel();
  else emit('close');
};

onMounted(async () => {
  try {
    await store.fetchAuditChannels();
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.LOAD'));
  }
});
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
        @click="back"
      />
      <span class="text-sm font-medium truncate text-n-slate-12">
        {{
          store.audit.activeChannel
            ? titleFor(store.audit.activeChannel)
            : $t('INTERNAL_CHAT.AUDIT.TITLE')
        }}
      </span>
    </div>
    <p class="px-4 py-2 text-xs bg-n-amber-3 text-n-amber-11">
      {{ $t('INTERNAL_CHAT.AUDIT.NOTE') }}
    </p>

    <div
      v-if="store.audit.activeChannel"
      class="flex flex-col flex-1 gap-3 p-4 overflow-y-auto"
    >
      <InternalChatMessageBubble
        v-for="message in store.audit.messages"
        :key="message.id"
        :message="message"
        show-sender
        read-only
      />
    </div>
    <ul v-else class="flex flex-col flex-1 overflow-y-auto">
      <li
        v-if="!store.audit.channels.length"
        class="px-4 py-6 text-sm text-center text-n-slate-11"
      >
        {{ $t('INTERNAL_CHAT.AUDIT.EMPTY') }}
      </li>
      <li v-for="channel in store.audit.channels" :key="channel.id">
        <button
          type="button"
          class="flex items-center w-full gap-3 px-4 py-2.5 text-start hover:bg-n-alpha-2"
          @click="open(channel)"
        >
          <Avatar
            v-if="channel.kind === 'direct'"
            :name="channel.participants[0]?.name || ''"
            :src="channel.participants[0]?.thumbnail"
            :size="32"
          />
          <span
            v-else
            class="flex items-center justify-center rounded-full size-8 bg-n-alpha-2 text-n-slate-11"
          >
            <span class="i-lucide-users size-4" />
          </span>
          <span class="text-sm truncate text-n-slate-12">
            {{ titleFor(channel) }}
          </span>
        </button>
      </li>
    </ul>
  </div>
</template>
