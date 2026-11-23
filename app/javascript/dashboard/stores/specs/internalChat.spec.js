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
    claimHelpRequest: vi.fn(),
    resolveHelpRequest: vi.fn(),
    search: vi.fn(),
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

    const result = await store.receiveMessage(buildMessage(), ME);

    expect(result).toEqual({ alert: true, attention: false });
    expect(store.channels[10].unread_count).toBe(1);
    expect(store.channels[10].last_message.content).toBe('oi');
    expect(store.messagesFor(10)).toHaveLength(1);
  });

  it('reads the message right away when the channel is on screen', async () => {
    store.upsertChannel(buildChannel());
    store.viewingChannelId = 10;

    const result = await store.receiveMessage(buildMessage(), ME);

    expect(result.alert).toBe(false);
    expect(store.channels[10].unread_count).toBe(0);
    expect(InternalChatAPI.markRead).toHaveBeenCalledWith(10);
  });

  it('does not count or alert for own messages arriving from another tab', async () => {
    store.upsertChannel(buildChannel());

    const result = await store.receiveMessage(
      buildMessage({ sender: { id: ME }, kind: 'nudge', urgent: true }),
      ME
    );

    expect(result).toEqual({ alert: false, attention: false });
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

    const result = await store.receiveMessage(buildMessage(), ME);

    expect(InternalChatAPI.getChannels).toHaveBeenCalled();
    expect(result.alert).toBe(true);
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

  describe('attention', () => {
    beforeEach(() => store.upsertChannel(buildChannel()));

    it.each([
      ['a nudge', { kind: 'nudge' }],
      ['an urgent message', { urgent: true }],
      ['a mention of the agent', { mentioned_user_ids: [ME] }],
    ])(
      'asks to call attention for %s, even with the channel on screen',
      async (_name, overrides) => {
        store.viewingChannelId = 10;

        const result = await store.receiveMessage(buildMessage(overrides), ME);

        expect(result.attention).toBe(true);
      }
    );

    it('does not call attention for a mention of someone else', async () => {
      const result = await store.receiveMessage(
        buildMessage({ mentioned_user_ids: [BRUNO] }),
        ME
      );

      expect(result.attention).toBe(false);
    });
  });

  describe('nudge', () => {
    beforeEach(() => store.upsertChannel(buildChannel()));

    it('starts the cooldown after sending', async () => {
      InternalChatAPI.sendMessage.mockResolvedValue({
        data: buildMessage({ kind: 'nudge', sender: { id: ME } }),
      });

      await store.sendNudge(10);

      expect(InternalChatAPI.sendMessage).toHaveBeenCalledWith(10, {
        kind: 'nudge',
      });
      expect(store.nudgeAvailableAt[10]).toBeGreaterThan(Date.now() + 50000);
    });

    it('waits the time the server says when it is too soon', async () => {
      InternalChatAPI.sendMessage.mockRejectedValue({
        response: { status: 429, data: { retry_after: 20 } },
      });

      await expect(store.sendNudge(10)).rejects.toBeDefined();

      const wait = store.nudgeAvailableAt[10] - Date.now();
      expect(wait).toBeGreaterThan(15000);
      expect(wait).toBeLessThanOrEqual(20000);
    });
  });

  describe('help requests', () => {
    it('sends a request to the whole team', async () => {
      store.upsertChannel(buildChannel({ id: 11, kind: 'team_room' }));
      InternalChatAPI.sendHelpRequest.mockResolvedValue({
        data: buildMessage({ channel_id: 11, kind: 'help_request' }),
      });

      await store.sendHelpRequest({ teamId: 3, content: 'ajuda' });

      expect(InternalChatAPI.sendHelpRequest).toHaveBeenCalledWith({
        recipient_id: undefined,
        team_id: 3,
        content: 'ajuda',
        conversation_id: undefined,
      });
    });

    it('takes a request, replaces it and opens the direct conversation', async () => {
      const request = buildMessage({
        id: 5,
        channel_id: 11,
        kind: 'help_request',
      });
      store.upsertChannel(buildChannel({ id: 11, kind: 'team_room' }));
      store.messages = { 11: [request] };
      InternalChatAPI.claimHelpRequest.mockResolvedValue({
        data: {
          message: { ...request, claimed_by: { id: ME, name: 'Ana' } },
          channel_id: 10,
          joined_conversation: true,
        },
      });
      InternalChatAPI.getChannels.mockResolvedValue({
        data: { payload: [buildChannel({ id: 10 }), buildChannel({ id: 11 })] },
      });
      InternalChatAPI.getMessages.mockResolvedValue({
        data: { payload: [], meta: { has_more: false } },
      });

      await store.claimHelpRequest(request);

      expect(InternalChatAPI.claimHelpRequest).toHaveBeenCalledWith(11, 5);
      expect(store.messagesFor(11)[0].claimed_by.id).toBe(ME);
      expect(store.activeChannelId).toBe(10);
    });

    it('updates a message changed by someone else', () => {
      store.messages = { 11: [buildMessage({ id: 5, channel_id: 11 })] };

      store.replaceMessage(
        buildMessage({ id: 5, channel_id: 11, resolved_at: 99 })
      );

      expect(store.messagesFor(11)[0].resolved_at).toBe(99);
    });
  });

  describe('search', () => {
    it('searches in all conversations or in one', async () => {
      InternalChatAPI.search.mockResolvedValue({
        data: { payload: [buildMessage()], meta: { has_more: false } },
      });

      await store.search({ query: 'senha' });
      await store.search({ query: 'senha', channelId: 10, beforeId: 4 });

      expect(InternalChatAPI.search).toHaveBeenNthCalledWith(1, {
        q: 'senha',
        channel_id: undefined,
        before_id: undefined,
      });
      expect(InternalChatAPI.search).toHaveBeenNthCalledWith(2, {
        q: 'senha',
        channel_id: 10,
        before_id: 4,
      });
    });
  });
});
