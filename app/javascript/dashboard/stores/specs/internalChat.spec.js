import { setActivePinia, createPinia } from 'pinia';
import InternalChatAPI from 'dashboard/api/internalChat';
import { useInternalChatStore } from '../internalChat';

vi.mock('dashboard/api/internalChat', () => ({
  default: {
    getChannels: vi.fn(),
    openChannel: vi.fn(),
    markRead: vi.fn(),
    getMessages: vi.fn(),
    sendMessage: vi.fn(),
    sendHelpRequest: vi.fn(),
  },
}));

const ME = 1;
const BRUNO = 2;

const buildChannel = (overrides = {}) => ({
  id: 10,
  kind: 'direct',
  unread_count: 0,
  last_activity_at: 100,
  last_message: null,
  ...overrides,
});

const buildMessage = (overrides = {}) => ({
  id: 1,
  channel_id: 10,
  kind: 'text',
  content: 'oi',
  sender: { id: BRUNO },
  created_at: 200,
  ...overrides,
});

describe('internalChat store', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    InternalChatAPI.markRead.mockResolvedValue({});
    store = useInternalChatStore();
  });

  it('loads the channels and sums the unread count', async () => {
    InternalChatAPI.getChannels.mockResolvedValue({
      data: {
        payload: [
          buildChannel({ id: 10, unread_count: 2 }),
          buildChannel({ id: 11, unread_count: 1, last_activity_at: 300 }),
        ],
      },
    });

    await store.fetchChannels();

    expect(store.totalUnread).toBe(3);
    expect(store.channelList.map(channel => channel.id)).toEqual([11, 10]);
    expect(store.hasLoadedChannels).toBe(true);
  });

  it('counts a message from someone else as unread and asks to alert', async () => {
    store.upsertChannel(buildChannel());

    const shouldAlert = await store.receiveMessage(buildMessage(), ME);

    expect(shouldAlert).toBe(true);
    expect(store.channels[10].unread_count).toBe(1);
    expect(store.channels[10].last_message.content).toBe('oi');
    expect(store.messagesFor(10)).toHaveLength(1);
  });

  it('reads the message right away when the channel is on screen', async () => {
    store.upsertChannel(buildChannel());
    store.viewingChannelId = 10;

    const shouldAlert = await store.receiveMessage(buildMessage(), ME);

    expect(shouldAlert).toBe(false);
    expect(store.channels[10].unread_count).toBe(0);
    expect(InternalChatAPI.markRead).toHaveBeenCalledWith(10);
  });

  it('does not count or alert for own messages arriving from another tab', async () => {
    store.upsertChannel(buildChannel());

    const shouldAlert = await store.receiveMessage(
      buildMessage({ sender: { id: ME } }),
      ME
    );

    expect(shouldAlert).toBe(false);
    expect(store.channels[10].unread_count).toBe(0);
  });

  it('ignores the same message delivered twice', async () => {
    store.upsertChannel(buildChannel());

    await store.receiveMessage(buildMessage(), ME);
    await store.receiveMessage(buildMessage(), ME);

    expect(store.messagesFor(10)).toHaveLength(1);
  });

  it('reloads the channels when a message arrives from an unknown channel', async () => {
    InternalChatAPI.getChannels.mockResolvedValue({
      data: { payload: [buildChannel({ unread_count: 1 })] },
    });

    const shouldAlert = await store.receiveMessage(buildMessage(), ME);

    expect(InternalChatAPI.getChannels).toHaveBeenCalled();
    expect(shouldAlert).toBe(true);
    expect(store.channels[10]).toBeDefined();
  });

  it('opens a direct channel, loads its messages and marks it as read', async () => {
    InternalChatAPI.openChannel.mockResolvedValue({
      data: buildChannel({ unread_count: 3 }),
    });
    InternalChatAPI.getMessages.mockResolvedValue({
      data: { payload: [buildMessage()], meta: { has_more: false } },
    });

    await store.openDirect(BRUNO);

    expect(InternalChatAPI.openChannel).toHaveBeenCalledWith({
      kind: 'direct',
      user_id: BRUNO,
    });
    expect(store.activeChannelId).toBe(10);
    expect(store.messagesFor(10)).toHaveLength(1);
    expect(store.channels[10].unread_count).toBe(0);
  });

  it('prepends older messages when paging backwards', async () => {
    store.messages = { 10: [buildMessage({ id: 5 })] };
    InternalChatAPI.getMessages.mockResolvedValue({
      data: {
        payload: [buildMessage({ id: 3 }), buildMessage({ id: 4 })],
        meta: { has_more: true },
      },
    });

    await store.fetchMessages(10, 5);

    expect(InternalChatAPI.getMessages).toHaveBeenCalledWith(10, {
      before_id: 5,
    });
    expect(store.messagesFor(10).map(message => message.id)).toEqual([3, 4, 5]);
    expect(store.hasMoreMessages[10]).toBe(true);
  });

  it('sends a help request to one recipient only', async () => {
    store.upsertChannel(buildChannel());
    InternalChatAPI.sendHelpRequest.mockResolvedValue({
      data: buildMessage({ kind: 'help_request', sender: { id: ME } }),
    });

    await store.sendHelpRequest({
      recipientId: BRUNO,
      content: 'ajuda',
      conversationId: 7,
    });

    expect(InternalChatAPI.sendHelpRequest).toHaveBeenCalledWith({
      recipient_id: BRUNO,
      content: 'ajuda',
      conversation_id: 7,
    });
    expect(store.channels[10].last_message.kind).toBe('help_request');
  });
});
