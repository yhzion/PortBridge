import { useId, useState } from "react";

import type { PortConflict } from "../lib/types";
import "./PortConflictModal.css";

interface PortConflictModalProps {
  conflict: PortConflict;
  /** 리모트 안내 문구의 서버 표시명. 없으면 "서버" 폴백. */
  serverDisplayName?: string;
  onConfirm: (newPort: number) => void;
  onClose: () => void;
}

/** 유효 로컬 포트: 1–65535이며 충돌난 포트와 달라야 함. */
function parsePort(
  localPortText: string,
  attemptedLocal: number,
): number | null {
  const trimmed = localPortText.trim();
  if (!/^\d+$/.test(trimmed)) return null;
  const port = Number(trimmed);
  if (port < 1 || port > 65535) return null;
  if (port === attemptedLocal) return null;
  return port;
}

export function PortConflictModal({
  conflict,
  serverDisplayName,
  onConfirm,
  onClose,
}: PortConflictModalProps) {
  const [localPortText, setLocalPortText] = useState(
    String(conflict.attemptedLocal + 1),
  );

  const parsedPort = parsePort(localPortText, conflict.attemptedLocal);

  const trimmed = localPortText.trim();
  let validationMessage: string | null = null;
  if (trimmed !== "") {
    const port = /^\d+$/.test(trimmed) ? Number(trimmed) : null;
    if (port === null || port < 1 || port > 65535) {
      validationMessage = "1–65535 범위의 숫자여야 합니다";
    } else if (port === conflict.attemptedLocal) {
      validationMessage = `이미 사용 중인 포트 ${conflict.attemptedLocal}와(과) 달라야 합니다`;
    }
  }

  const remoteName = serverDisplayName ?? "서버";
  const titleId = useId();

  const handleConfirm = () => {
    if (parsedPort === null) return;
    onConfirm(parsedPort);
    onClose();
  };

  const handleKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === "Escape") {
      event.preventDefault();
      onClose();
    } else if (event.key === "Enter" && parsedPort !== null) {
      event.preventDefault();
      handleConfirm();
    }
  };

  return (
    <div
      className="pb-port-conflict__overlay"
      onMouseDown={onClose}
      role="presentation"
    >
      <div
        className="pb-port-conflict__card"
        onMouseDown={(e) => e.stopPropagation()}
        onKeyDown={handleKeyDown}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
      >
        <h2 id={titleId} className="pb-port-conflict__title">
          로컬 포트 {conflict.attemptedLocal}이(가) 사용 중입니다
        </h2>

        <p className="pb-port-conflict__prompt">
          다른 로컬 포트를 입력하세요. 리모트는 {remoteName}:
          {conflict.remotePort}.
        </p>

        <input
          className="pb-port-conflict__input"
          type="text"
          value={localPortText}
          placeholder="로컬 포트"
          autoFocus
          onChange={(e) => setLocalPortText(e.target.value)}
        />

        {validationMessage !== null && (
          <p className="pb-port-conflict__error">{validationMessage}</p>
        )}

        <div className="pb-port-conflict__actions">
          <button
            className="pb-port-conflict__button"
            type="button"
            onClick={onClose}
          >
            취소
          </button>
          <button
            className="pb-port-conflict__button pb-port-conflict__button--primary"
            type="button"
            onClick={handleConfirm}
            disabled={parsedPort === null}
          >
            연결
          </button>
        </div>
      </div>
    </div>
  );
}
