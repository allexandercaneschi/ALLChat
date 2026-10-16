<script setup>
import { computed, watch } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { isAIAssigneeType } from 'dashboard/helper/agentHelper';
import ConversationApi from 'dashboard/api/inbox/conversation';
import wootConstants from 'dashboard/constants/globals';
import { useConversationOwnership } from 'dashboard/composables/useConversationOwnership';
import { useConversationRequestsStore } from 'dashboard/stores/conversationRequests';

import Banner from 'dashboard/components/ui/Banner.vue';

const props = defineProps({
  message: {
    type: String,
    default: '',
  },
  isOnPrivateNote: {
    type: Boolean,
    default: false,
  },
});

const store = useStore();
const { t } = useI18n();

const currentChat = useMapGetter('getSelectedChat');
const currentUser = useMapGetter('getCurrentUser');

const assignedAgent = computed(() => currentChat.value?.meta?.assignee);

// ALLChat: ownership banners. Unassigned conversations always offer
// "Assign to me"; agents ask to participate in someone else's conversation.
const requests = useConversationRequestsStore();
const {
  assignee,
  isUnassigned,
  isOwner,
  isManager,
  canReply,
  pendingTransfer,
  pendingParticipation,
} = useConversationOwnership();

watch(
  () => currentChat.value?.id,
  conversationId => {
    if (conversationId) requests.fetchForConversation(conversationId);
  },
  { immediate: true }
);

const showSelfAssignBanner = computed(
  () =>
    !props.isOnPrivateNote &&
    (isUnassigned.value ||
      (isManager.value &&
        props.message !== '' &&
        assignedAgent.value?.id !== currentUser.value?.id))
);

const showPendingTransferBanner = computed(
  () => isOwner.value && !!pendingTransfer.value
);

const showParticipationBanner = computed(
  () => !props.isOnPrivateNote && !isUnassigned.value && !canReply.value
);

const participationBannerMessage = computed(() =>
  pendingParticipation.value
    ? t('CONVERSATION_REQUESTS.BANNER.WAITING_PARTICIPATION', {
        name: assignee.value?.name,
      })
    : t('CONVERSATION_REQUESTS.BANNER.OWNED_BY_OTHER', {
        name: assignee.value?.name,
      })
);

const onClickParticipation = async () => {
  try {
    if (pendingParticipation.value) {
      await requests.respond(pendingParticipation.value.id, 'cancel');
      return;
    }
    await requests.askParticipation(currentChat.value.id);
    useAlert(
      t('CONVERSATION_REQUESTS.BANNER.ASK_SENT', { name: assignee.value?.name })
    );
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CONVERSATION_REQUESTS.BANNER.ERROR')
    );
  }
};

const onCancelTransfer = async () => {
  try {
    await requests.respond(pendingTransfer.value.id, 'cancel');
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CONVERSATION_REQUESTS.BANNER.ERROR')
    );
  }
};

const selfAssignBannerMessage = computed(() =>
  isUnassigned.value
    ? t('CONVERSATION.UNASSIGNED_ASSIGN_TO_REPLY')
    : t('CONVERSATION.NOT_ASSIGNED_TO_YOU')
);

const showBotHandoffBanner = computed(
  () =>
    currentChat.value?.status === wootConstants.STATUS_TYPE.PENDING &&
    isAIAssigneeType(currentChat.value?.meta?.assignee_type)
);

const botAssigneeName = computed(
  () =>
    assignedAgent.value?.name || t('CONVERSATION.BOT_HANDOFF_FALLBACK_ASSIGNEE')
);

const selfAssignConversation = async conversationId => {
  const { data } = await ConversationApi.assignAgent({
    conversationId,
    agentId: currentUser.value.id,
    assigneeType: 'User',
  });
  await store.dispatch('setCurrentChatAssignee', {
    conversationId,
    assignee: data,
    assigneeType: 'User',
  });
};

const onClickSelfAssign = async () => {
  try {
    await selfAssignConversation(currentChat.value.id);
    useAlert(t('CONVERSATION.CHANGE_AGENT'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CONVERSATION.CHANGE_AGENT_FAILED')
    );
  }
};

const onClickBotHandoff = async () => {
  const conversationId = currentChat.value.id;
  try {
    await selfAssignConversation(conversationId);
    store.commit('CHANGE_CONVERSATION_STATUS', {
      conversationId,
      status: 'open',
      snoozedUntil: null,
    });
    useAlert(t('CONVERSATION.BOT_HANDOFF_SUCCESS'));
  } catch (error) {
    useAlert(t('CONVERSATION.BOT_HANDOFF_ERROR'));
  }
};
</script>

<template>
  <Banner
    v-if="showSelfAssignBanner && !showBotHandoffBanner"
    action-button-variant="ghost"
    color-scheme="secondary"
    class="mx-2 mb-2 rounded-lg !py-2"
    :banner-message="selfAssignBannerMessage"
    has-action-button
    :action-button-label="$t('CONVERSATION.ASSIGN_TO_ME')"
    @primary-action="onClickSelfAssign"
  />
  <Banner
    v-if="showPendingTransferBanner"
    action-button-variant="ghost"
    color-scheme="secondary"
    class="mx-2 mb-2 rounded-lg !py-2"
    :banner-message="
      $t('CONVERSATION_REQUESTS.BANNER.WAITING_TRANSFER', {
        name: pendingTransfer.target.name,
      })
    "
    has-action-button
    :action-button-label="$t('CONVERSATION_REQUESTS.BANNER.CANCEL')"
    @primary-action="onCancelTransfer"
  />
  <Banner
    v-if="showParticipationBanner"
    action-button-variant="ghost"
    color-scheme="secondary"
    class="mx-2 mb-2 rounded-lg !py-2"
    :banner-message="participationBannerMessage"
    has-action-button
    :action-button-label="
      pendingParticipation
        ? $t('CONVERSATION_REQUESTS.BANNER.CANCEL')
        : $t('CONVERSATION_REQUESTS.BANNER.ASK')
    "
    @primary-action="onClickParticipation"
  />
  <Banner
    v-if="showBotHandoffBanner"
    action-button-variant="ghost"
    color-scheme="secondary"
    class="mx-2 mb-2 rounded-lg !py-2"
    :banner-message="
      $t('CONVERSATION.BOT_HANDOFF_MESSAGE', {
        assigneeName: botAssigneeName,
      })
    "
    has-action-button
    :action-button-label="$t('CONVERSATION.BOT_HANDOFF_ACTION')"
    @primary-action="onClickBotHandoff"
  />
</template>
