import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import InternalChatAPI from 'dashboard/api/internalChat';
import { useInternalChatStore } from 'dashboard/stores/internalChat';
import InternalChatThread from '../InternalChatThread.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref({ id: 1, name: 'Ana' }),
}));

vi.mock('dashboard/api/internalChat', () => ({
  default: {
    markRead: vi.fn(),
    getMessages: vi.fn(),
    sendMessage: vi.fn(),
    sendHelpRequest: vi.fn(),
  },
}));

const directChannel = {
  id: 10,
  kind: 'direct',
  user: { id: 2, name: 'Bruno' },
  unread_count: 0,
  last_activity_at: 1,
};

const teamRoom = {
  id: 11,
  kind: 'team_room',
  team: { id: 3, name: 'suporte' },
  unread_count: 0,
  last_activity_at: 1,
};

const createThread = channel => {
  const pinia = createPinia();
  setActivePinia(pinia);
  const store = useInternalChatStore();
  store.channels = { [channel.id]: channel };
  store.messages = { [channel.id]: [] };
  store.activeChannelId = channel.id;
  const wrapper = mount(InternalChatThread, {
    global: {
      plugins: [pinia],
      stubs: {
        Button: {
          props: ['label', 'disabled'],
          template:
            '<button :disabled="disabled" :data-label="label" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });
  return { wrapper, store };
};

const buttonByLabel = (wrapper, label) =>
  wrapper.find(`button[data-label="${label}"]`);

describe('InternalChatThread', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('marks the channel as being viewed while it is on screen', () => {
    const { wrapper, store } = createThread(directChannel);

    expect(store.viewingChannelId).toBe(10);
    wrapper.unmount();
    expect(store.viewingChannelId).toBeNull();
  });

  it('sends the typed message and clears the box', async () => {
    InternalChatAPI.sendMessage.mockResolvedValue({
      data: {
        id: 1,
        channel_id: 10,
        kind: 'text',
        content: 'oi Bruno',
        sender: { id: 1 },
        created_at: 5,
      },
    });
    const { wrapper } = createThread(directChannel);

    await wrapper.find('textarea').setValue('oi Bruno');
    await buttonByLabel(wrapper, 'INTERNAL_CHAT.SEND').trigger('click');
    await vi.waitFor(() =>
      expect(InternalChatAPI.sendMessage).toHaveBeenCalledWith(10, 'oi Bruno')
    );

    await vi.waitFor(() =>
      expect(wrapper.find('textarea').element.value).toBe('')
    );
  });

  it('does not send an empty message', async () => {
    const { wrapper } = createThread(directChannel);

    await buttonByLabel(wrapper, 'INTERNAL_CHAT.SEND').trigger('click');

    expect(InternalChatAPI.sendMessage).not.toHaveBeenCalled();
  });

  it('asks for help from the one person of a direct chat', async () => {
    InternalChatAPI.sendHelpRequest.mockResolvedValue({
      data: {
        id: 2,
        channel_id: 10,
        kind: 'help_request',
        content: 'socorro',
        sender: { id: 1 },
        created_at: 6,
      },
    });
    const { wrapper } = createThread(directChannel);

    await wrapper.find('textarea').setValue('socorro');
    await buttonByLabel(wrapper, 'INTERNAL_CHAT.ASK_HELP').trigger('click');

    await vi.waitFor(() =>
      expect(InternalChatAPI.sendHelpRequest).toHaveBeenCalledWith({
        recipient_id: 2,
        content: 'socorro',
        conversation_id: undefined,
      })
    );
  });

  it('offers no help request button in a team room, so it can never be a broadcast', () => {
    const { wrapper } = createThread(teamRoom);

    expect(buttonByLabel(wrapper, 'INTERNAL_CHAT.ASK_HELP').exists()).toBe(
      false
    );
  });
});
