import { useEffect, useRef, useState } from "react";
import type {
  Forwarding,
  RemotePort,
  ServerSection as ServerSectionModel,
} from "../lib/types";
import { ForwardingRow } from "./ForwardingRow";
import { ServerMonogram } from "./ServerMonogram";
import "./ServerSection.css";

interface ServerSectionProps {
  section: ServerSectionModel;
  activeForwardings: Forwarding[];
  matches: (p: RemotePort) => boolean;
  onToggleExpanded: () => void;
  onScan: () => void;
  onToggle: (port: RemotePort) => void;
  onEdit: () => void;
  onDelete: () => void;
  isFavorite: (port: RemotePort) => boolean;
  onFavoriteToggle: (port: RemotePort) => void;
}

type MonogramStatus = "none" | "offline" | "warning" | "online";

const INSTALL_COMMANDS: ReadonlyArray<{ distro: string; command: string }> = [
  { distro: "Debian / Ubuntu", command: "sudo apt install iproute2 lsof" },
  { distro: "RHEL / CentOS", command: "sudo yum install iproute lsof" },
  { distro: "Alpine", command: "apk add iproute2 lsof" },
];

export function ServerSection({
  section,
  activeForwardings,
  matches,
  onToggleExpanded,
  onScan,
  onToggle,
  onEdit,
  onDelete,
  isFavorite,
  onFavoriteToggle,
}: ServerSectionProps) {
  const { server, ports, isExpanded, scanState } = section;
  const isOffline = scanState.kind === "offline";

  const serverActive = activeForwardings.filter(
    (f) => f.server_id === server.id,
  );
  const activeCount = serverActive.length;
  const activeNums = new Set(serverActive.map((f) => f.remote_port));
  const inactivePorts = ports.filter(
    (p) => !activeNums.has(p.port) && matches(p),
  );

  const primaryLabel = server.name ?? server.host;
  const sshTarget = `${server.user}@${server.host}`;
  const secondaryLabel =
    server.port === 22 ? sshTarget : `${sshTarget}:${server.port}`;

  let status: MonogramStatus = "none";
  let pulse = false;
  if (scanState.kind === "offline") {
    status = "offline";
    pulse = scanState.isRetrying;
  } else if (
    scanState.kind === "toolMissing" ||
    scanState.kind === "authFailed"
  ) {
    status = "warning";
  } else if (scanState.kind === "loaded") {
    status = "online";
  }

  function handleRowTap() {
    if (isOffline) {
      onScan();
    } else {
      onToggleExpanded();
    }
  }

  return (
    <div className="pb-server-section">
      <div className="pb-server-section__header">
        <button
          type="button"
          className="pb-server-section__row"
          onClick={handleRowTap}
          aria-label={`${primaryLabel} ${secondaryLabel}`}
        >
          {!isOffline ? (
            <span className="pb-server-section__chevron" aria-hidden="true">
              <Chevron expanded={isExpanded} />
            </span>
          ) : (
            <span
              className="pb-server-section__chevron-spacer"
              aria-hidden="true"
            />
          )}

          <span aria-hidden="true">
            <ServerMonogram
              server={server}
              status={status}
              pulse={pulse}
              dimmed={isOffline}
            />
          </span>

          <span className="pb-server-section__labels">
            <span
              className={
                isOffline
                  ? "pb-server-section__primary pb-server-section__primary--dimmed"
                  : "pb-server-section__primary"
              }
            >
              {primaryLabel}
            </span>
            <span className="pb-server-section__secondary">
              {secondaryLabel}
            </span>
          </span>

          <span className="pb-server-section__spacer" />

          {activeCount > 0 && !isOffline ? (
            <span
              className="pb-server-section__badge"
              title="이 서버에서 포워딩 중인 포트 수"
              aria-label={`포워딩 중인 포트 ${activeCount}개`}
            >
              {activeCount}
            </span>
          ) : null}
        </button>

        {scanState.kind === "scanning" ? (
          <span className="pb-server-section__spinner" aria-hidden="true" />
        ) : !isOffline ? (
          <button
            type="button"
            className="pb-server-section__icon-button"
            onClick={onScan}
            title={`${primaryLabel} 포트 재스캔`}
            aria-label={`${primaryLabel} 포트 재스캔`}
          >
            <RefreshIcon />
          </button>
        ) : null}

        <MoreMenu
          primaryLabel={primaryLabel}
          onEdit={onEdit}
          onDelete={onDelete}
        />
      </div>

      {isExpanded && !isOffline ? (
        <div className="pb-server-section__content">
          <SectionContent
            scanState={scanState}
            inactivePorts={inactivePorts}
            onToggle={onToggle}
            isFavorite={isFavorite}
            onFavoriteToggle={onFavoriteToggle}
            onScan={onScan}
          />
        </div>
      ) : null}
    </div>
  );
}

