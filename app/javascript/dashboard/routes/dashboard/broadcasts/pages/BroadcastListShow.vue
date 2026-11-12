<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import BroadcastListsAPI from 'dashboard/api/broadcastLists';
import ContactAPI from 'dashboard/api/contacts';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BroadcastListFormDialog from 'dashboard/components-next/BroadcastLists/BroadcastListFormDialog.vue';
import BroadcastListImportDialog from 'dashboard/components-next/BroadcastLists/BroadcastListImportDialog.vue';
import BroadcastListUsersDialog from 'dashboard/components-next/BroadcastLists/BroadcastListUsersDialog.vue';
import BroadcastMessageFormDialog from 'dashboard/components-next/BroadcastLists/BroadcastMessageFormDialog.vue';
import { deliveryPayload } from 'dashboard/components-next/BroadcastLists/broadcastSchedule';
import { contactSearchTerm } from 'dashboard/components-next/BroadcastLists/contactSearchTerm';

const CONTACTS_PER_PAGE = 25;
const SEARCH_DEBOUNCE_MS = 300;

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const listId = computed(() => route.params.listId);
const list = ref(null);
const contacts = ref([]);
const totalContacts = ref(0);
const currentPage = ref(1);
const searchQuery = ref('');
const isFetchingContacts = ref(true);
const isSaving = ref(false);

const contactOptions = ref([]);
const selectedContactId = ref('');

const formDialogRef = ref(null);
const usersDialogRef = ref(null);
const sendDialogRef = ref(null);
const importDialogRef = ref(null);
const deleteDialogRef = ref(null);

const goToLists = () => router.push({ name: 'broadcast_lists_index' });

const errorMessage = (error, fallbackKey) =>
  error?.response?.data?.message ||
  error?.response?.data?.error ||
  t(fallbackKey);

const fetchList = async () => {
  try {
    const { data } = await BroadcastListsAPI.show(listId.value);
    list.value = data;
  } catch {
    useAlert(t('BROADCAST_LISTS.FETCH_ERROR'));
    goToLists();
  }
};

const fetchContacts = async () => {
  isFetchingContacts.value = true;
  try {
    const { data } = await BroadcastListsAPI.getContacts(listId.value, {
      page: currentPage.value,
      q: searchQuery.value,
    });
    contacts.value = data.payload;
    totalContacts.value = data.meta.count;
  } finally {
    isFetchingContacts.value = false;
  }
};

const refresh = () => Promise.all([fetchList(), fetchContacts()]);

const onSearch = debounce(() => {
  currentPage.value = 1;
  fetchContacts();
}, SEARCH_DEBOUNCE_MS);

watch(searchQuery, onSearch);

const onPageChange = page => {
  currentPage.value = page;
  fetchContacts();
};

const contactLabel = contact =>
  [contact.name, contact.phone_number].filter(Boolean).join(' · ');

const toContactOptions = payload =>
  payload.map(contact => ({
    value: contact.id,
    label: contactLabel(contact),
  }));

// The picker opens with the first contacts so it is never empty before typing.
const loadFirstContacts = async () => {
  const { data } = await ContactAPI.get(1);
  contactOptions.value = toContactOptions(data.payload);
};

const searchContactsToAdd = debounce(async query => {
  const term = contactSearchTerm(query);
  if (!term) {
    await loadFirstContacts();
    return;
  }
  const { data } = await ContactAPI.search(term);
  contactOptions.value = toContactOptions(data.payload);
}, SEARCH_DEBOUNCE_MS);

const addContact = async contactId => {
  if (!contactId) return;
  try {
    const { data } = await BroadcastListsAPI.addContacts(listId.value, [
      contactId,
    ]);
    useAlert(
      data.added
        ? t('BROADCAST_LISTS.SHOW.ADDED')
        : t('BROADCAST_LISTS.SHOW.ALREADY')
    );
    await refresh();
  } catch (error) {
    useAlert(errorMessage(error, 'BROADCAST_LISTS.SHOW.ERROR'));
  } finally {
    selectedContactId.value = '';
  }
};

watch(selectedContactId, addContact);

const removeContact = async contact => {
  try {
    await BroadcastListsAPI.removeContact(listId.value, contact.id);
    useAlert(t('BROADCAST_LISTS.SHOW.REMOVED'));
    await refresh();
  } catch (error) {
    useAlert(errorMessage(error, 'BROADCAST_LISTS.SHOW.ERROR'));
  }
};

