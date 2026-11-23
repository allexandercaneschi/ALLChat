<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useInternalChatStore } from 'dashboard/stores/internalChat';
import Button from 'dashboard/components-next/button/Button.vue';
import InternalChatAudit from './InternalChatAudit.vue';
import InternalChatChannelList from './InternalChatChannelList.vue';
import InternalChatThread from './InternalChatThread.vue';
import { callAttention } from './attention';

// ALLChat: right column with the internal team chat. It takes the place of the contact column:
// opening one closes the other (they share the `is_*_open` UI settings of the right-hand panels).
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const store = useInternalChatStore();
const currentChat = useMapGetter('getSelectedChat');
const { checkPermissions } = usePolicy();

const isAuditing = ref(false);
const canAudit = computed(() =>
  checkPermissions(['administrator', 'supervisor'])
);

const isOpen = computed(() => !!uiSettings.value.is_internal_chat_open);
// Without an open conversation the switch next to the messages is not on screen, so offer a launcher.
const showLauncher = computed(() => !isOpen.value && !currentChat.value.id);

const toggle = () => {
  updateUISettings({
    is_internal_chat_open: !isOpen.value,
    ...(isOpen.value
      ? {}
      : { is_contact_sidebar_open: false, is_copilot_panel_open: false }),
  });
};

useKeyboardEvents({ 'Alt+KeyI': { action: toggle } });

// In-app alert for a message that arrives while its conversation is not on screen.
useEmitter(BUS_EVENTS.INTERNAL_CHAT_NEW_MESSAGE, message => {
  useAlert(
    t('INTERNAL_CHAT.NEW_MESSAGE_ALERT', { name: message.sender?.name })
  );
});

// Nudge, urgent message or mention: sound, blinking tab title and a desktop notification that stays on screen.
useEmitter(BUS_EVENTS.INTERNAL_CHAT_ATTENTION, message => {
  const name = message.sender?.name;
  let title = t('INTERNAL_CHAT.ATTENTION.MENTION', { name });
  if (message.kind === 'nudge') {
    title = t('INTERNAL_CHAT.ATTENTION.NUDGE', { name });
  } else if (message.urgent) {
    title = t('INTERNAL_CHAT.ATTENTION.URGENT', { name });
  }
  callAttention({
    title,
    body: message.content,
    tag: `internal_chat_${message.channel_id}`,
  });
});

onMounted(async () => {
  if (store.hasLoadedChannels) return;
  try {
    await store.fetchChannels();
  } catch {
    useAlert(t('INTERNAL_CHAT.ERRORS.LOAD'));
  }
});
</script>

<template>
  <div
    v-if="isOpen"
    class="bg-n-surface-2 h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none"
  >
    <div
      class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
    >
      <span class="text-heading-3 text-n-slate-12">
        {{ $t('INTERNAL_CHAT.TITLE') }}
      </span>
      <div class="flex items-center">
        <Button
          v-if="canAudit"
          v-tooltip.bottom="$t('INTERNAL_CHAT.AUDIT.TITLE')"
          :faded="isAuditing"
          :ghost="!isAuditing"
          slate
          sm
          icon="i-lucide-shield-check"
          @click="isAuditing = !isAuditing"
        />
        <Button
          ghost
          slate
          sm
          icon="i-lucide-x"
          :aria-label="$t('INTERNAL_CHAT.CLOSE')"
          @click="toggle"
        />
      </div>
    </div>
    <InternalChatAudit v-if="isAuditing" @close="isAuditing = false" />
    <InternalChatThread v-else-if="store.activeChannel" />
    <InternalChatChannelList v-else />
  </div>
  <div
    v-else-if="showLauncher"
    class="absolute z-20 top-24 ltr:right-2 rtl:left-2"
  >
    <Button
      v-tooltip.left="$t('INTERNAL_CHAT.OPEN')"
      solid
      slate
      sm
      class="!rounded-full"
      icon="i-lucide-messages-square"
      @click="toggle"
    />
    <span
      v-if="store.totalUnread"
      class="absolute flex items-center justify-center h-4 px-1 text-xs font-medium rounded-full -top-1 -end-1 min-w-4 bg-n-ruby-9 text-white"
    >
      {{ store.totalUnread }}
    </span>
  </div>
</template>
