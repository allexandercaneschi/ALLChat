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
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import {
  CHANNEL_KINDS,
  useInternalChatStore,
} from 'dashboard/stores/internalChat';
import Button from 'dashboard/components-next/button/Button.vue';
import InternalChatMessageBubble from './InternalChatMessageBubble.vue';
import { getChannelTitle } from './helpers';

const { t } = useI18n();
const store = useInternalChatStore();
const currentUser = useMapGetter('getCurrentUser');

const draft = ref('');
const isSending = ref(false);
const messagesContainer = ref(null);

const channel = computed(() => store.activeChannel);
const messages = computed(() => store.messagesFor(channel.value.id));
const isDirect = computed(() => channel.value.kind === CHANNEL_KINDS.DIRECT);
const hasMore = computed(() => store.hasMoreMessages[channel.value.id]);
const canSend = computed(() => draft.value.trim() && !isSending.value);

const scrollToBottom = async () => {
  await nextTick();
  const container = messagesContainer.value;
  if (container) container.scrollTop = container.scrollHeight;
};

const send = async sendAction => {
  if (!canSend.value) return;
  isSending.value = true;
  try {
    await sendAction(draft.value.trim());
    draft.value = '';
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.SEND'));
  } finally {
    isSending.value = false;
  }
};

const sendMessage = () =>
  send(content => store.sendMessage(channel.value.id, content));

// A help request goes to the one person of this direct chat, never to a group.
const askForHelp = () =>
  send(content =>
    store.sendHelpRequest({ recipientId: channel.value.user.id, content })
  );

const loadOlder = () =>
  store.fetchMessages(channel.value.id, messages.value[0]?.id);

const onKeydown = event => {
  if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
  event.preventDefault();
  sendMessage();
};

onMounted(() => {
  store.viewingChannelId = channel.value.id;
  scrollToBottom();
});
onBeforeUnmount(() => {
  store.viewingChannelId = null;
});
watch(() => messages.value[messages.value.length - 1]?.id, scrollToBottom);
watch(
  () => channel.value.id,
  id => {
    store.viewingChannelId = id;
  }
);
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
      <span class="text-sm font-medium truncate text-n-slate-12">
        {{ getChannelTitle(channel) }}
      </span>
    </div>

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
        :show-sender="!isDirect"
      />
    </div>

    <div class="flex flex-col gap-2 p-3 border-t border-n-weak">
      <textarea
        v-model="draft"
        rows="2"
        class="w-full !mb-0 text-sm resize-none"
        :placeholder="$t('INTERNAL_CHAT.MESSAGE_PLACEHOLDER')"
        @keydown="onKeydown"
      />
      <div class="flex items-center justify-between gap-2">
        <Button
          v-if="isDirect"
          v-tooltip.top="
            $t('INTERNAL_CHAT.ASK_HELP_TOOLTIP', { name: channel.user?.name })
          "
          faded
          amber
          sm
          icon="i-lucide-life-buoy"
          :label="$t('INTERNAL_CHAT.ASK_HELP')"
          :disabled="!canSend"
          @click="askForHelp"
        />
        <span v-else />
        <Button
          solid
          blue
          sm
          icon="i-lucide-send"
          :label="$t('INTERNAL_CHAT.SEND')"
          :is-loading="isSending"
          :disabled="!canSend"
          @click="sendMessage"
        />
      </div>
    </div>
  </div>
</template>
