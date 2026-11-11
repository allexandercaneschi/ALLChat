// ALLChat: preview of the label a broadcast list gets, mirroring
// BroadcastList.label_title_for (Rails String#parameterize).
export const LABEL_PREFIX = 'lista-';

export const labelTitleFor = name => {
  const slug = (name || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/-{2,}/g, '-')
    .replace(/^-|-$/g, '');
  return slug ? `${LABEL_PREFIX}${slug}` : '';
};
