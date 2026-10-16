import { useAlert } from 'dashboard/composables';

// ALLChat: toast for the result of the `assignAgent` store action.
// Returns true when the conversation actually changed hands.
export const alertAssignmentResult = (result, t, successMessage) => {
  if (result?.request) {
    useAlert(
      t('CONVERSATION_REQUESTS.TRANSFER_SENT', {
        name: result.request.target.name,
      })
    );
    return false;
  }
  if (result?.error !== undefined) {
    useAlert(result.error || t('CONVERSATION_REQUESTS.ASSIGN_FAILED'));
    return false;
  }
  if (successMessage) useAlert(successMessage);
  return true;
};
