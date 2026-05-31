import "./ActiveSectionHeader.css";

interface ActiveSectionHeaderProps {
  count: number;
  onStopAll: () => void;
}

/** macOS `ActiveSectionHeader.swift` 미러 — 활성 포워딩 헤더 + "모두 끄기". */
export function ActiveSectionHeader({
  count,
  onStopAll,
}: ActiveSectionHeaderProps) {
  return (
    <div className="pb-active-section-header">
      <span className="pb-active-section-header__title">
        포워딩 중 · {count}
      </span>
      <button
        type="button"
        className="pb-active-section-header__stop"
        onClick={onStopAll}
        aria-label={`활성 포워딩 ${count}개 모두 끄기`}
      >
        모두 끄기
      </button>
    </div>
  );
}
