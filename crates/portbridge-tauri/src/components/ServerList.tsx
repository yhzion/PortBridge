import { useMemo, useState } from "react";

import {
  isFavorite,
  makeMatches,
  selectActiveForwardings,
  selectAllExpanded,
  selectServerSections,
  serverDisplayName,
  useAppStore,
} from "../store/appStore";
import type { Forwarding, Server } from "../lib/types";
import { ServerSection } from "./ServerSection";
import { ForwardingRow } from "./ForwardingRow";
import { ActiveSectionHeader } from "./ActiveSectionHeader";
import { AllServersSectionHeader } from "./AllServersSectionHeader";
import { AddServerModal } from "./AddServerModal";
import "./ServerList.css";

/**
 * macOS `ServerListView` 등가 — 검색 헤더 + (활성 포워딩 섹션 / 서버별 섹션) 리스트 +
 * 추가/편집 모달 + 삭제 확인. 스토어를 구독하고 콜백을 순수 컴포넌트들에 내려준다.
 */
export function ServerList() {
  const sections = useAppStore(selectServerSections);
  const activeForwardings = useAppStore(selectActiveForwardings);
  const allExpanded = useAppStore(selectAllExpanded);
  const searchText = useAppStore((s) => s.searchText);
  const servers = useAppStore((s) => s.servers);
  const matches = useMemo(() => makeMatches(searchText), [searchText]);
  const isFav = useAppStore(
    (s) => (serverId: string, port: number) => isFavorite(s, serverId, port),
  );
  const displayName = useAppStore(
    (s) => (serverId: string) => serverDisplayName(s, serverId),
  );

  const setSearchText = useAppStore((s) => s.setSearchText);
  const scanAll = useAppStore((s) => s.scanAll);
  const scanServer = useAppStore((s) => s.scanServer);
  const setExpanded = useAppStore((s) => s.setExpanded);
  const toggleAllExpanded = useAppStore((s) => s.toggleAllExpanded);
  const toggleForwarding = useAppStore((s) => s.toggleForwarding);
  const stopAllActiveForwardings = useAppStore(
    (s) => s.stopAllActiveForwardings,
  );
  const toggleFavorite = useAppStore((s) => s.toggleFavorite);
  const addServer = useAppStore((s) => s.addServer);
  const updateServer = useAppStore((s) => s.updateServer);
  const deleteServer = useAppStore((s) => s.deleteServer);

  const [showAddModal, setShowAddModal] = useState(false);
  const [editingServer, setEditingServer] = useState<Server | null>(null);
  const [pendingDelete, setPendingDelete] = useState<Server | null>(null);

  const isDuplicate = (
    user: string,
    host: string,
    port: number,
    excludeId?: string,
  ) =>
    servers.some(
      (s) =>
        s.user === user &&
        s.host === host &&
        s.port === port &&
        s.id !== excludeId,
    );

  // 표시 가능한 활성 포워딩 — 섹션/포트를 찾을 수 있고 검색에 매칭되거나, 못 찾으면 검색이 비어있을 때.
  const visibleActive = activeForwardings.filter((fw) => {
    const section = sections.find((s) => s.server.id === fw.server_id);
    const port = section?.ports.find((p) => p.port === fw.remote_port);
    if (!section || !port) return searchText.trim() === "";
    return matches(port);
  });

  const isSearching = searchText.trim() !== "";
  const hasMatches =
    visibleActive.length > 0 ||
    sections.some((s) => s.ports.some((p) => matches(p)));

  const renderActiveRow = (fw: Forwarding) => {
    const section = sections.find((s) => s.server.id === fw.server_id);
    const port = section?.ports.find((p) => p.port === fw.remote_port);
    if (!section || !port) return null;
    return (
      <ForwardingRow
        key={fw.id}
        port={port}
        forwarding={fw}
        serverDisplayName={displayName(fw.server_id) ?? null}
        onToggle={() => void toggleForwarding(fw.server_id, port.port)}
        isFavorite={isFav(fw.server_id, port.port)}
        onFavoriteToggle={() => void toggleFavorite(fw.server_id, port.port)}
      />
    );
  };

  const isEmpty = sections.length === 0 && activeForwardings.length === 0;

  return (
    <div className="pb-serverlist">
      <header className="pb-serverlist__searchbar">
        {sections.length === 0 ? (
          <span className="pb-serverlist__hint">서버를 추가하세요</span>
        ) : (
          <label className="pb-serverlist__search">
            <span className="pb-serverlist__search-icon" aria-hidden="true">
              ⌕
            </span>
            <input
              type="text"
              value={searchText}
              placeholder="포트 번호나 프로세스 이름으로 찾기"
              onChange={(e) => setSearchText(e.target.value)}
            />
            {searchText !== "" && (
              <button
                type="button"
                className="pb-serverlist__search-clear"
                onClick={() => setSearchText("")}
                aria-label="검색어 지우기"
                title="검색어 지우기"
              >
                ⓧ
              </button>
            )}
          </label>
        )}
        <span className="pb-serverlist__spacer" />
        <button
          type="button"
          className="pb-serverlist__icon-btn"
          onClick={() => void scanAll()}
          title="전체 서버 포트 새로고침 (⌘R)"
          aria-label="전체 서버 포트 새로고침"
        >
          ↻
        </button>
        <button
          type="button"
          className="pb-serverlist__icon-btn"
          onClick={() => setShowAddModal(true)}
          title="서버 추가 (⌘N)"
          aria-label="서버 추가"
        >
          ＋
        </button>
      </header>

      {sections.length > 0 && (
        <AllServersSectionHeader
          count={sections.length}
          allExpanded={allExpanded}
          onToggleAll={toggleAllExpanded}
        />
      )}

      {isEmpty ? (
        <div className="pb-serverlist__empty">
          <div className="pb-serverlist__empty-icon" aria-hidden="true">
            ▦
          </div>
          <p>등록된 서버가 없습니다</p>
          <button
            type="button"
            className="pb-serverlist__add-btn"
            onClick={() => setShowAddModal(true)}
          >
            ＋ 서버 추가
          </button>
        </div>
      ) : isSearching && !hasMatches ? (
        <div className="pb-serverlist__empty">
          <div className="pb-serverlist__empty-icon" aria-hidden="true">
            ⌕
          </div>
          <p>'{searchText}'에 일치하는 결과가 없습니다</p>
          <button
            type="button"
            className="pb-serverlist__add-btn"
            onClick={() => setSearchText("")}
          >
            검색어 지우기
          </button>
        </div>
      ) : (
        <div className="pb-serverlist__list">
          {visibleActive.length > 0 && (
            <section className="pb-serverlist__section">
              <ActiveSectionHeader
                count={visibleActive.length}
                onStopAll={() => void stopAllActiveForwardings()}
              />
              {visibleActive.map(renderActiveRow)}
            </section>
          )}
          <section className="pb-serverlist__section">
            {sections.map((section) => (
              <ServerSection
                key={section.server.id}
                section={section}
                activeForwardings={activeForwardings}
                matches={matches}
                onToggleExpanded={() =>
                  setExpanded(section.server.id, !section.isExpanded)
                }
                onScan={() => void scanServer(section.server)}
                onToggle={(port) =>
                  void toggleForwarding(section.server.id, port.port)
                }
                onEdit={() => setEditingServer(section.server)}
                onDelete={() => setPendingDelete(section.server)}
                isFavorite={(port) => isFav(section.server.id, port.port)}
                onFavoriteToggle={(port) =>
                  void toggleFavorite(section.server.id, port.port)
                }
              />
            ))}
          </section>
        </div>
      )}

      {showAddModal && (
        <AddServerModal
          isDuplicate={(user, host, port) => isDuplicate(user, host, port)}
          onClose={() => setShowAddModal(false)}
          onSubmit={(server) => {
            void addServer(server);
            setShowAddModal(false);
          }}
        />
      )}

      {editingServer && (
        <AddServerModal
          editing={editingServer}
          isDuplicate={(user, host, port) =>
            isDuplicate(user, host, port, editingServer.id)
          }
          onClose={() => setEditingServer(null)}
          onSubmit={(server) => {
            void updateServer(server);
            setEditingServer(null);
          }}
        />
      )}

      {pendingDelete && (
        <DeleteConfirm
          server={pendingDelete}
          activeCount={
            activeForwardings.filter((f) => f.server_id === pendingDelete.id)
              .length
          }
          onCancel={() => setPendingDelete(null)}
          onConfirm={() => {
            void deleteServer(pendingDelete.id);
            setPendingDelete(null);
          }}
        />
      )}
    </div>
  );
}

interface DeleteConfirmProps {
  server: Server;
  activeCount: number;
  onCancel: () => void;
  onConfirm: () => void;
}

function DeleteConfirm({
  server,
  activeCount,
  onCancel,
  onConfirm,
}: DeleteConfirmProps) {
  const label = server.name ?? server.host;
  const message =
    activeCount > 0
      ? `'${label}'을(를) 삭제하면 활성 포워딩 ${activeCount}개가 종료됩니다. 이 동작은 되돌릴 수 없습니다.`
      : `'${label}'을(를) 삭제하시겠습니까? 이 동작은 되돌릴 수 없습니다.`;
  return (
    <div className="pb-confirm__overlay" role="presentation" onClick={onCancel}>
      <div
        className="pb-confirm"
        role="alertdialog"
        aria-modal="true"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="pb-confirm__title">서버 삭제</h2>
        <p className="pb-confirm__message">{message}</p>
        <div className="pb-confirm__actions">
          <button type="button" onClick={onCancel}>
            취소
          </button>
          <button
            type="button"
            className="pb-confirm__delete"
            onClick={onConfirm}
          >
            삭제
          </button>
        </div>
      </div>
    </div>
  );
}
