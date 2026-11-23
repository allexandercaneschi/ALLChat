import { flushPromises, mount } from '@vue/test-utils';
import InternalChatAPI from 'dashboard/api/internalChat';
import InternalChatRooms from '../InternalChatRooms.vue';

vi.mock('dashboard/api/internalChat', () => ({
  default: { getRooms: vi.fn(), updateRoom: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// A new list for each test: the component edits the rooms it receives.
const buildRooms = () => [
  {
    id: 1,
    kind: 'company_room',
    name: 'ALL Tecnologias',
    team_id: null,
    posting_policy: 'everyone',
    members_count: 12,
  },
  {
    id: 2,
    kind: 'team_room',
    name: 'suporte',
    team_id: 7,
    posting_policy: 'admins_only',
    members_count: 4,
  },
];

const createSettings = async () => {
  const wrapper = mount(InternalChatRooms, {
    global: {
      stubs: { SectionLayout: { template: '<section><slot /></section>' } },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('InternalChatRooms settings', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    InternalChatAPI.getRooms.mockResolvedValue({
      data: { payload: buildRooms() },
    });
  });

  it('lists the company room and the team rooms with their current policy', async () => {
    const wrapper = await createSettings();

    const selects = wrapper.findAll('select');
    expect(wrapper.text()).toContain('ALL Tecnologias');
    expect(wrapper.text()).toContain('suporte');
    expect(selects.map(select => select.element.value)).toEqual([
      'everyone',
      'admins_only',
    ]);
  });

  it('offers the three policies', async () => {
    const wrapper = await createSettings();

    expect(
      wrapper
        .find('select')
        .findAll('option')
        .map(option => option.element.value)
    ).toEqual(['everyone', 'admins_only', 'admins_and_supervisors']);
  });

  it('saves the policy chosen for a room', async () => {
    InternalChatAPI.updateRoom.mockResolvedValue({ data: {} });
    const wrapper = await createSettings();

    await wrapper.find('select').setValue('admins_and_supervisors');

    expect(InternalChatAPI.updateRoom).toHaveBeenCalledWith(1, {
      posting_policy: 'admins_and_supervisors',
    });
  });

  it('goes back to the previous policy when saving fails', async () => {
    InternalChatAPI.updateRoom.mockRejectedValue(new Error('boom'));
    const wrapper = await createSettings();

    await wrapper.find('select').setValue('admins_only');
    await flushPromises();

    expect(wrapper.find('select').element.value).toBe('everyone');
  });
});
