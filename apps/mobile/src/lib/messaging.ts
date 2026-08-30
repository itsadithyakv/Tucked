/** Shared messaging constants: the audience is the parent's explicit choice,
 * shown on every thread — no silently-copied supervisor. */

export type Audience = 'teacher' | 'supervisor' | 'both';

export const AUDIENCE_LABEL: Record<Audience, string> = {
  teacher: 'Seen by the room team',
  supervisor: 'Seen by the supervisor only',
  both: 'Seen by the room team and the supervisor',
};

export const AUDIENCE_OPTIONS = [
  { value: 'teacher', label: 'The room team' },
  { value: 'supervisor', label: 'The supervisor' },
  { value: 'both', label: 'Both' },
] as const;
