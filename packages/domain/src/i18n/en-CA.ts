/**
 * en-CA strings. Ontario's words are binding (tucked-ontario-requirements.md §0):
 * supervisor, RECE, program advisor, licensee, age group, children's record,
 * daily written record, serious occurrence. Canadian spelling throughout.
 * No exclamation marks in the working UI; no emoji; specific over generic.
 */

export const enCA = {
  terms: {
    supervisor: 'Supervisor',
    rece: 'RECE',
    programAdvisor: 'Program advisor',
    licensee: 'Licensee',
    ageGroup: 'Age group',
    childrensRecord: "Children's record",
    dailyWrittenRecord: 'Daily written record',
    seriousOccurrence: 'Serious occurrence',
    parent: 'Parent',
    centre: 'Centre',
    enrolment: 'Enrolment',
  },
  auth: {
    familySignInTitle: 'Sign in',
    familySignInBody: 'Enter the email your centre has on file and we will send you a sign-in link.',
    familySignInAction: 'Email me a sign-in link',
    familyLinkSent: 'Check your email — the link signs you in on this device.',
    staffSignInTitle: 'Staff sign in',
    staffSignInAction: 'Sign in',
    signOut: 'Sign out',
  },
  home: {
    familyEmpty: 'No children linked to your account yet. Your centre sends the invitation.',
    roomOffline: 'Working offline — changes will sync when the connection returns.',
  },
  errors: {
    signInFailed: 'That did not work. Check the email address and try again.',
    sessionExpired: 'Your session ended. Sign in again to continue.',
  },
} as const;

export type Strings = typeof enCA;
