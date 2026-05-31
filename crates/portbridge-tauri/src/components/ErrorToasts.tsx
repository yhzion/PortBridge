// macOS `ContentView.errorStack`/`errorToast` 포팅 — 빨강 계열 오류 토스트 스택.
//
// 순수 컴포넌트: errors/onDismiss를 props로 받는다(스토어 미구독).

import "./ErrorToasts.css";

import type { ErrorToast } from "../lib/types";

interface ErrorToastsProps {
  errors: ErrorToast[];
  onDismiss: (id: string) => void;
}

export function ErrorToasts({ errors, onDismiss }: ErrorToastsProps) {
  if (errors.length === 0) {
    return null;
  }

  return (
    <div className="pb-error-toasts">
      {errors.map((toast) => (
        <div key={toast.id} className="pb-error-toasts__toast">
          <svg
            className="pb-error-toasts__icon"
            viewBox="0 0 16 16"
            width="13"
            height="13"
            aria-hidden="true"
          >
            <path
              fill="currentColor"
              d="M7.13 1.7a1 1 0 0 1 1.74 0l6.06 11.1A1 1 0 0 1 14.06 14.3H1.94a1 1 0 0 1-.87-1.5L7.13 1.7Zm.12 3.55v4.1a.75.75 0 0 0 1.5 0v-4.1a.75.75 0 0 0-1.5 0ZM8 11.3a.9.9 0 1 0 0 1.8.9.9 0 0 0 0-1.8Z"
            />
          </svg>
          <span
            className="pb-error-toasts__message"
            aria-label={`오류: ${toast.message}`}
          >
            {toast.message}
          </span>
          <button
            type="button"
            className="pb-error-toasts__dismiss"
            title="에러 메시지 닫기"
            aria-label="에러 메시지 닫기"
            onClick={() => onDismiss(toast.id)}
          >
            <svg viewBox="0 0 16 16" width="11" height="11" aria-hidden="true">
              <path
                fill="none"
                stroke="currentColor"
                strokeWidth="1.6"
                strokeLinecap="round"
                d="M3.5 3.5l9 9M12.5 3.5l-9 9"
              />
            </svg>
          </button>
        </div>
      ))}
    </div>
  );
}
