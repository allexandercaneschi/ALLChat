import { CHANNEL_KINDS } from 'dashboard/stores/internalChat';

// Name shown for a channel: the other person of a direct chat or the team name of a room.
export const getChannelTitle = channel => {
  if (channel.kind === CHANNEL_KINDS.TEAM_ROOM) return channel.team?.name || '';
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
