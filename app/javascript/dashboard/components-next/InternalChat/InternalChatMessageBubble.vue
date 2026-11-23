<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { MESSAGE_KINDS } from 'dashboard/stores/internalChat';

const props = defineProps({
  message: { type: Object, required: true },
  isOwn: { type: Boolean, default: false },
  showSender: { type: Boolean, default: false },
  currentUserId: { type: Number, default: 0 },
  // Audit mode only reads.
  readOnly: { type: Boolean, default: false },
});

const emit = defineEmits(['claim', 'resolve']);

const { t } = useI18n();

const isHelpRequest = computed(
  () => props.message.kind === MESSAGE_KINDS.HELP_REQUEST
);
const isNudge = computed(() => props.message.kind === MESSAGE_KINDS.NUDGE);
const isResolved = computed(() => !!props.message.resolved_at);
const takenBy = computed(() => props.message.claimed_by);

const canClaim = computed(
  () =>
    !props.readOnly &&
    isHelpRequest.value &&
    !takenBy.value &&
    !isResolved.value &&
    !props.isOwn
);
const canResolve = computed(
  () =>
    !props.readOnly &&
    isHelpRequest.value &&
    !isResolved.value &&
    (props.isOwn || takenBy.value?.id === props.currentUserId)
);

const helpStatus = computed(() => {
  if (isResolved.value) return t('INTERNAL_CHAT.HELP.STATUS_RESOLVED');
  if (takenBy.value) {
    return t('INTERNAL_CHAT.HELP.STATUS_TAKEN', { name: takenBy.value.name });
  }
  return t('INTERNAL_CHAT.HELP.STATUS_OPEN');
});

const nudgeText = computed(() =>
  props.isOwn
    ? t('INTERNAL_CHAT.NUDGE.FROM_ME')
    : t('INTERNAL_CHAT.NUDGE.FROM_OTHER', { name: props.message.sender?.name })
);

const time = computed(() =>
  new Date(props.message.created_at * 1000).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  })
);
</script>

<template>
  <p
    v-if="isNudge"
    class="flex items-center self-center gap-1 px-3 py-1 text-xs rounded-full bg-n-amber-3 text-n-amber-11"
  >
    <span class="i-lucide-bell-ring size-3.5" />
    {{ nudgeText }}
    <span class="text-n-slate-10">{{ time }}</span>
  </p>
  <div
    v-else
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
          'border border-n-ruby-7': message.urgent,
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
      <span
        v-else-if="message.urgent"
        class="flex items-center gap-1 mb-1 text-xs font-medium text-n-ruby-11"
      >
        <span class="i-lucide-siren size-3.5" />
        {{ $t('INTERNAL_CHAT.URGENT.BADGE') }}
      </span>
      {{ message.content }}
      <div v-if="isHelpRequest" class="flex flex-col gap-2 mt-2">
        <span class="text-xs text-n-slate-11">{{ helpStatus }}</span>
        <div v-if="canClaim || canResolve" class="flex gap-2">
          <Button
            v-if="canClaim"
            solid
            blue
            xs
            :label="$t('INTERNAL_CHAT.HELP.CLAIM')"
            @click="emit('claim', message)"
          />
          <Button
            v-if="canResolve"
            faded
            slate
            xs
            :label="$t('INTERNAL_CHAT.HELP.RESOLVE')"
            @click="emit('resolve', message)"
          />
        </div>
      </div>
    </div>
    <span class="text-xs text-n-slate-10 px-1">{{ time }}</span>
  </div>
</template>
