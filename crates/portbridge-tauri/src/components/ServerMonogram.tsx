import "./ServerMonogram.css";

import type { Server } from "../lib/types";

interface ServerMonogramProps {
  server: Server;
  status: "none" | "offline" | "warning" | "online";
  pulse?: boolean;
  dimmed?: boolean;
}

function initialOf(server: Server): string {
  const source = server.name ?? server.host;
  const first = [...source][0];
  return first ? first.toUpperCase() : "?";
}

/** server.host의 UTF-8 바이트로 FNV-1a 32bit 해시 → hue(0..1). */
function hueOf(host: string): number {
  let hash = 0x811c9dc5;
  const bytes = new TextEncoder().encode(host);
  for (const byte of bytes) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return (hash % 360) / 360;
}

const SATURATION = 0.55;
const BRIGHTNESS = 0.85;
const FILL_OPACITY = 0.18;
const STROKE_OPACITY = 0.4;

export function ServerMonogram({
  server,
  status,
  pulse = false,
  dimmed = false,
}: ServerMonogramProps) {
  const hueDeg = hueOf(server.host) * 360;
  const tint = `hsl(${hueDeg}, ${SATURATION * 100}%, ${BRIGHTNESS * 100}%)`;
  const fill = `hsla(${hueDeg}, ${SATURATION * 100}%, ${BRIGHTNESS * 100}%, ${FILL_OPACITY})`;
  const stroke = `hsla(${hueDeg}, ${SATURATION * 100}%, ${BRIGHTNESS * 100}%, ${STROKE_OPACITY})`;

  return (
    <div className="pb-monogram">
      <div
        className="pb-monogram__tile"
        style={{
          background: fill,
          boxShadow: `inset 0 0 0 0.5px ${stroke}`,
          color: tint,
          opacity: dimmed ? 0.55 : 1,
        }}
      >
        {initialOf(server)}
      </div>
      {status !== "none" && (
        <span
          className={`pb-monogram__dot pb-monogram__dot--${status}${pulse ? " pb-monogram__dot--pulse" : ""}`}
        />
      )}
    </div>
  );
}
