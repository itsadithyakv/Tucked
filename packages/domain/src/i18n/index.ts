import { enCA } from './en-CA';
import { frCA } from './fr-CA';
import type { Strings } from './en-CA';

export type Locale = 'en-CA' | 'fr-CA';

export const strings: Record<Locale, Strings> = {
  'en-CA': enCA,
  'fr-CA': frCA,
};

export type { Strings };
export { enCA, frCA };
