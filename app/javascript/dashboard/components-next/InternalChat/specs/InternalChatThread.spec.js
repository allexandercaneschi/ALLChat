import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import InternalChatAPI from 'dashboard/api/internalChat';
import { useInternalChatStore } from 'dashboard/stores/internalChat';
import InternalChatThread from '../InternalChatThread.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: name =>
    ref(
      name === 'agents/getAgents'
        ? [
            { id: 1, name: 'Ana' },
            { id: 2, name: 'Bruno' },
          ]
        : { id: 1, name: 'Ana' }
    ),
}));

vi.mock('dashboard/api/internalChat', () => ({
  default: {
    markRead: vi.fn(),
    getMessages: vi.fn(),
    sendMessage: vi.fn(),
    sendHelpRequest: vi.fn(),
    search: vi.fn(),
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

const companyRoom = {
  id: 12,
  kind: 'company_room',
  name: 'ALL Tecnologias',
  posting_policy: 'everyone',
  can_post: true,
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
          emits: ['click'],
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
      expect(InternalChatAPI.sendMessage).toHaveBeenCalledWith(10, {
        content: 'oi Bruno',
        urgent: false,
        mentioned_user_ids: [],
      })
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
        team_id: undefined,
        content: 'socorro',
        conversation_id: undefined,
      })
    );
  });

  it('sends a help request to the whole team from a team room', async () => {
    InternalChatAPI.sendHelpRequest.mockResolvedValue({
      data: {
        id: 3,
        channel_id: 11,
        kind: 'help_request',
        content: 'alguém sabe?',
        sender: { id: 1 },
        created_at: 7,
      },
    });
    const { wrapper } = createThread(teamRoom);

    await wrapper.find('textarea').setValue('alguém sabe?');
    await buttonByLabel(wrapper, 'INTERNAL_CHAT.HELP.ASK_TEAM').trigger(
      'click'
    );

    await vi.waitFor(() =>
      expect(InternalChatAPI.sendHelpRequest).toHaveBeenCalledWith({
        recipient_id: undefined,
        team_id: 3,
        content: 'alguém sabe?',
        conversation_id: undefined,
      })
    );
  });

  it('sends an urgent message only when marked as urgent, and only in a direct chat', async () => {
    InternalChatAPI.sendMessage.mockResolvedValue({
      data: {
        id: 4,
        channel_id: 10,
        kind: 'text',
        content: 'agora',
        urgent: true,
        sender: { id: 1 },
        created_at: 8,
      },
    });
    const { wrapper } = createThread(directChannel);

    await buttonByLabel(wrapper, 'INTERNAL_CHAT.URGENT.LABEL').trigger('click');
    await wrapper.find('textarea').setValue('agora');
    await buttonByLabel(wrapper, 'INTERNAL_CHAT.SEND').trigger('click');

    await vi.waitFor(() =>
      expect(InternalChatAPI.sendMessage).toHaveBeenCalledWith(10, {
        content: 'agora',
        urgent: true,
        mentioned_user_ids: [],
      })
    );
    expect(
      createThread(teamRoom)
        .wrapper.find('button[data-label="INTERNAL_CHAT.URGENT.LABEL"]')
        .exists()
    ).toBe(false);
  });

  it('sends the attention nudge and blocks the button while the cooldown runs', async () => {
    InternalChatAPI.sendMessage.mockResolvedValue({
      data: {
        id: 5,
        channel_id: 10,
        kind: 'nudge',
        content: '',
        sender: { id: 1 },
        created_at: 9,
      },
    });
    const { wrapper } = createThread(directChannel);

    await buttonByLabel(wrapper, 'INTERNAL_CHAT.NUDGE.BUTTON').trigger('click');

    await vi.waitFor(() =>
      expect(InternalChatAPI.sendMessage).toHaveBeenCalledWith(10, {
        kind: 'nudge',
      })
    );
    await vi.waitFor(() =>
      expect(
        wrapper.find('button[data-label="INTERNAL_CHAT.NUDGE.WAIT"]').exists()
      ).toBe(true)
    );
    expect(
      wrapper.find('button[data-label="INTERNAL_CHAT.NUDGE.WAIT"]').element
        .disabled
    ).toBe(true);
  });

  it('sends the mentions that are still in the text', async () => {
    InternalChatAPI.sendMessage.mockResolvedValue({
      data: {
        id: 6,
        channel_id: 11,
        kind: 'text',
        content: '@Bruno olha',
        sender: { id: 1 },
        created_at: 10,
      },
    });
    const { wrapper } = createThread(teamRoom);

    await wrapper.find('[data-testid="mention-button"]').trigger('click');
    await wrapper
      .findAll('ul button')
      .find(button => button.text() === 'Bruno')
      .trigger('click');
    await wrapper.find('textarea').setValue('@Bruno olha');
    await buttonByLabel(wrapper, 'INTERNAL_CHAT.SEND').trigger('click');

    await vi.waitFor(() =>
      expect(InternalChatAPI.sendMessage).toHaveBeenCalledWith(11, {
        content: '@Bruno olha',
        urgent: false,
        mentioned_user_ids: [2],
      })
    );
  });

  describe('company room and posting policy', () => {
    it('lets everyone write in the company room, but offers no help request there', () => {
      const { wrapper } = createThread(companyRoom);

      expect(wrapper.find('textarea').exists()).toBe(true);
      expect(buttonByLabel(wrapper, 'INTERNAL_CHAT.ASK_HELP').exists()).toBe(
        false
      );
      expect(
        buttonByLabel(wrapper, 'INTERNAL_CHAT.HELP.ASK_TEAM').exists()
      ).toBe(false);
    });

    it('replaces the message box with a note when the room is restricted to administrators', () => {
      const { wrapper } = createThread({
        ...companyRoom,
        posting_policy: 'admins_only',
        can_post: false,
      });

      expect(wrapper.find('textarea').exists()).toBe(false);
      expect(wrapper.text()).toContain(
        'INTERNAL_CHAT.POSTING.ADMINS_ONLY_NOTE'
      );
    });

    it('says who can write when the room is restricted to administrators and supervisors', () => {
      const { wrapper } = createThread({
        ...teamRoom,
        posting_policy: 'admins_and_supervisors',
        can_post: false,
      });

      expect(wrapper.find('textarea').exists()).toBe(false);
      expect(wrapper.text()).toContain(
        'INTERNAL_CHAT.POSTING.ADMINS_AND_SUPERVISORS_NOTE'
      );
    });

    it('keeps the message box for who can write in a restricted room', () => {
      const { wrapper } = createThread({
        ...companyRoom,
        posting_policy: 'admins_only',
        can_post: true,
      });

      expect(wrapper.find('textarea').exists()).toBe(true);
    });
  });
});
