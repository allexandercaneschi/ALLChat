import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createPinia, setActivePinia } from 'pinia';
import { useConversationOwnership } from '../useConversationOwnership';
import { useConversationRequestsStore } from 'dashboard/stores/conversationRequests';

let permissions = [];
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    checkPermissions: required => required.some(p => permissions.includes(p)),
  }),
}));

const ME = { id: 7, name: 'Me' };
const PEDRO = { id: 3, name: 'Pedro' };
const future = () => Math.floor(Date.now() / 1000) + 600;

const mountWith = meta => {
  const pinia = createPinia();
  setActivePinia(pinia);
  const store = createStore({
    getters: {
      getSelectedChat: () => ({ id: 42, meta }),
      getCurrentUser: () => ME,
    },
  });
  let result;
  mount(
    defineComponent({
      setup() {
        result = useConversationOwnership();
        return () => h('div');
      },
    }),
    { global: { plugins: [store, pinia] } }
  );
  return result;
};

const request = attrs => ({
  id: 1,
  conversation_id: 42,
  status: 'pending',
  expires_at: future(),
  created_at: 1,
  requester: ME,
  target: PEDRO,
  ...attrs,
});

describe('useConversationOwnership', () => {
  beforeEach(() => {
    permissions = ['agent'];
  });

  it('locks unassigned conversations for everyone, managers included', () => {
    permissions = ['administrator'];
    const ownership = mountWith({});
    expect(ownership.isUnassigned.value).toBe(true);
    expect(ownership.canReply.value).toBe(false);
  });

  it('lets the assignee reply', () => {
    const ownership = mountWith({ assignee: ME, assignee_type: 'User' });
    expect(ownership.canReply.value).toBe(true);
  });

  it("locks another agent's conversation for a plain agent", () => {
    const ownership = mountWith({ assignee: PEDRO, assignee_type: 'User' });
    expect(ownership.canReply.value).toBe(false);
  });

  it.each(['administrator', 'supervisor'])(
    "lets a %s reply in another agent's conversation",
    role => {
      permissions = [role];
      const ownership = mountWith({ assignee: PEDRO, assignee_type: 'User' });
      expect(ownership.canReply.value).toBe(true);
    }
  );

  it('lets an agent reply once the assignee accepted the participation', () => {
    const ownership = mountWith({ assignee: PEDRO, assignee_type: 'User' });
    useConversationRequestsStore().upsert(
      request({ request_type: 'participation', status: 'accepted' })
    );
    expect(ownership.canReply.value).toBe(true);
  });

  it('exposes the pending requests made by the current agent', () => {
    const ownership = mountWith({ assignee: PEDRO, assignee_type: 'User' });
    useConversationRequestsStore().upsert(
      request({ request_type: 'participation' })
    );
    expect(ownership.pendingParticipation.value.id).toBe(1);
    expect(ownership.pendingTransfer.value).toBeUndefined();
  });
});
