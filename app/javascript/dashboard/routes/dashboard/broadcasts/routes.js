import { frontendURL } from '../../../helper/URLHelper';
import BroadcastListsIndex from './pages/BroadcastListsIndex.vue';
import BroadcastListShow from './pages/BroadcastListShow.vue';

// ALLChat: broadcasts. Every user reaches the pages; the API only returns the
// lists the user is authorized on (administrators see all of them).
const meta = {
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/broadcasts/lists'),
    name: 'broadcast_lists_index',
    component: BroadcastListsIndex,
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/broadcasts/lists/:listId'),
    name: 'broadcast_lists_show',
    component: BroadcastListShow,
    meta,
  },
];
