import { labelTitleFor } from '../labelTitle';

describe('labelTitleFor', () => {
  it('builds the list label like Rails parameterize', () => {
    expect(labelTitleFor('Clientes Tecmar')).toBe('lista-clientes-tecmar');
    expect(labelTitleFor('Dia das Mães / Promoção')).toBe(
      'lista-dia-das-maes-promocao'
    );
  });

  it('returns nothing for an empty name', () => {
    expect(labelTitleFor('  ')).toBe('');
  });
});
