import { defineConfig } from 'vitest/config';

/** The offline command queue is the s. 82(2) path: a regulated write made on a
 * phone with no signal must survive, keep its order, and never be silently
 * dropped. Until now that was verified only by hand on a device. */
export default defineConfig({
  test: {
    globals: true,
    include: ['test/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      include: ['src/lib/queue.ts'],
      thresholds: { branches: 85 },
    },
  },
});
