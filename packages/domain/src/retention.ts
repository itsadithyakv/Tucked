/**
 * Retention clocks — s. 72(5) (children's records, incl. attendance and plans:
 * 3 years after discharge) and O. Reg. 138/15 s. 27.1 (financial records:
 * 6 years). Purge is anonymisation AFTER the period, never a hard delete, and
 * never before (never-do list §9.14).
 */

export type RetentionKind = 'childrens_record' | 'attendance' | 'financial';

const RETENTION_YEARS: Record<RetentionKind, number> = {
  childrens_record: 3,
  attendance: 3,
  financial: 6,
  // TODO(reg): confirm whether the 6-year financial clock runs from the record
  // date or the end of the fiscal year it relates to; this engine uses the
  // record/reference date (the conservative reading starts later, keeps longer).
};

/** The reference date is the discharge date for children's records and
 * attendance, and the record date for financial records. */
export function retentionEndsAt(kind: RetentionKind, referenceDate: Date): Date {
  const end = new Date(referenceDate.getTime());
  end.setFullYear(end.getFullYear() + RETENTION_YEARS[kind]);
  return end;
}

export function mayAnonymise(kind: RetentionKind, referenceDate: Date, now: Date): boolean {
  return now.getTime() >= retentionEndsAt(kind, referenceDate).getTime();
}
