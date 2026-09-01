'use client';

/** Light / dark / follow-the-system, in that cycle.
 *
 * Three states rather than two, because "dark mode" genuinely has three: a
 * reader who wants light at midnight is as real as one who wants dark at noon,
 * and a reader who wants neither — just whatever their phone is doing — is the
 * commonest of all, so it is the default.
 *
 * The choice is written to <html data-theme> and to localStorage. The
 * no-flash script in the root layout reads it back before first paint, so a
 * supervisor who has chosen dark never gets a white flash at six in the
 * morning.
 */

import { useEffect, useState } from 'react';
import { Monitor, Moon, Sun } from 'lucide-react';

export type Theme = 'system' | 'light' | 'dark';

const ORDER: Theme[] = ['system', 'light', 'dark'];

const LABEL: Record<Theme, string> = {
  system: 'Following your device',
  light: 'Light',
  dark: 'Dark',
};

export function applyTheme(theme: Theme) {
  const root = document.documentElement;
  if (theme === 'system') root.removeAttribute('data-theme');
  else root.setAttribute('data-theme', theme);
  try {
    localStorage.setItem('tucked.theme', theme);
  } catch {
    /* storage unavailable — the choice still holds for this visit */
  }
}

export function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>('system');
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let saved: Theme = 'system';
    try {
      const v = localStorage.getItem('tucked.theme');
      if (v === 'light' || v === 'dark' || v === 'system') saved = v;
    } catch {
      /* storage unavailable */
    }
    setTheme(saved);
    setReady(true);
  }, []);

  function next() {
    const value = ORDER[(ORDER.indexOf(theme) + 1) % ORDER.length]!;
    setTheme(value);
    applyTheme(value);
  }

  const Icon = theme === 'dark' ? Moon : theme === 'light' ? Sun : Monitor;

  return (
    <button
      type="button"
      className="theme-toggle"
      onClick={next}
      // Until the saved value is read the icon would be wrong, and an icon that
      // changes under the reader's eye is worse than one that arrives a frame
      // late.
      style={{ visibility: ready ? 'visible' : 'hidden' }}
      aria-label={`Appearance: ${LABEL[theme]}. Change it.`}
      title={`Appearance: ${LABEL[theme]}`}
    >
      <Icon aria-hidden />
      <span className="theme-label">{LABEL[theme]}</span>
    </button>
  );
}
