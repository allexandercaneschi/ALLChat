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

  describe('help request actions', () => {
    const helpRequest = overrides =>
      buildMessage({ kind: 'help_request', ...overrides });
    const stubs = {
      Button: {
        props: ['label'],
        emits: ['click'],
        template: '<button :data-label="label" @click="$emit(\'click\')" />',
      },
    };
    const create = (props = {}) =>
      mount(InternalChatMessageBubble, {
        props: { message: helpRequest(), currentUserId: 1, ...props },
        global: { stubs },
      });

    it('lets a colleague take an open request', async () => {
      const bubble = create();

      await bubble
        .find('[data-label="INTERNAL_CHAT.HELP.CLAIM"]')
        .trigger('click');

      expect(bubble.emitted('claim')).toHaveLength(1);
      expect(bubble.text()).toContain('INTERNAL_CHAT.HELP.STATUS_OPEN');
    });

    it('does not let who asked take their own request, but lets them resolve it', () => {
      const bubble = create({ isOwn: true });

      expect(
        bubble.find('[data-label="INTERNAL_CHAT.HELP.CLAIM"]').exists()
      ).toBe(false);
      expect(
        bubble.find('[data-label="INTERNAL_CHAT.HELP.RESOLVE"]').exists()
      ).toBe(true);
    });

    it('shows who took it and lets only them or the requester resolve it', () => {
      const taken = helpRequest({ claimed_by: { id: 1, name: 'Ana' } });

      const byTaker = create({ message: taken });
      expect(
        byTaker.find('[data-label="INTERNAL_CHAT.HELP.CLAIM"]').exists()
      ).toBe(false);
      expect(
        byTaker.find('[data-label="INTERNAL_CHAT.HELP.RESOLVE"]').exists()
      ).toBe(true);

      const byOther = create({ message: taken, currentUserId: 9 });
      expect(
        byOther.find('[data-label="INTERNAL_CHAT.HELP.RESOLVE"]').exists()
      ).toBe(false);
    });

    it('has no actions once resolved or in audit mode', () => {
      const resolved = create({ message: helpRequest({ resolved_at: 5 }) });
      expect(resolved.find('button').exists()).toBe(false);
      expect(resolved.text()).toContain('INTERNAL_CHAT.HELP.STATUS_RESOLVED');

      expect(create({ readOnly: true }).find('button').exists()).toBe(false);
    });
  });

  it('shows a nudge as a short line and an urgent message with a badge', () => {
    expect(
      createBubble({
        message: buildMessage({ kind: 'nudge', content: '' }),
      }).text()
    ).toContain('INTERNAL_CHAT.NUDGE.FROM_OTHER');
    expect(
      createBubble({ message: buildMessage({ urgent: true }) }).text()
    ).toContain('INTERNAL_CHAT.URGENT.BADGE');
  });
});
