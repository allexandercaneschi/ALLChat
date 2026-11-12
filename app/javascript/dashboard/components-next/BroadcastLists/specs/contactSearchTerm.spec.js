import { contactSearchTerm } from '../contactSearchTerm';

describe('contactSearchTerm', () => {
  it('drops the country code, the extra 9 and formatting from phones', () => {
    expect(contactSearchTerm('+55 (32) 99946-0230')).toBe('3299460230');
    expect(contactSearchTerm('32 99946-0230')).toBe('3299460230');
    expect(contactSearchTerm('99946-0230')).toBe('99460230');
    expect(contactSearchTerm('9460-230')).toBe('9460230');
  });

  it('keeps names as typed', () => {
    expect(contactSearchTerm(' Alan Teixeira ')).toBe('Alan Teixeira');
    expect(contactSearchTerm('Racional 2')).toBe('Racional 2');
  });
});