interface SectionContentProps {
  scanState: ServerSectionModel["scanState"];
  inactivePorts: RemotePort[];
  onToggle: (port: RemotePort) => void;
  isFavorite: (port: RemotePort) => boolean;
  onFavoriteToggle: (port: RemotePort) => void;
  onScan: () => void;
}

function SectionContent({
  scanState,
  inactivePorts,
  onToggle,
  isFavorite,
  onFavoriteToggle,
  onScan,
}: SectionContentProps) {
  switch (scanState.kind) {
    case "idle":
      return (
        <p className="pb-server-section__hint">
          ↻ 버튼을 눌러 포트를 스캔하세요
        </p>
      );

    case "scanning":
      return (
        <div className="pb-server-section__scanning">
          <span className="pb-server-section__spinner" aria-hidden="true" />
          <span className="pb-server-section__hint">스캔 중…</span>
        </div>
      );

    case "loaded":
      if (inactivePorts.length === 0) {
        return (
          <p className="pb-server-section__hint">포워딩되지 않은 포트 없음</p>
        );
      }
      return (
        <>
          {inactivePorts.map((port) => (
            <ForwardingRow
              key={port.port}
              port={port}
              forwarding={null}
              serverDisplayName={null}
              onToggle={() => onToggle(port)}
              isFavorite={isFavorite(port)}
              onFavoriteToggle={() => onFavoriteToggle(port)}
            />
          ))}
        </>
      );

    case "toolMissing":
      return <ToolInstallGuide />;

    case "error":
      return (
        <p className="pb-server-section__error">
          <WarningIcon />
          <span>{scanState.message}</span>
        </p>
      );

    case "authFailed":
      return (
        <AuthFailed copyCommand={scanState.copyCommand} onRetry={onScan} />
      );

    case "offline":
      return null;
  }
}

interface MoreMenuProps {
  primaryLabel: string;
  onEdit: () => void;
  onDelete: () => void;
}

