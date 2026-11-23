import { mount } from '@vue/test-utils';
import InternalChatMessageBubble from '../InternalChatMessageBubble.vue';

const buildMessage = (overrides = {}) => ({
  id: 1,
  kind: 'text',
  content: 'Preciso de ajuda com o servidor',
  sender: { id: 2, name: 'Bruno' },
  created_at: 1700000000,
  ...overrides,
});

const createBubble = (props = {}) =>
  mount(InternalChatMessageBubble, {
    props: { message: buildMessage(), ...props },
  });

describe('InternalChatMessageBubble', () => {
  it('shows the message content', () => {
    expect(createBubble().text()).toContain('Preciso de ajuda com o servidor');
  });

  it('shows the sender name only when asked and for others', () => {
    expect(createBubble().text()).not.toContain('Bruno');
    expect(createBubble({ showSender: true }).text()).toContain('Bruno');
    expect(
      createBubble({ showSender: true, isOwn: true }).text()
    ).not.toContain('Bruno');
  });

  it('marks help requests', () => {
    const help = createBubble({
      message: buildMessage({ kind: 'help_request' }),
    });

    expect(help.text()).toContain('INTERNAL_CHAT.HELP_REQUEST');
    expect(createBubble().text()).not.toContain('INTERNAL_CHAT.HELP_REQUEST');
  });
});
