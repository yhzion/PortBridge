import type { Forwarding, RemotePort } from "../lib/types";
import "./ForwardingRow.css";

interface ForwardingRowProps {
  port: RemotePort;
  forwarding: Forwarding | null;
  serverDisplayName: string | null;
  onToggle: () => void;
  isFavorite: boolean;
  onFavoriteToggle: () => void;
}

const ERROR_PREFIX = "Error: ";

function scopeLabel(address: string): string {
  switch (address) {
    case "0.0.0.0":
    case "::":
      return "모든 인터페이스";
    case "127.0.0.1":
    case "::1":
      return "로컬 전용";
    default:
      return address;
  }
}

function displayLine(port: RemotePort): string {
  const base = `:${port.port} · ${scopeLabel(port.address)}`;
  if (port.process_name && port.process_name.length > 0) {
    return `${base} · ${port.process_name}`;
  }
  return base;
}

/**
 * 단일 원격 포트 행 (macOS `ForwardingRowView` 포팅).
 *
 * 순수 presentational — 데이터·콜백은 props로만 받는다. forwarding이 null이면 idle.
 * state 문자열은 "Idle"|"Starting"|"Active"|"Error: ..." (Error는 "Error: " 접두).
 */
export function ForwardingRow({
  port,
  forwarding,
  serverDisplayName,
  onToggle,
  isFavorite,
  onFavoriteToggle,
}: ForwardingRowProps) {
  const state = forwarding?.state ?? "Idle";
  const isStarting = state === "Starting";
  const isActive = state === "Active";
  const isErrorState = state.startsWith(ERROR_PREFIX);
  const errorMessage = isErrorState ? state.slice(ERROR_PREFIX.length) : null;

  // showPortColumn: Starting일 때만 숨김(스피너+서브타이틀로 대체).
  const showPortColumn = !isStarting;

  const serverPrefix = serverDisplayName ? `${serverDisplayName} · ` : "";

  let stateSubtitle: string | null = null;
  if (isStarting) {
    stateSubtitle = `${serverPrefix}포워딩 연결 중…`;
  } else if (isActive && forwarding) {
    stateSubtitle = `→ :${forwarding.local_port} 포워딩 중`;
  } else if (isErrorState) {
    stateSubtitle = `${serverPrefix}포워딩 실패 — 클릭해 다시 시도`;
  }

  const rightPrimary = stateSubtitle ?? scopeLabel(port.address);

  let rightPrimaryClass = "pb-forwarding-row__primary--secondary";
  if (isErrorState) {
    rightPrimaryClass = "pb-forwarding-row__primary--error";
  } else if (isActive) {
    rightPrimaryClass = "pb-forwarding-row__primary--active";
  }

  const rightSecondary =
    stateSubtitle === null && port.process_name && port.process_name.length > 0
      ? port.process_name
      : null;

  let portColumnClass = "";
  if (isErrorState) {
    portColumnClass = "pb-forwarding-row__port--error";
  } else if (isActive) {
    portColumnClass = "pb-forwarding-row__port--active";
  }

  const accessibilityLabel = stateSubtitle
    ? `:${port.port} ${serverPrefix}${stateSubtitle}`
    : displayLine(port);

  const toggleHint =
    state === "Active" ? "이중 탭하여 포워딩 끄기" : "이중 탭하여 포워딩 켜기";
  const toggleHelp =
    state === "Active" ? "클릭해 포워딩 끄기" : "클릭해 포워딩 켜기";

  return (
    <div className="pb-forwarding-row">
      <button
        type="button"
        className="pb-forwarding-row__favorite"
        onClick={onFavoriteToggle}
        aria-label={isFavorite ? "즐겨찾기 해제" : "즐겨찾기 추가"}
        title={isFavorite ? "즐겨찾기에서 제거" : "즐겨찾기에 추가"}
      >
        {isFavorite ? (
          <svg
            className="pb-forwarding-row__star pb-forwarding-row__star--on"
            viewBox="0 0 16 16"
            width="16"
            height="16"
            aria-hidden="true"
          >
            <path d="M8 1.2l1.96 3.97 4.38.64-3.17 3.09.75 4.36L8 11.2l-3.92 2.06.75-4.36L1.66 5.81l4.38-.64z" />
          </svg>
        ) : (
          <svg
            className="pb-forwarding-row__star"
            viewBox="0 0 16 16"
            width="16"
            height="16"
            aria-hidden="true"
          >
            <path
              d="M8 1.2l1.96 3.97 4.38.64-3.17 3.09.75 4.36L8 11.2l-3.92 2.06.75-4.36L1.66 5.81l4.38-.64z"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.2"
              strokeLinejoin="round"
            />
          </svg>
        )}
      </button>

      <button
        type="button"
        className="pb-forwarding-row__toggle"
        onClick={onToggle}
        disabled={isStarting}
        title={toggleHelp}
        aria-label={accessibilityLabel}
        aria-description={toggleHint}
      >
        <span className="pb-forwarding-row__status">
          {isStarting ? (
            <span className="pb-forwarding-row__spinner" aria-hidden="true" />
          ) : isActive ? (
            <svg
              className="pb-forwarding-row__dot pb-forwarding-row__dot--active"
              viewBox="0 0 16 16"
              width="16"
              height="16"
              aria-hidden="true"
            >
              <circle cx="8" cy="8" r="4" fill="currentColor" />
            </svg>
          ) : isErrorState ? (
            <svg
              className="pb-forwarding-row__dot pb-forwarding-row__dot--error"
              viewBox="0 0 16 16"
              width="16"
              height="16"
              aria-hidden="true"
            >
              <path
                d="M8 2l6 11H2z"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.4"
                strokeLinejoin="round"
              />
              <path
                d="M8 6.5v3.2M8 11.2v.1"
                stroke="currentColor"
                strokeWidth="1.4"
                strokeLinecap="round"
              />
            </svg>
          ) : (
            <svg
              className="pb-forwarding-row__dot pb-forwarding-row__dot--idle"
              viewBox="0 0 16 16"
              width="16"
              height="16"
              aria-hidden="true"
            >
              <circle
                cx="8"
                cy="8"
                r="4"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.4"
              />
            </svg>
          )}
        </span>

        {showPortColumn && (
          <span className={`pb-forwarding-row__port ${portColumnClass}`}>
            :{port.port}
          </span>
        )}

        <span className="pb-forwarding-row__text">
          <span className={`pb-forwarding-row__primary ${rightPrimaryClass}`}>
            {rightPrimary}
          </span>
          {rightSecondary && (
            <span className="pb-forwarding-row__secondary">
              {rightSecondary}
            </span>
          )}
        </span>

        <span className="pb-forwarding-row__spacer" />
      </button>

      {isActive && forwarding && (
        <a
          className="pb-forwarding-row__open"
          href={`http://localhost:${forwarding.local_port}`}
          target="_blank"
          rel="noreferrer"
          title={`기본 브라우저로 http://localhost:${forwarding.local_port} 열기`}
        >
          <svg
            className="pb-forwarding-row__open-icon"
            viewBox="0 0 16 16"
            width="13"
            height="13"
            aria-hidden="true"
          >
            <path
              d="M5.5 3h7.5v7.5M13 3L7 9"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.4"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
            <path
              d="M11 9.5V12.5a1 1 0 01-1 1H3.5a1 1 0 01-1-1V6a1 1 0 011-1H6.5"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.4"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
          <span className="pb-forwarding-row__open-label">
            브라우저에서 열기
          </span>
        </a>
      )}

      {isErrorState && errorMessage && (
        <span
          className="pb-forwarding-row__info"
          title={errorMessage}
          aria-hidden="true"
        >
          <svg viewBox="0 0 16 16" width="15" height="15">
            <circle
              cx="8"
              cy="8"
              r="6.2"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.3"
            />
            <path
              d="M8 7v4M8 4.9v.1"
              stroke="currentColor"
              strokeWidth="1.4"
              strokeLinecap="round"
            />
          </svg>
        </span>
      )}
    </div>
  );
}
