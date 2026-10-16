import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { usePolicy } from 'dashboard/composables/usePolicy';
import {
  useConversationRequestsStore,
  REQUEST_TYPES,
} from 'dashboard/stores/conversationRequests';

// ALLChat: frontend mirror of Conversations::OwnershipRules.
// - Nobody replies publicly to an unassigned conversation.
// - The assignee, administrators, supervisors and agents whose participation
//   request the assignee accepted can reply.
export function useConversationOwnership() {
  const currentChat = useMapGetter('getSelectedChat');
  const currentUser = useMapGetter('getCurrentUser');
  const { checkPermissions } = usePolicy();
  const requests = useConversationRequestsStore();

  const conversationId = computed(() => currentChat.value?.id);
  const userId = computed(() => currentUser.value?.id);
  const assignee = computed(() =>
    currentChat.value?.meta?.assignee_type === 'User'
      ? currentChat.value.meta.assignee
      : null
  );

  const isUnassigned = computed(() => !assignee.value);
  const isOwner = computed(() => assignee.value?.id === userId.value);
  const isManager = computed(() =>
    checkPermissions(['administrator', 'supervisor'])
  );
  const isAuthorizedParticipant = computed(() =>
    requests.acceptedParticipation(
      conversationId.value,
      userId.value,
      assignee.value?.id
    )
  );

  const canReply = computed(
    () =>
      !isUnassigned.value &&
      (isOwner.value || isManager.value || isAuthorizedParticipant.value)
  );

  const pendingTransfer = computed(() =>
    requests.openOutgoing(
      conversationId.value,
      userId.value,
      REQUEST_TYPES.TRANSFER
    )
  );
  const pendingParticipation = computed(() =>
    requests.openOutgoing(
      conversationId.value,
      userId.value,
      REQUEST_TYPES.PARTICIPATION
    )
  );

  return {
    assignee,
    isUnassigned,
    isOwner,
    isManager,
    canReply,
    pendingTransfer,
    pendingParticipation,
  };
}
