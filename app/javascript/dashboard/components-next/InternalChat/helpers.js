import { CHANNEL_KINDS } from 'dashboard/stores/internalChat';

// Name shown for a channel: the other person of a direct chat, the team name or the company name.
export const getChannelTitle = channel => {
  if (channel.kind === CHANNEL_KINDS.TEAM_ROOM) return channel.team?.name || '';
  if (channel.kind === CHANNEL_KINDS.COMPANY_ROOM) return channel.name || '';
  return channel.user?.name || '';
};

// Agents the current agent can start a direct chat with, filtered by name.
export const filterAgentsForChat = (agents, currentUserId, query) => {
  const search = query.trim().toLowerCase();
  return agents.filter(
    agent =>
      agent.id !== currentUserId && agent.name.toLowerCase().includes(search)
  );
};