const updateList = async attributes => {
  isSaving.value = true;
  try {
    const { data } = await BroadcastListsAPI.update(listId.value, {
      broadcast_list: attributes,
    });
    list.value = data;
    formDialogRef.value?.close();
    useAlert(t('BROADCAST_LISTS.MESSAGES.UPDATED'));
  } catch (error) {
    useAlert(errorMessage(error, 'BROADCAST_LISTS.MESSAGES.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const updateUsers = async userIds => {
  isSaving.value = true;
  try {
    const { data } = await BroadcastListsAPI.updateUsers(listId.value, userIds);
    list.value = data;
    usersDialogRef.value?.close();
    useAlert(t('BROADCAST_LISTS.USERS.SAVED'));
  } catch (error) {
    useAlert(errorMessage(error, 'BROADCAST_LISTS.USERS.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const sendNow = async form => {
  isSaving.value = true;
  try {
    const { data } = await BroadcastListsAPI.sendNow(
      listId.value,
      deliveryPayload(form)
    );
    sendDialogRef.value?.close();
    useAlert(t('BROADCAST_MESSAGES.QUEUED', { count: data.queued }));
  } catch (error) {
    useAlert(errorMessage(error, 'BROADCAST_MESSAGES.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const importContacts = async content => {
  isSaving.value = true;
  try {
    const { data } = await BroadcastListsAPI.importContacts(
      listId.value,
      content
    );
    importDialogRef.value?.close();
    const summary = t('BROADCAST_LISTS.IMPORT.RESULT', {
      added: data.added,
      created: data.created,
      already: data.already_in_list,
    });
    const invalid = data.invalid_lines.length
      ? ` ${t('BROADCAST_LISTS.IMPORT.INVALID', { lines: data.invalid_lines.join(', ') })}`
      : '';
    useAlert(`${summary}${invalid}`);
    currentPage.value = 1;
    await refresh();
  } catch (error) {
    useAlert(errorMessage(error, 'BROADCAST_LISTS.IMPORT.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const deleteList = async () => {
  isSaving.value = true;
  try {
    await BroadcastListsAPI.delete(listId.value);
    useAlert(t('BROADCAST_LISTS.MESSAGES.DELETED'));
    goToLists();
  } catch (error) {
    useAlert(errorMessage(error, 'BROADCAST_LISTS.MESSAGES.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

onMounted(refresh);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="px-6">
      <div class="flex flex-col w-full max-w-5xl gap-3 py-5 mx-auto">
        <Button
          :label="t('BROADCAST_LISTS.SHOW.BACK')"
          icon="i-lucide-chevron-left"
          variant="link"
          color="slate"
          size="sm"
          class="self-start"
          @click="goToLists"
        />
        <div
          v-if="list"
          class="flex flex-wrap items-start justify-between w-full gap-3"
        >
          <div class="flex flex-col min-w-0 gap-1">
            <span class="text-heading-1 text-n-slate-12">{{ list.name }}</span>
            <span v-if="list.description" class="text-sm text-n-slate-11">
              {{ list.description }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{ t('BROADCAST_LISTS.LABEL', { label: list.label }) }} ·
              {{
                t('BROADCAST_LISTS.CONTACTS_COUNT', {
                  count: list.contacts_count,
                })
              }}
            </span>
          </div>
          <div v-if="list.can_manage" class="flex flex-wrap gap-2">
            <Button
              :label="t('BROADCAST_LISTS.USERS.BUTTON')"
              icon="i-lucide-users"
              variant="outline"
              color="slate"
              size="sm"
              @click="usersDialogRef?.open(list)"
            />
            <Button
              :label="t('BROADCAST_LISTS.SHOW.EDIT')"
              icon="i-lucide-pencil"
              variant="outline"
              color="slate"
              size="sm"
              @click="formDialogRef?.open(list)"
            />
            <Button
              :label="t('BROADCAST_LISTS.SHOW.DELETE')"
              icon="i-lucide-trash-2"
              variant="outline"
              color="ruby"
              size="sm"
              @click="deleteDialogRef?.open()"
            />
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <div class="flex-1 min-w-60">
            <Input
              v-model="searchQuery"
              :placeholder="t('BROADCAST_LISTS.SHOW.SEARCH')"
            />
          </div>
          <div class="w-72">
            <ComboBox
              v-model="selectedContactId"
              :options="contactOptions"
              :placeholder="t('BROADCAST_LISTS.SHOW.ADD_CONTACT')"
              :search-placeholder="t('BROADCAST_LISTS.SHOW.ADD_SEARCH')"
              :empty-state="t('BROADCAST_LISTS.SHOW.ADD_EMPTY')"
              use-api-results
              @search="searchContactsToAdd"
              @open="loadFirstContacts"
            />
          </div>
          <Button
            :label="t('BROADCAST_MESSAGES.QUICK_SEND')"
            icon="i-lucide-send"
            size="sm"
            :disabled="!list?.contacts_count"
            @click="sendDialogRef?.open()"
          />
          <Button
            :label="t('BROADCAST_LISTS.SHOW.IMPORT')"
            icon="i-lucide-file-up"
            variant="outline"
            color="slate"
            size="sm"
            @click="importDialogRef?.open()"
          />
        </div>
      </div>
    </header>
    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-5xl pb-4 mx-auto">
        <div
          v-if="isFetchingContacts"
          class="flex items-center justify-center py-10 text-n-slate-11"
        >
          <Spinner />
        </div>
        <p
          v-else-if="!contacts.length"
          class="py-10 text-base text-center text-n-slate-11"
        >
          {{
            searchQuery
              ? t('BROADCAST_LISTS.SHOW.NO_RESULTS')
              : t('BROADCAST_LISTS.SHOW.EMPTY')
          }}
        </p>
        <div
          v-else
          class="divide-y rounded-xl outline outline-1 outline-n-container bg-n-solid-2 divide-n-weak"
        >
          <div
            v-for="contact in contacts"
            :key="contact.id"
            class="flex items-center gap-3 px-5 py-3"
          >
            <Avatar
              :src="contact.thumbnail"
              :name="contact.name"
              :size="32"
              rounded-full
            />
            <div class="flex flex-col flex-1 min-w-0">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ contact.name }}
              </span>
              <span class="text-xs truncate text-n-slate-11">
                {{
                  [
                    contact.phone_number || t('BROADCAST_LISTS.SHOW.NO_PHONE'),
                    contact.email,
                  ]
                    .filter(Boolean)
                    .join(' · ')
                }}
              </span>
            </div>
            <Button
              v-tooltip="t('BROADCAST_LISTS.SHOW.REMOVE')"
              icon="i-lucide-user-minus"
              variant="ghost"
              color="slate"
              size="sm"
              @click="removeContact(contact)"
            />
          </div>
        </div>
      </div>
    </main>
    <footer v-if="totalContacts > CONTACTS_PER_PAGE" class="px-6 pb-4">
      <div class="w-full max-w-5xl mx-auto">
        <PaginationFooter
          :current-page="currentPage"
          :total-items="totalContacts"
          :items-per-page="CONTACTS_PER_PAGE"
          @update:current-page="onPageChange"
        />
      </div>
    </footer>
    <BroadcastListFormDialog
      ref="formDialogRef"
      :is-loading="isSaving"
      @submit="updateList"
    />
    <BroadcastMessageFormDialog
      ref="sendDialogRef"
      mode="send"
      :recipient-count="list?.contacts_count || 0"
      :is-loading="isSaving"
      @submit="sendNow"
    />
    <BroadcastListUsersDialog
      ref="usersDialogRef"
      :is-loading="isSaving"
      @submit="updateUsers"
    />
    <BroadcastListImportDialog
      ref="importDialogRef"
      :is-loading="isSaving"
      @submit="importContacts"
    />
    <Dialog
      v-if="list"
      ref="deleteDialogRef"
      type="alert"
      :title="t('BROADCAST_LISTS.DELETE.TITLE', { name: list.name })"
      :description="
        t('BROADCAST_LISTS.DELETE.DESCRIPTION', {
          label: list.label,
          count: list.contacts_count,
        })
      "
      :confirm-button-label="t('BROADCAST_LISTS.DELETE.CONFIRM')"
      :is-loading="isSaving"
      @confirm="deleteList"
    />
  </section>
</template>
