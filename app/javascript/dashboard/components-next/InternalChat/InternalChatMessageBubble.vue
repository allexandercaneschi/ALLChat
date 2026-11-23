<script setup>
import { computed } from 'vue';
import { MESSAGE_KINDS } from 'dashboard/stores/internalChat';

const props = defineProps({
  message: { type: Object, required: true },
  isOwn: { type: Boolean, default: false },
  showSender: { type: Boolean, default: false },
});

const isHelpRequest = computed(
  () => props.message.kind === MESSAGE_KINDS.HELP_REQUEST
);

const time = computed(() =>
  new Date(props.message.created_at * 1000).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  })
);
</script>

<template>
  <div
    class="flex flex-col gap-0.5 max-w-[85%]"
    :class="isOwn ? 'items-end ms-auto' : 'items-start me-auto'"
  >
    <span v-if="showSender && !isOwn" class="text-xs text-n-slate-11 px-1">
      {{ message.sender?.name }}
    </span>
    <div
      class="px-3 py-2 text-sm whitespace-pre-wrap break-words rounded-xl"
      :class="[
        isOwn ? 'bg-n-brand text-n-on-brand' : 'bg-n-alpha-2 text-n-slate-12',
        {
          'border border-n-amber-7 !bg-n-amber-3 !text-n-slate-12':
            isHelpRequest,
        },
      ]"
    >
      <span
        v-if="isHelpRequest"
        class="flex items-center gap-1 mb-1 text-xs font-medium text-n-amber-11"
      >
        <span class="i-lucide-life-buoy size-3.5" />
        {{ $t('INTERNAL_CHAT.HELP_REQUEST') }}
      </span>
      {{ message.content }}
    </div>
    <span class="text-xs text-n-slate-10 px-1">{{ time }}</span>
  </div>
</template>
