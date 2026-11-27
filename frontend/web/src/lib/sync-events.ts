export interface SyncEventPayload {
  type?: string;
  scope?: string;
  conversationId?: string;
  messageId?: string;
  at?: number;
}

export interface SyncBatch {
  scopes: Set<string>;
  conversationIds: Set<string>;
  messageIdsByConversation: Map<string, Set<string>>;
  wildcardMessageConversations: Set<string>;
  hasGlobalWildcardMessage: boolean;
}

export interface SyncRoutingContext {
  selectedConversationId?: string | null;
  isSearchingMessages: boolean;
  isHistoryReady: boolean;
  favoritesOpen: boolean;
  filesOpen: boolean;
  devicesOpen: boolean;
  settingsOpen: boolean;
}

export type SelectedHistoryAction =
  { type: 'none' } | { type: 'refreshLatest' } | { type: 'fetchMessages'; messageIds: string[] };

export interface SyncActionPlan {
  refreshConversations: boolean;
  selectedHistory: SelectedHistoryAction;
  refreshFavorites: boolean;
  refreshFiles: boolean;
  refreshDevices: boolean;
  refreshSettings: boolean;
}

export function parseSseFrames(buffer: string): { events: SyncEventPayload[]; rest: string } {
  const normalized = buffer.replace(/\r\n/g, '\n');
  const frames = normalized.split('\n\n');
  const rest = frames.pop() ?? '';
  const events: SyncEventPayload[] = [];
  for (const frame of frames) {
    if (!frame.trim()) continue;
    let eventName = '';
    const dataLines: string[] = [];
    for (const line of frame.split('\n')) {
      if (line.startsWith(':')) continue;
      if (line.startsWith('event:')) {
        eventName = line.slice(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.push(line.slice(5).trimStart());
      }
    }
    if ((eventName === '' || eventName === 'sync') && dataLines.length > 0) {
      try {
        const parsed = JSON.parse(dataLines.join('\n')) as SyncEventPayload;
        if (parsed && typeof parsed === 'object' && parsed.type === 'invalidate') {
          events.push(parsed);
        }
      } catch {
        // Ignore malformed payloads instead of crashing the stream loop.
      }
    }
  }
  return { events, rest };
}

export function createSyncBatch(): SyncBatch {
  return {
    scopes: new Set(),
    conversationIds: new Set(),
    messageIdsByConversation: new Map(),
    wildcardMessageConversations: new Set(),
    hasGlobalWildcardMessage: false,
  };
}

export function addSyncEventToBatch(batch: SyncBatch, event: SyncEventPayload): void {
  const scope = event.scope;
  if (!scope) return;
  batch.scopes.add(scope);
  if (event.conversationId) batch.conversationIds.add(event.conversationId);
  if (scope === 'messages') {
    if (event.conversationId) {
      if (event.messageId) {
        let ids = batch.messageIdsByConversation.get(event.conversationId);
        if (!ids) {
          ids = new Set();
          batch.messageIdsByConversation.set(event.conversationId, ids);
        }
        ids.add(event.messageId);
      } else {
        batch.wildcardMessageConversations.add(event.conversationId);
      }
    } else {
      batch.hasGlobalWildcardMessage = true;
    }
  }
}

export function planSyncActions(batch: SyncBatch, ctx: SyncRoutingContext): SyncActionPlan {
  const { scopes, conversationIds, messageIdsByConversation, wildcardMessageConversations } = batch;
  const refreshConversations = scopes.has('conversations');
  const selectedId = ctx.selectedConversationId ?? null;

  let selectedHistory: SelectedHistoryAction = { type: 'none' };
  if (selectedId) {
    const selectedConversationInvalidated = refreshConversations && conversationIds.has(selectedId);
    const hasWildcardForSelected =
      batch.hasGlobalWildcardMessage || wildcardMessageConversations.has(selectedId);
    const selectedMessageIds = messageIdsByConversation.get(selectedId);
    const hasMessageEventForSelected =
      hasWildcardForSelected || (selectedMessageIds !== undefined && selectedMessageIds.size > 0);

    if (hasWildcardForSelected) {
      selectedHistory = { type: 'refreshLatest' };
    } else if (hasMessageEventForSelected) {
      if (
        !ctx.isSearchingMessages &&
        ctx.isHistoryReady &&
        selectedMessageIds &&
        selectedMessageIds.size <= 3
      ) {
        selectedHistory = { type: 'fetchMessages', messageIds: [...selectedMessageIds] };
      } else {
        selectedHistory = { type: 'refreshLatest' };
      }
    } else if (selectedConversationInvalidated) {
      selectedHistory = { type: 'refreshLatest' };
    }
  }

  const refreshFavorites = ctx.favoritesOpen && scopes.has('favorites');
  const refreshFiles =
    ctx.filesOpen &&
    (scopes.has('messages') || scopes.has('conversations') || scopes.has('settings'));
  const refreshDevices = ctx.devicesOpen && scopes.has('devices');
  const refreshSettings = ctx.settingsOpen && scopes.has('settings');

  return {
    refreshConversations,
    selectedHistory,
    refreshFavorites,
    refreshFiles,
    refreshDevices,
    refreshSettings,
  };
}
