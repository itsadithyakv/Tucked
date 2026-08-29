import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    include: ['test/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      // Quality gate (build prompt §12): ≥ 90% branch coverage on the rule engine.
      include: [
        'src/ageGroups.ts',
        'src/ratios.ts',
        'src/retention.ts',
        'src/notifications.ts',
        'src/presets.ts',
      ],
      thresholds: { branches: 90 },
    },
  },
});
