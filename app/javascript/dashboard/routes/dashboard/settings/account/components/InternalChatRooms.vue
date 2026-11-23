<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InternalChatAPI from 'dashboard/api/internalChat';
import SectionLayout from './SectionLayout.vue';

// ALLChat: settings of the internal chat rooms (the company room and one room per team).
// For now it sets who can send messages in each room.
const POSTING_POLICIES = ['everyone', 'admins_only', 'admins_and_supervisors'];
const POSTING_LABEL_KEYS = {
  everyone: 'INTERNAL_CHAT.POSTING.EVERYONE',
  admins_only: 'INTERNAL_CHAT.POSTING.ADMINS_ONLY',
  admins_and_supervisors: 'INTERNAL_CHAT.POSTING.ADMINS_AND_SUPERVISORS',
};

const { t } = useI18n();
const rooms = ref([]);
const savingRoomId = ref(null);
// Last policy saved on the server, to go back to it if saving fails.
const savedPolicies = {};

const load = async () => {
  try {
    const { data } = await InternalChatAPI.getRooms();
    rooms.value = data.payload;
    data.payload.forEach(room => {
      savedPolicies[room.id] = room.posting_policy;
    });
  } catch (error) {
    useAlert(t('INTERNAL_CHAT.ROOMS.LOAD_FAILED'));
  }
};

// The select is bound with v-model, so room.posting_policy already holds the new choice here.
const changePolicy = async room => {
  savingRoomId.value = room.id;
  try {
    await InternalChatAPI.updateRoom(room.id, {
      posting_policy: room.posting_policy,
    });
    savedPolicies[room.id] = room.posting_policy;
    useAlert(t('INTERNAL_CHAT.ROOMS.SUCCESS'));
  } catch (error) {
    room.posting_policy = savedPolicies[room.id];
    useAlert(t('INTERNAL_CHAT.ROOMS.FAILED'));
  } finally {
    savingRoomId.value = null;
  }
};

onMounted(load);
</script>

<template>
  <SectionLayout
    :title="t('INTERNAL_CHAT.ROOMS.TITLE')"
    :description="t('INTERNAL_CHAT.ROOMS.NOTE')"
    with-border
  >
    <ul class="flex flex-col divide-y divide-n-weak">
      <li
        v-for="room in rooms"
        :key="room.id"
        class="flex flex-wrap items-center justify-between gap-3 py-3"
      >
        <div class="flex items-center gap-3 min-w-0">
          <span
            :class="
              room.kind === 'company_room'
                ? 'i-lucide-building-2'
                : 'i-lucide-users'
            "
            class="size-5 text-n-slate-11"
          />
          <div class="flex flex-col min-w-0">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ room.name }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{
                room.kind === 'company_room'
                  ? t('INTERNAL_CHAT.ROOMS.COMPANY_NOTE')
                  : t('INTERNAL_CHAT.ROOMS.TEAM_NOTE')
              }}
              ·
              {{
                t('INTERNAL_CHAT.ROOMS.MEMBERS', { count: room.members_count })
              }}
            </span>
          </div>
        </div>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('INTERNAL_CHAT.ROOMS.POSTING_LABEL') }}
          <select
            v-model="room.posting_policy"
            class="!mb-0 text-sm"
            :disabled="savingRoomId === room.id"
            @change="changePolicy(room)"
          >
            <option
              v-for="policy in POSTING_POLICIES"
              :key="policy"
              :value="policy"
            >
              {{ t(POSTING_LABEL_KEYS[policy]) }}
            </option>
          </select>
        </label>
      </li>
    </ul>
  </SectionLayout>
</template>
