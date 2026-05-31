import { useId, useState } from "react";

import type { Server } from "../lib/types";
import "./AddServerModal.css";

interface AddServerModalProps {
  /** 편집 대상 서버. 없으면 신규 추가. */
  editing?: Server;
  /** 입력된 `(user, host, port)`가 이미 존재하는지 검사(자기 자신 제외는 호출 측 책임). */
  isDuplicate: (user: string, host: string, port: number) => boolean;
  onClose: () => void;
  onSubmit: (server: Server) => void;
}

/** 유효 SSH 포트: 1–65535. 0은 "임의 할당" 의미라 SSH 대상으로 부적합. */
function parsePort(portText: string): number | null {
  const trimmed = portText.trim();
  if (!/^\d+$/.test(trimmed)) return null;
  const port = Number(trimmed);
  return port >= 1 && port <= 65535 ? port : null;
}

export function AddServerModal({
  editing,
  isDuplicate,
  onClose,
  onSubmit,
}: AddServerModalProps) {
  const [name, setName] = useState(editing?.name ?? "");
  const [user, setUser] = useState(editing?.user ?? "");
  const [host, setHost] = useState(editing?.host ?? "");
  const [portText, setPortText] = useState(
    editing ? String(editing.port) : "22",
  );

  const trimmedUser = user.trim();
  const trimmedHost = host.trim();
  const parsedPort = parsePort(portText);
  const portValue = parsedPort ?? 22;

  const isDuplicateInput =
    trimmedUser !== "" &&
    trimmedHost !== "" &&
    parsedPort !== null &&
    isDuplicate(trimmedUser, trimmedHost, parsedPort);

  const isValid =
    trimmedUser !== "" &&
    trimmedHost !== "" &&
    parsedPort !== null &&
    !isDuplicateInput;

  const titleId = useId();

  const handleSubmit = () => {
    if (!isValid) return;
    const trimmedName = name.trim();
    onSubmit({
      id: editing?.id ?? crypto.randomUUID(),
      ...(trimmedName !== "" ? { name: trimmedName } : {}),
      user: trimmedUser,
      host: trimmedHost,
      port: portValue,
    });
    onClose();
  };

  const handleKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === "Escape") {
      event.preventDefault();
      onClose();
    } else if (event.key === "Enter" && isValid) {
      event.preventDefault();
      handleSubmit();
    }
  };

  return (
    <div
      className="pb-add-server__overlay"
      onMouseDown={onClose}
      role="presentation"
    >
      <div
        className="pb-add-server__card"
        onMouseDown={(e) => e.stopPropagation()}
        onKeyDown={handleKeyDown}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
      >
        <h2 id={titleId} className="pb-add-server__title">
          {editing ? "서버 편집" : "서버 추가"}
        </h2>

        <div className="pb-add-server__form">
          <label className="pb-add-server__field">
            <span className="pb-add-server__label">이름</span>
            <input
              className="pb-add-server__input"
              type="text"
              value={name}
              placeholder="선택사항"
              onChange={(e) => setName(e.target.value)}
              autoFocus
            />
          </label>

          <label className="pb-add-server__field">
            <span className="pb-add-server__label">사용자</span>
            <input
              className="pb-add-server__input"
              type="text"
              value={user}
              placeholder="user"
              autoCorrect="off"
              autoCapitalize="off"
              spellCheck={false}
              onChange={(e) => setUser(e.target.value)}
            />
          </label>

          <label className="pb-add-server__field">
            <span className="pb-add-server__label">호스트</span>
            <input
              className="pb-add-server__input"
              type="text"
              value={host}
              placeholder="hostname 또는 IP"
              autoCorrect="off"
              autoCapitalize="off"
              spellCheck={false}
              onChange={(e) => setHost(e.target.value)}
            />
          </label>

          <label className="pb-add-server__field">
            <span className="pb-add-server__label">포트</span>
            <input
              className="pb-add-server__input"
              type="text"
              value={portText}
              placeholder="22"
              onChange={(e) => setPortText(e.target.value)}
            />
          </label>

          {portText !== "" && parsedPort === null && (
            <p className="pb-add-server__error">
              1–65535 범위의 숫자여야 합니다
            </p>
          )}
          {isDuplicateInput && (
            <p className="pb-add-server__error">
              이미 등록된 서버입니다 ({trimmedUser}@{trimmedHost}:{portValue})
            </p>
          )}
        </div>

        <div className="pb-add-server__actions">
          <button
            className="pb-add-server__button"
            type="button"
            onClick={onClose}
          >
            취소
          </button>
          <button
            className="pb-add-server__button pb-add-server__button--primary"
            type="button"
            onClick={handleSubmit}
            disabled={!isValid}
          >
            {editing ? "저장" : "추가"}
          </button>
        </div>
      </div>
    </div>
  );
}
