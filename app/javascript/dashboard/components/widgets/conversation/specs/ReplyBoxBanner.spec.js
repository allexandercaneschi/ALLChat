import { flushPromises, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Banner from 'dashboard/components/ui/Banner.vue';
import ReplyBoxBanner from '../ReplyBoxBanner.vue';
import ConversationApi from 'dashboard/api/inbox/conversation';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { assignAgent: vi.fn() },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const fetchForConversation = vi.fn();
vi.mock('dashboard/stores/conversationRequests', () => ({
  useConversationRequestsStore: () => ({ fetchForConversation }),
}));

vi.mock('dashboard/composables/useConversationOwnership', async () => {
  const { computed } = await import('vue');
  const { useMapGetter } = await import('dashboard/composables/store');
  return {
    useConversationOwnership: () => {
      const chat = useMapGetter('getSelectedChat');
      const isUnassigned = computed(
        () => chat.value?.meta?.assignee_type !== 'User'
      );
      return {
        assignee: computed(() => chat.value?.meta?.assignee),
        isUnassigned,
        isOwner: computed(() => chat.value?.meta?.assignee?.id === 7),
        isManager: computed(() => false),
        canReply: computed(() => chat.value?.meta?.assignee?.id === 7),
        pendingTransfer: computed(() => null),
        pendingParticipation: computed(() => null),
      };
    },
  };
});

describe('ReplyBoxBanner', () => {
  const currentUser = { id: 7 };

  it.each([false, true])(
    'only updates takeover after assignment succeeds (fails: %s)',
    async requestFails => {
      const setCurrentChatAssignee = vi.fn();
      const changeStatus = vi.fn();
      ConversationApi.assignAgent.mockReset();
      if (requestFails) {
        ConversationApi.assignAgent.mockRejectedValue(new Error('Failed'));
      } else {
        ConversationApi.assignAgent.mockResolvedValue({ data: currentUser });
      }
      const store = createStore({
        state: {
          chat: {
            id: 1,
            status: 'pending',
            meta: {
              assignee: { id: 3, name: 'Captain' },
              assignee_type: 'Captain::Assistant',
            },
          },
        },
        getters: {
          getSelectedChat: state => state.chat,
          getCurrentUser: () => currentUser,
        },
        actions: {
          setCurrentChatAssignee,
        },
        mutations: { CHANGE_CONVERSATION_STATUS: changeStatus },
      });
      const wrapper = shallowMount(ReplyBoxBanner, {
        global: {
          plugins: [store],
          mocks: {
            $t: key => key,
          },
        },
      });

      const banner = wrapper.findComponent(Banner);
      expect(banner.exists()).toBe(true);
      banner.vm.$emit('primaryAction');
      await flushPromises();

      expect(ConversationApi.assignAgent).toHaveBeenCalledWith({
        conversationId: 1,
        agentId: currentUser.id,
        assigneeType: 'User',
      });
      if (requestFails) {
        expect(setCurrentChatAssignee).not.toHaveBeenCalled();
        expect(changeStatus).not.toHaveBeenCalled();
        expect(wrapper.findComponent(Banner).exists()).toBe(true);
        return;
      }
      expect(changeStatus).toHaveBeenCalledWith(expect.anything(), {
        conversationId: 1,
        status: 'open',
        snoozedUntil: null,
      });
      expect(setCurrentChatAssignee).toHaveBeenCalledWith(expect.anything(), {
        conversationId: 1,
        assignee: currentUser,
        assigneeType: 'User',
      });
    }
  );

  it.each([
    [{}, 'CONVERSATION.UNASSIGNED_ASSIGN_TO_REPLY'],
    [
      { assignee: { id: 3, name: 'Pedro' }, assignee_type: 'User' },
      'CONVERSATION_REQUESTS.BANNER.OWNED_BY_OTHER',
    ],
    [{ assignee: { id: 7 }, assignee_type: 'User' }, null],
  ])(
    'shows the ownership banner without typing (%o)',
    (meta, expectedMessage) => {
      const store = createStore({
        state: { chat: { id: 1, status: 'open', meta } },
        getters: {
          getSelectedChat: state => state.chat,
          getCurrentUser: () => currentUser,
        },
      });
      const wrapper = shallowMount(ReplyBoxBanner, {
        global: { plugins: [store], mocks: { $t: key => key } },
      });

      const banner = wrapper.findComponent(Banner);
      if (!expectedMessage) {
        expect(banner.exists()).toBe(false);
        return;
      }
      expect(banner.props('bannerMessage')).toBe(expectedMessage);
    }
  );
});