function MoreMenu({ primaryLabel, onEdit, onDelete }: MoreMenuProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function onDocClick(event: MouseEvent) {
      if (ref.current && !ref.current.contains(event.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", onDocClick);
    return () => document.removeEventListener("mousedown", onDocClick);
  }, [open]);

  return (
    <div className="pb-server-section__menu" ref={ref}>
      <button
        type="button"
        className="pb-server-section__icon-button"
        onClick={() => setOpen((v) => !v)}
        aria-label={`${primaryLabel} 더보기`}
        aria-haspopup="menu"
        aria-expanded={open}
      >
        <EllipsisIcon />
      </button>
      {open ? (
        <div className="pb-server-section__menu-popover" role="menu">
          <button
            type="button"
            className="pb-server-section__menu-item"
            role="menuitem"
            onClick={() => {
              setOpen(false);
              onEdit();
            }}
          >
            편집…
          </button>
          <div className="pb-server-section__menu-divider" />
          <button
            type="button"
            className="pb-server-section__menu-item pb-server-section__menu-item--destructive"
            role="menuitem"
            onClick={() => {
              setOpen(false);
              onDelete();
            }}
          >
            삭제
          </button>
        </div>
      ) : null}
    </div>
  );
}

interface AuthFailedProps {
  copyCommand: string;
  onRetry: () => void;
}

function AuthFailed({ copyCommand, onRetry }: AuthFailedProps) {
  const { copied, copy } = useCopy(copyCommand);

  return (
    <div className="pb-server-section__guide" onDoubleClick={onRetry}>
      <p className="pb-server-section__guide-title">
        <WarningIcon />
        <span>SSH 키 인증 실패</span>
      </p>
      <div className="pb-server-section__command-row">
        <span className="pb-server-section__command">{copyCommand}</span>
        <span className="pb-server-section__spacer" />
        <CopyButton
          copied={copied}
          onClick={copy}
          label={copied ? "복사됨" : "명령 복사"}
        />
      </div>
    </div>
  );
}

function ToolInstallGuide() {
  return (
    <div className="pb-server-section__guide">
      <p className="pb-server-section__guide-title">
        <WarningIcon />
        <span>원격 서버에 ss 또는 lsof가 필요합니다</span>
      </p>
      <p className="pb-server-section__guide-desc">
        포트 목록을 조회하려면 둘 중 하나가 설치되어 있어야 합니다.
      </p>
      <div className="pb-server-section__commands">
        {INSTALL_COMMANDS.map((item) => (
          <InstallCommandRow
            key={item.distro}
            distro={item.distro}
            command={item.command}
          />
        ))}
      </div>
    </div>
  );
}

interface InstallCommandRowProps {
  distro: string;
  command: string;
}

function InstallCommandRow({ distro, command }: InstallCommandRowProps) {
  const { copied, copy } = useCopy(command);

  return (
    <div className="pb-server-section__install-row">
      <span className="pb-server-section__distro">{distro}</span>
      <span className="pb-server-section__install-command">{command}</span>
      <span className="pb-server-section__spacer" />
      <CopyButton
        copied={copied}
        onClick={copy}
        label={copied ? "복사됨" : `${distro} 명령 복사`}
      />
    </div>
  );
}

function useCopy(value: string) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<number | null>(null);

  useEffect(
    () => () => {
      if (timer.current !== null) window.clearTimeout(timer.current);
    },
    [],
  );

  function copy() {
    void navigator.clipboard.writeText(value);
    setCopied(true);
    if (timer.current !== null) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setCopied(false), 1800);
  }

  return { copied, copy };
}

interface CopyButtonProps {
  copied: boolean;
  onClick: () => void;
  label: string;
}

function CopyButton({ copied, onClick, label }: CopyButtonProps) {
  return (
    <button
      type="button"
      className="pb-server-section__copy-button"
      onClick={onClick}
      title={copied ? "복사됨" : "복사"}
      aria-label={label}
    >
      {copied ? <CheckIcon /> : <CopyIcon />}
    </button>
  );
}

function Chevron({ expanded }: { expanded: boolean }) {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
      <path
        d={expanded ? "M2.5 4.5 L6 8 L9.5 4.5" : "M4.5 2.5 L8 6 L4.5 9.5"}
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function RefreshIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path
        d="M12 7a5 5 0 1 1-1.46-3.54"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
      <path
        d="M12 1.5 V4 H9.5"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function EllipsisIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
      <circle cx="3" cy="8" r="1.4" />
      <circle cx="8" cy="8" r="1.4" />
      <circle cx="13" cy="8" r="1.4" />
    </svg>
  );
}

function WarningIcon() {
  return (
    <svg
      className="pb-server-section__warning-icon"
      width="13"
      height="13"
      viewBox="0 0 14 14"
      fill="none"
    >
      <path
        d="M7 1.5 L13 12 H1 Z"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinejoin="round"
      />
      <path
        d="M7 5.5 V8.5"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
      />
      <circle cx="7" cy="10.4" r="0.8" fill="currentColor" />
    </svg>
  );
}

function CopyIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
      <rect
        x="4.5"
        y="4.5"
        width="7.5"
        height="7.5"
        rx="1.5"
        stroke="currentColor"
        strokeWidth="1.2"
      />
      <path
        d="M9.5 4.5 V3 A1.5 1.5 0 0 0 8 1.5 H3 A1.5 1.5 0 0 0 1.5 3 V8 A1.5 1.5 0 0 0 3 9.5 H4.5"
        stroke="currentColor"
        strokeWidth="1.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
      <path
        d="M2.5 7.5 L5.5 10.5 L11.5 3.5"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
