/**
 * Tucked design tokens — single source of truth.
 * Values and rules: references/design-language.md. Colours were sampled from the
 * logo and contrast-checked; do not add a colour here without a computed ratio.
 * Consumed as TS objects by React Native StyleSheet and mirrored in css/tokens.css.
 */

export const colour = {
  // Brand blues (sampled from assets/logoTuckedNoBG.png)
  blue500: '#3E89E8', // Blanket. Large text/UI only on white (3.53:1) — never body text.
  blue600: '#2166C8', // Deep. Pressed states, text links (5.53:1).
  blue700: '#1C5AB5', // High-emphasis blue text, focus rings (6.61:1).
  blue100: '#A0C8F8', // Heart. DECORATIVE ONLY (1.73:1) — never text.
  blue50: '#CFE2FA', // Mist. Tinted surfaces.
  ink: '#17325C', // Primary text (12.75:1).

  // Neutrals
  canvas: '#EFF4FB',
  surface: '#FFFFFF',
  line: '#D9E2EF',
  slate: '#46587A', // Secondary text (7.4:1).
  slateMuted: '#7C8AA0', // Placeholders, timestamps — large/secondary contexts only.

  // Semantic — green = fine, red = act now, amber = due soon (sparingly)
  ok: '#177243',
  okWash: '#C9EAD7',
  now: '#B02A20',
  nowWash: '#F9D9D3',
  due: '#96470A',
  dueWash: '#FAE3C2',
} as const;

/**
 * Baloo 2 carries the bubbly display personality (headings, buttons, nav);
 * Nunito keeps records readable. Mobile ships static instances, each under
 * its own family name — select by family name ONLY, never set fontWeight
 * alongside a custom family on React Native.
 */
export const fontFamily = {
  displaySemi: 'Baloo2-SemiBold',
  displayBold: 'Baloo2-Bold',
  displayHeavy: 'Baloo2-ExtraBold',
  body: 'Nunito-Medium',
  bodySemi: 'Nunito-SemiBold',
  bodyBold: 'Nunito-Bold',
} as const;

export interface TypeStyle {
  fontFamily: string;
  fontSize: number;
  lineHeight: number;
  letterSpacing?: number;
  textTransform?: 'uppercase';
}

export const type: Record<string, TypeStyle> = {
  display: { fontFamily: fontFamily.displayHeavy, fontSize: 34, lineHeight: 40 },
  title: { fontFamily: fontFamily.displayBold, fontSize: 26, lineHeight: 32 },
  heading: { fontFamily: fontFamily.displaySemi, fontSize: 20, lineHeight: 26 },
  subheading: { fontFamily: fontFamily.bodyBold, fontSize: 17, lineHeight: 24 },
  body: { fontFamily: fontFamily.body, fontSize: 16, lineHeight: 24 },
  label: { fontFamily: fontFamily.displaySemi, fontSize: 15, lineHeight: 20 },
  caption: { fontFamily: fontFamily.bodySemi, fontSize: 13, lineHeight: 18 },
  overline: {
    fontFamily: fontFamily.displaySemi,
    fontSize: 12,
    lineHeight: 16,
    letterSpacing: 0.48,
    textTransform: 'uppercase',
  },
} as const;

/** 4-pt grid. */
export const space = {
  xs: 4,
  sm: 8,
  md: 12,
  base: 16,
  lg: 20,
  xl: 24,
  x2l: 32,
  x3l: 40,
  x4l: 48,
  x5l: 64,
  gutter: 16,
  gutterWeb: 24,
  cardPadding: 16,
  cardGap: 12,
} as const;

/** Generous claymorphic radii, echoing the mark's roundness. */
export const radius = {
  sm: 12, // chips, inputs
  md: 16, // small controls
  lg: 18,
  card: 22, // cards (the default)
  xl: 24, // sheets, modals
  tile: 28, // stat tiles
  pill: 999, // buttons, pills, avatars
} as const;

/** Two elevation levels only; shadows are always ink-tinted, never black. */
export const shadow = {
  resting: {
    shadowColor: colour.ink,
    shadowOpacity: 0.08,
    shadowRadius: 3,
    shadowOffset: { width: 0, height: 1 },
    elevation: 1,
  },
  raised: {
    shadowColor: colour.ink,
    shadowOpacity: 0.14,
    shadowRadius: 24,
    shadowOffset: { width: 0, height: 8 },
    elevation: 8,
  },
} as const;

/** Durations in ms. Respect prefers-reduced-motion on both platforms. */
export const motion = {
  fast: 120,
  base: 200,
  gentle: 300,
} as const;

/** Accessibility floors (quality gates). */
export const a11y = {
  minTouchTarget: 44,
  minTextSize: 13,
} as const;
