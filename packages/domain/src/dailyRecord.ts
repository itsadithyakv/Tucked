/**
 * Daily written record drafter (s. 37). Deterministic template — never AI
 * (never-do list §9.14). The regulation requires a dated entry every operating
 * day summarising incidents, fire drills, accidents ("see child's file"),
 * serious occurrences and self-administered medication. "Uneventful" is a
 * valid answer; the human still confirms before the day closes.
 */

export interface DailyRecordInput {
  attendanceCount: number;
  staffCount: number;
  accidents: number;
  fireDrills: number;
  seriousOccurrences: number;
  selfAdministeredMedications: number;
  /** Free-text incident summaries affecting a child's or staff member's
   * health, safety or well-being. */
  incidents: string[];
  outdoorMinutes: number | null;
  outdoorSkippedReason: string | null;
}

function count(n: number, singular: string, plural: string): string {
  return `${n} ${n === 1 ? singular : plural}`;
}

export function draftDailyRecord(input: DailyRecordInput): string {
  const lines: string[] = [];
  lines.push(
    `Attendance: ${count(input.attendanceCount, 'child', 'children')} present with ${count(
      input.staffCount,
      'staff member',
      'staff members',
    )} on shift.`,
  );

  if (input.outdoorMinutes !== null && input.outdoorMinutes > 0) {
    lines.push(`Outdoor play: ${input.outdoorMinutes} minutes.`);
  } else if (input.outdoorSkippedReason) {
    lines.push(`Outdoor play not held: ${input.outdoorSkippedReason}.`);
  }

  if (input.fireDrills > 0) {
    lines.push(`Fire drill held: ${count(input.fireDrills, 'drill', 'drills')} completed and recorded.`);
  }
  if (input.accidents > 0) {
    lines.push(`${count(input.accidents, 'Accident', 'Accidents')} recorded — see child's file.`);
  }
  if (input.seriousOccurrences > 0) {
    lines.push(
      `${count(input.seriousOccurrences, 'Serious occurrence', 'Serious occurrences')} reported — see serious occurrence record.`,
    );
  }
  if (input.selfAdministeredMedications > 0) {
    lines.push(
      `Self-administered medication: ${count(input.selfAdministeredMedications, 'dose', 'doses')} recorded in the medication log.`,
    );
  }
  for (const incident of input.incidents) {
    lines.push(`Incident: ${incident}`);
  }

  const eventful =
    input.accidents > 0 ||
    input.fireDrills > 0 ||
    input.seriousOccurrences > 0 ||
    input.selfAdministeredMedications > 0 ||
    input.incidents.length > 0;
  if (!eventful) {
    lines.push('Nothing further to report — an uneventful day.');
  }
  return lines.join('\n');
}
