import {
  ChevronLeft,
  ChevronRight,
  FolderOpen,
  LogOut,
  MessageSquare,
  Pencil,
  Pin,
  Plus,
  Search,
  Settings,
  Star,
  Trash2,
} from 'lucide-react';
import { ActionMenu } from '@/components/ui/action-menu';
import { BrandIcon } from '@/components/ui/brand-icon';
import { Button } from '@/components/ui/button';
import { HighlightText } from '@/components/ui/highlight-text';
import { ConversationContextMenu } from '@/components/chat/conversation-context-menu';
import { SyncStatus } from '@/components/layout/sync-status';
import type { Conversation, Page } from '@/services/conversations';

export function ConversationSidebar({
  hidden,
  userName,
  conversations,
  selectedId,
  listLoading,
  search,
  query,
  page,
  busy,
  pinBusy,
  connected,
  lastSyncedAt,
  onSearchChange,
  onPageChange,
  onSelect,
  onCreateConversation,
  onOpenSettings,
  onOpenFavorites,
  onOpenFiles,
  onTogglePin,
  onOpenDialog,
  onRetrySync,
  onLogout,
}: {
  hidden: boolean;
  userName: string;
  conversations: Page<Conversation>;
  selectedId?: string;
  listLoading: boolean;
  search: string;
  query: string;
  page: number;
  busy: boolean;
  pinBusy: boolean;
  connected: boolean;
  lastSyncedAt: number | null;
  onSearchChange: (value: string) => void;
  onPageChange: (nextPage: number) => void;
  onSelect: (conversation: Conversation) => void;
  onCreateConversation: () => void;
  onOpenSettings: () => void;
  onOpenFavorites: () => void;
  onOpenFiles: () => void;
  onTogglePin: (conversation: Conversation) => void;
  onOpenDialog: (kind: 'rename' | 'delete', target: Conversation) => void;
  onRetrySync: () => void;
  onLogout: () => void;
}) {
  return (
    <aside className={`conversation-pane ${hidden ? 'mobile-hidden' : ''}`}>
      <div className="workspace-brand">
        <div className="brand desktop-brand">
          <BrandIcon size={28} />
          SyncBox
        </div>
        <h1 className="mobile-list-title">消息列表</h1>
        <div className="workspace-header-actions">
          <button
            className="icon-btn desktop-settings-entry"
            aria-label="打开设置"
            title="设置"
            onClick={onOpenSettings}
          >
            <Settings size={19} />
          </button>
          <Button
            variant="ghost"
            size="icon"
            className="sidebar-create"
            aria-label="创建会话"
            title="新建会话"
            onClick={onCreateConversation}
          >
            <Plus size={22} />
          </Button>
        </div>
      </div>
      <div className="sidebar-search-row">
        <label className="search-box">
          <Search size={16} />
          <input
            aria-label="搜索会话、消息、批注或文件名"
            placeholder="搜索"
            value={search}
            onChange={(e) => onSearchChange(e.target.value)}
          />
        </label>
      </div>
      <div className="sidebar-intro">
        <h2>会话</h2>
        <div className="sidebar-actions">
          <button className="favorites-entry" aria-label="查看收藏" onClick={onOpenFavorites}>
            <Star size={14} />
            收藏
          </button>
          <button className="favorites-entry" aria-label="查看文件" onClick={onOpenFiles}>
            <FolderOpen size={14} />
            文件
          </button>
        </div>
      </div>
      <div className="conversation-list" aria-busy={listLoading}>
        {listLoading && (
          <p className="list-loading" role="status">
            正在加载会话…
          </p>
        )}
        {!listLoading &&
          conversations.items.map((c) => (
            <ConversationContextMenu
              key={c.id}
              conversation={c}
              disabled={busy || pinBusy}
              onPin={() => onTogglePin(c)}
              onRename={() => onOpenDialog('rename', c)}
              onDelete={() => onOpenDialog('delete', c)}
            >
              <div
                className={`conversation-row-shell ${selectedId === c.id ? 'selected' : ''} ${c.isPinned ? 'pinned' : ''}`}
              >
                <button
                  onClick={() => onSelect(c)}
                  className={`conversation-row ${selectedId === c.id ? 'active' : ''}`}
                >
                  <span className="conversation-text">
                    <span className="conversation-title">
                      {c.isPinned && (
                        <span className="conversation-pin" title="已置顶">
                          <Pin size={12} fill="currentColor" />
                        </span>
                      )}
                      <span className="conversation-name">
                        <HighlightText text={c.title} query={query} />
                      </span>
                      <time>
                        {new Date(c.updatedAt).toLocaleDateString('zh-CN', {
                          month: 'numeric',
                          day: 'numeric',
                        })}
                      </time>
                    </span>
                    <span className="preview">
                      {c.preview ? <HighlightText text={c.preview} query={query} /> : '暂无消息'}
                    </span>
                  </span>
                </button>
                <ActionMenu
                  label={`会话操作：${c.title}`}
                  disabled={busy || pinBusy}
                  actions={[
                    {
                      label: c.isPinned ? '取消置顶' : '置顶',
                      icon: <Pin size={15} />,
                      onSelect: () => onTogglePin(c),
                    },
                    {
                      label: '改名',
                      icon: <Pencil size={15} />,
                      onSelect: () => onOpenDialog('rename', c),
                      opensDialog: true,
                    },
                    {
                      label: '删除',
                      icon: <Trash2 size={15} />,
                      onSelect: () => onOpenDialog('delete', c),
                      danger: true,
                      opensDialog: true,
                    },
                  ]}
                />
              </div>
            </ConversationContextMenu>
          ))}
        {!listLoading && !conversations.items.length && (
          <div className="list-empty">
            <MessageSquare size={28} />
            <p>{!connected ? '暂时无法连接服务' : query ? '没有找到相关会话' : '还没有会话'}</p>
            <small>
              {query ? '试试消息内容、批注或文件名' : '新建一个会话，在手机和电脑之间共享内容'}
            </small>
            {!connected && <button onClick={onRetrySync}>重新连接</button>}
          </div>
        )}
      </div>
      {conversations.totalPages > 1 && (
        <div className="pagination">
          <button
            disabled={page === 1}
            onClick={() => onPageChange(page - 1)}
            aria-label="上一页会话"
          >
            <ChevronLeft size={16} />
          </button>
          {page} / {conversations.totalPages}
          <button
            disabled={page >= conversations.totalPages}
            onClick={() => onPageChange(page + 1)}
            aria-label="下一页会话"
          >
            <ChevronRight size={16} />
          </button>
        </div>
      )}
      <div className="profile">
        <div className="profile-name">
          <strong>{userName}</strong>
          <SyncStatus connected={connected} lastSyncedAt={lastSyncedAt} onRetry={onRetrySync} />
        </div>
        <button className="icon-btn" aria-label="退出登录" onClick={onLogout}>
          <LogOut size={17} />
        </button>
      </div>
    </aside>
  );
}
