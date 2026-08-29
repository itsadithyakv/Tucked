'use client';

/**
 * Sparkles — the happy layer. Ambient twinkles around good news, and gold
 * bursts on primary presses. Decorative only: never attached to Now/serious
 * content (design law), and inert under prefers-reduced-motion (the global
 * reduce rule kills the keyframes; bursts also check before spawning).
 */

import type { ReactNode } from 'react';

const STAR_PATH = 'M6 0 L7.4 4.6 L12 6 L7.4 7.4 L6 12 L4.6 7.4 L0 6 L4.6 4.6 Z';

export function Star({ size = 12 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 12 12" aria-hidden fill="currentColor">
      <path d={STAR_PATH} />
    </svg>
  );
}

/** Deterministic twinkle placements around the wrapped element. */
const AMBIENT = [
  { top: '-10px', right: '-12px', size: 12, delay: '0s' },
  { bottom: '-6px', left: '-12px', size: 9, delay: '0.9s' },
  { top: '30%', right: '-20px', size: 7, delay: '1.7s' },
] as const;

export function Sparkles({ children, count = 2 }: { children: ReactNode; count?: 1 | 2 | 3 }) {
  return (
    <span className="sparkle-host">
      {children}
      {AMBIENT.slice(0, count).map((s, i) => (
        <span
          key={i}
          className="sparkle"
          style={{ ...s, width: s.size, height: s.size, animationDelay: s.delay }}
        >
          <Star size={s.size} />
        </span>
      ))}
    </span>
  );
}

const BURST_DIRECTIONS = [
  [0, -46], [34, -30], [46, 4], [30, 36], [-2, 46], [-34, 32], [-46, -2], [-30, -34],
] as const;

/** Spawn a gold star burst at viewport coordinates. Self-cleaning. */
export function sparkleBurst(x: number, y: number) {
  if (typeof document === 'undefined') return;
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const host = document.createElement('div');
  host.className = 'sparkle-burst';
  for (const [i, [dx, dy]] of BURST_DIRECTIONS.entries()) {
    const fly = document.createElement('span');
    fly.className = 'fly';
    const size = i % 3 === 0 ? 13 : 9;
    fly.style.left = `${x - size / 2}px`;
    fly.style.top = `${y - size / 2}px`;
    fly.style.setProperty('--dx', `${dx}px`);
    fly.style.setProperty('--dy', `${dy}px`);
    fly.style.animationDelay = `${(i % 4) * 22}ms`;
    fly.innerHTML = `<svg width="${size}" height="${size}" viewBox="0 0 12 12" fill="currentColor" aria-hidden="true"><path d="${STAR_PATH}"/></svg>`;
    host.appendChild(fly);
  }
  document.body.appendChild(host);
  setTimeout(() => host.remove(), 900);
}
