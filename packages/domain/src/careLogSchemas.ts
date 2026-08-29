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

export const napPayload = z.object({}).passthrough();

export const sleepCheckPayload = z.object({
  breathing_ok: z.boolean(),
  position: z.enum(['back', 'side', 'front']).optional(),
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
  nap_start: napPayload,
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
