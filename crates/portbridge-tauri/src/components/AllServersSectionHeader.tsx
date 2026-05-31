import "./AllServersSectionHeader.css";

interface AllServersSectionHeaderProps {
  count: number;
  allExpanded: boolean;
  onToggleAll: () => void;
}

export function AllServersSectionHeader({
  count,
  allExpanded,
  onToggleAll,
}: AllServersSectionHeaderProps) {
  const toggleLabel = allExpanded ? "모두 접기" : "모두 펼치기";
  const toggleHelp = allExpanded ? "모두 접기 (⌘⇧E)" : "모두 펼치기 (⌘⇧E)";
  const toggleA11y = allExpanded ? "모든 서버 접기" : "모든 서버 펼치기";

  return (
    <div className="pb-all-servers-header">
      <span className="pb-all-servers-header__title">모든 서버 · {count}</span>
      <button
        type="button"
        className="pb-all-servers-header__toggle"
        onClick={onToggleAll}
        title={toggleHelp}
        aria-label={toggleA11y}
      >
        {toggleLabel}
      </button>
    </div>
  );
}
