'use client';

import type { ReactNode } from 'react';

/** Remounts per navigation, so each page settles in with the page-in
 * animation (collapsed entirely under prefers-reduced-motion). */
export default function ConsoleTemplate({ children }: { children: ReactNode }) {
  return <div className="page-enter">{children}</div>;
}
