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
  blue50: '#EAF2FD', // Mist. Tinted surfaces.
  ink: '#17325C', // Primary text (12.75:1).

  // Neutrals
  canvas: '#F7F9FC',
  surface: '#FFFFFF',
  line: '#E3E9F2',
  slate: '#4B5C74', // Secondary text (6.81:1).
  slateMuted: '#7C8AA0', // Placeholders, timestamps — large/secondary contexts only.

  // Semantic — green = fine, red = act now, amber = due soon (sparingly)
  ok: '#1E7A46',
  okWash: '#E7F4EC',
  now: '#C2362B',
  nowWash: '#FBECEA',
  due: '#B45309',
  dueWash: '#FBF1E4',
} as const;

/**
 * Gilroy ships as five separate internal families (each weight class 400).
 * Select by family name ONLY — never set fontWeight alongside a custom family
 * on React Native. Load each ttf under exactly these keys.
 */
export const fontFamily = {
  light: 'Gilroy-Light',
  regular: 'Gilroy-Regular',
  medium: 'Gilroy-Medium',
  bold: 'Gilroy-Bold',
  heavy: 'Gilroy-Heavy',
} as const;

export interface TypeStyle {
  fontFamily: string;
  fontSize: number;
  lineHeight: number;
  letterSpacing?: number;
  textTransform?: 'uppercase';
}

export const type: Record<string, TypeStyle> = {
  display: { fontFamily: fontFamily.heavy, fontSize: 32, lineHeight: 38 },
  title: { fontFamily: fontFamily.bold, fontSize: 24, lineHeight: 30 },
  heading: { fontFamily: fontFamily.bold, fontSize: 20, lineHeight: 26 },
  subheading: { fontFamily: fontFamily.medium, fontSize: 17, lineHeight: 24 },
  body: { fontFamily: fontFamily.regular, fontSize: 16, lineHeight: 24 },
  label: { fontFamily: fontFamily.medium, fontSize: 15, lineHeight: 20 },
  caption: { fontFamily: fontFamily.regular, fontSize: 13, lineHeight: 18 },
  overline: {
    fontFamily: fontFamily.medium,
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

/** Generous radii, echoing the mark's roundness. Nothing square-cornered. */
export const radius = {
  sm: 8, // chips, inputs
  md: 12, // buttons
  lg: 16, // cards (the default)
  xl: 24, // sheets, modals
  pill: 999,
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
