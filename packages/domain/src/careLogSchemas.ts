/**
 * Care-log payload schemas — the client-side face of the validation that
 * app.validate_care_log_payload enforces in SQL (migration 0006). Change both
 * together; test/careLogSchemas.test.ts pins the shared shape.
 */

import { z } from 'zod';
import type { CareLogType } from './presets';

export const mealPayload = z.object({
  meal: z.enum(['breakfast', 'lunch', 'snack_am', 'snack_pm']),
  eaten: z.enum(['none', 'some', 'most', 'all']),
  notes: z.string().optional(),
});

export const bottlePayload = z.object({
  amount_ml: z.number().positive(),
  kind: z.enum(['breast_milk', 'formula', 'milk', 'water']),
  finished: z.boolean().optional(),
});

/** The three positions a child can be placed or found in (s. 33.1). */
export const sleepPosition = z.enum(['back', 'side', 'front']);

/**
 * nap_start is the PLACING, and for a child under 12 months the position is the
 * regulated fact — so the database refuses a nap_start without one. It stays
 * optional here because the same log type covers a four year old on a cot,
 * whose sleep position no regulation names.
 */
export const napStartPayload = z
  .object({ position: sleepPosition.optional() })
  .passthrough();

export const napPayload = z.object({}).passthrough();

export const sleepCheckPayload = z.object({
  breathing_ok: z.boolean(),
  // What the educator SAW. It may differ from how the child was placed —
  // babies roll — and unlike a placing it is never refused: refusing to record
  // a child found on their front would only delete the evidence that somebody
  // noticed.
  position: sleepPosition.optional(),
  repositioned: z.boolean().optional(),
  intervention: z.string().optional(),
});

export const diaperPayload = z.object({
  kind: z.enum(['wet', 'soiled', 'both', 'dry']),
  cream_applied: z.boolean().optional(),
  supplies_remaining: z.number().int().nonnegative().optional(),
});

export const toiletPayload = z.object({
  kind: z.enum(['urine', 'bm', 'attempt', 'accident']),
});

export const outdoorPayload = z
  .object({
    minutes: z.number().int().nonnegative().optional(),
    skipped_reason: z.string().optional(), // weather reason is manual entry — no weather API
    weather_reason: z.string().optional(),
  })
  .refine((p) => p.minutes !== undefined || p.skipped_reason !== undefined, {
    message: 'record minutes outdoors, or the reason the room stayed in',
  });

export const healthObservationPayload = z.object({
  observation: z.string().min(1),
  parent_reported: z.string().optional(), // "restless night" — s. 32
  symptoms: z.array(z.string()).optional(),
});

export const activityPayload = z.object({ description: z.string().min(1) });
export const notePayload = z.object({ text: z.string().min(1) });
export const photoPayload = z.object({
  storage_path: z.string().min(1),
  captured_at: z.string().min(1),
});

export const careLogPayloads: Record<CareLogType, z.ZodTypeAny> = {
  meal: mealPayload,
  bottle: bottlePayload,
  nap_start: napStartPayload,
  nap_end: napPayload,
  sleep_check: sleepCheckPayload,
  diaper: diaperPayload,
  toilet: toiletPayload,
  outdoor: outdoorPayload,
  health_observation: healthObservationPayload,
  activity: activityPayload,
  note: notePayload,
  photo: photoPayload,
};

export function validateCareLogPayload(type: CareLogType, payload: unknown) {
  return careLogPayloads[type].safeParse(payload);
}
