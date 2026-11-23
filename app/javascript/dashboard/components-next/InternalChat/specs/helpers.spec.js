import { getChannelTitle, filterAgentsForChat } from '../helpers';

describe('InternalChat helpers', () => {
  describe('getChannelTitle', () => {
    it('returns the other person for a direct channel', () => {
      const channel = { kind: 'direct', user: { name: 'Bruno' } };
      expect(getChannelTitle(channel)).toBe('Bruno');
    });

    it('returns the company name for the company room', () => {
      const channel = { kind: 'company_room', name: 'ALL Tecnologias' };
      expect(getChannelTitle(channel)).toBe('ALL Tecnologias');
    });

    it('returns the team name for a team room', () => {
      const channel = { kind: 'team_room', team: { name: 'suporte' } };
      expect(getChannelTitle(channel)).toBe('suporte');
    });
  });

  describe('filterAgentsForChat', () => {
    const agents = [
      { id: 1, name: 'Ana' },
      { id: 2, name: 'Bruno' },
      { id: 3, name: 'Brenda' },
    ];

    it('leaves the current agent out', () => {
      expect(filterAgentsForChat(agents, 1, '').map(a => a.id)).toEqual([2, 3]);
    });

    it('filters by name ignoring case and spaces around', () => {
      expect(filterAgentsForChat(agents, 1, ' BRU ').map(a => a.id)).toEqual([
        2,
      ]);
    });
  });
});
