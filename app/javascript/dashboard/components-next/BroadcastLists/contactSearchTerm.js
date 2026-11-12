// ALLChat: contacts keep phones as +55 + DDD + number, mobiles without the
// extra 9 (see GoogleContacts::PhoneNumber). A typed phone such as
// "(32) 99946-0230" is reduced to the digits stored, so the contact search,
// which matches part of the phone, finds it. Other text is searched as typed.
const PHONE_INPUT = /^[\d\s()+\-.]+$/;
const COUNTRY_CODE = '55';

export const contactSearchTerm = query => {
  const text = (query || '').trim();
  if (!PHONE_INPUT.test(text)) return text;

  let digits = text.replace(/\D/g, '');
  if (digits.length >= 12 && digits.startsWith(COUNTRY_CODE)) {
    digits = digits.slice(COUNTRY_CODE.length);
  }
  if (digits.length === 11 && digits[2] === '9') {
    digits = `${digits.slice(0, 2)}${digits.slice(3)}`;
  } else if (digits.length === 9 && digits[0] === '9') {
    digits = digits.slice(1);
  }
  return digits;
};
