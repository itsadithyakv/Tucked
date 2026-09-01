/**
 * The CSS token face, checked rather than trusted.
 *
 * tokens.css defines the palette three times — once for light, once for a
 * device set to dark, once for a reader who chose dark explicitly — and nothing
 * in CSS makes those three agree. A colour added to one and forgotten in
 * another is invisible until somebody with that exact combination of device and
 * choice opens the exact screen that uses it. So the agreement is a test.
 *
 * The contrast numbers in references/design-language.md §3 are checked here
 * too. A ratio written in a document is a claim; a ratio in a test is a rule.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const css = readFileSync(fileURLToPath(new URL('../css/tokens.css', import.meta.url)), 'utf8');

/** The body of the first block whose selector line contains `marker`. */
function blockAfter(marker: string): string {
  const at = css.indexOf(marker);
  if (at < 0) throw new Error(`no block for ${marker}`);
  const open = css.indexOf('{', at + marker.length - 1);
  let depth = 0;
  for (let i = open; i < css.length; i += 1) {
    if (css[i] === '{') depth += 1;
    else if (css[i] === '}') {
      depth -= 1;
      if (depth === 0) return css.slice(open + 1, i);
    }
  }
  throw new Error(`unclosed block for ${marker}`);
}

function declarations(body: string): Map<string, string> {
  const out = new Map<string, string>();
  for (const m of body.matchAll(/--([\w-]+)\s*:\s*([^;]+);/g)) {
    // nested blocks are stripped by taking the outermost body only, so a
    // repeated name here would be a genuine duplicate declaration
    out.set(m[1]!, m[2]!.replace(/\s+/g, ' ').trim());
  }
  return out;
}

const light = declarations(blockAfter(':root {'));
// The @media block wraps :root:not([data-theme='light']); take the inner one.
const deviceDark = declarations(blockAfter(":root:not([data-theme='light'])"));
const chosenDark = declarations(blockAfter(":root[data-theme='dark']"));

const PALETTES: Array<[string, Map<string, string>]> = [
  ['light', light],
  ['device dark', deviceDark],
  ['chosen dark', chosenDark],
];

/** A token whose value is a colour, as opposed to a length or a duration. */
function isColour(value: string): boolean {
  return /^(#|rgba?\()/.test(value);
}

// ── colour maths ─────────────────────────────────────────────────────────────

function channels(value: string): [number, number, number] {
  const hex = value.trim();
  if (hex.startsWith('#')) {
    const h = hex.slice(1);
    const full =
      h.length === 3
        ? h
            .split('')
            .map((c) => c + c)
            .join('')
        : h;
    return [
      parseInt(full.slice(0, 2), 16),
      parseInt(full.slice(2, 4), 16),
      parseInt(full.slice(4, 6), 16),
    ];
  }
  const nums = hex.match(/[\d.]+/g);
  if (!nums) throw new Error(`not a colour: ${value}`);
  return [Number(nums[0]), Number(nums[1]), Number(nums[2])];
}

function luminance(value: string): number {
  const [r, g, b] = channels(value).map((c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  }) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a: string, b: string): number {
  const [x, y] = [luminance(a), luminance(b)];
  const [hi, lo] = x > y ? [x, y] : [y, x];
  return (hi + 0.05) / (lo + 0.05);
}

function colour(palette: Map<string, string>, name: string): string {
  const v = palette.get(name);
  if (!v) throw new Error(`missing token --${name}`);
  return v;
}

// ── the three palettes agree ─────────────────────────────────────────────────

describe('the palette is defined three times and must agree', () => {
  it('redefines every light colour in both dark blocks', () => {
    const colours = [...light].filter(([, v]) => isColour(v)).map(([k]) => k);
    expect(colours.length).toBeGreaterThan(20);
    for (const name of colours) {
      expect(deviceDark.has(name), `--${name} missing from the @media block`).toBe(true);
      expect(chosenDark.has(name), `--${name} missing from the data-theme block`).toBe(true);
    }
  });

  it('gives the two dark blocks identical values', () => {
    // They are the same theme reached two ways. A reader who picks dark on a
    // light device must get exactly what a dark device gets, token for token.
    expect([...chosenDark.keys()].sort()).toEqual([...deviceDark.keys()].sort());
    for (const [name, value] of chosenDark) {
      expect(deviceDark.get(name), `--${name} differs between the dark blocks`).toBe(value);
    }
  });

  it('declares color-scheme in every palette so native controls follow', () => {
    // Without this the browser renders selects, scrollbars and date pickers
    // from its own light palette on a dark page.
    expect(blockAfter(':root {')).toContain('color-scheme: light');
    expect(blockAfter(":root:not([data-theme='light'])")).toContain('color-scheme: dark');
    expect(blockAfter(":root[data-theme='dark']")).toContain('color-scheme: dark');
  });
});

// ── contrast, per design-language.md §3 ──────────────────────────────────────

/** [foreground, background, floor].
 *
 * AA is 4.5:1 for body text and 3:1 for large text and UI. Two tokens carry
 * the lower floor on purpose, and say so in their own declarations: blue-500
 * is "large text/UI only, never body text" and slate-muted is for
 * "placeholders, timestamps — large/secondary contexts only". Holding them to
 * 4.5 would not be strictness, it would be testing a rule the design language
 * never made. The floor each token is actually held to is the one it claims.
 */
const PAIRS: Array<[string, string, number]> = [
  ['ink', 'surface', 7],
  ['ink', 'canvas', 7],
  ['slate', 'surface', 7],
  ['slate-muted', 'surface', 3],
  ['blue-500', 'surface', 3],
  ['blue-700', 'surface', 4.5],
  ['ok', 'ok-wash', 4.5],
  ['now', 'now-wash', 4.5],
  ['due', 'due-wash', 4.5],
];

describe.each(PALETTES)('%s contrast', (_name, palette) => {
  it.each(PAIRS)('%s on %s clears %s:1', (fg, bg, floor) => {
    expect(contrast(colour(palette, fg), colour(palette, bg))).toBeGreaterThanOrEqual(floor);
  });

  it('keeps the primary button label legible on its own face', () => {
    // The face is blue-500 and the label is --surface in both palettes, which
    // means white-on-blue in light and dark-navy-on-pale-blue in dark.
    expect(
      contrast(colour(palette, 'surface'), colour(palette, 'blue-500')),
    ).toBeGreaterThanOrEqual(3);
  });
});

describe('dark is not a downgrade', () => {
  it.each(PAIRS)('reads %s on %s at least as well as light does', (fg, bg) => {
    // Dark mode is offered as an equal, not as a concession. If a pair ever
    // reads worse in the dark than in the light, the dark value is wrong —
    // there is always a lighter foreground available on a dark ground.
    const inLight = contrast(colour(light, fg), colour(light, bg));
    const inDark = contrast(colour(chosenDark, fg), colour(chosenDark, bg));
    expect(inDark).toBeGreaterThanOrEqual(inLight);
  });
});

// ── clay is a physical metaphor, and physics does not invert ─────────────────

describe.each(PALETTES)('%s clay', (_name, palette) => {
  it('sits the foot of a clay control DARKER than its face', () => {
    // This is the bug that dark mode exposed: the feet were steps of the brand
    // ramp (blue-700, blue-100), and the ramp inverts in dark because blue-700
    // has to work as text there. Every foot came out lighter than its own face
    // — a button lit from underneath.
    expect(luminance(colour(palette, 'clay-foot'))).toBeLessThan(
      luminance(colour(palette, 'blue-500')),
    );
    expect(luminance(colour(palette, 'clay-foot-quiet'))).toBeLessThan(
      luminance(colour(palette, 'blue-50')),
    );
  });

  it('makes a quiet button MORE present on hover, whichever way that is', () => {
    // button.quiet:hover swaps blue-50 for blue-100 — and the direction is not
    // the same in both palettes. In light the hover darkens; in dark it
    // lightens. Both mean the same thing, which is why the invariant is
    // distance from the canvas rather than lightness.
    expect(contrast(colour(palette, 'blue-100'), colour(palette, 'canvas'))).toBeGreaterThan(
      contrast(colour(palette, 'blue-50'), colour(palette, 'canvas')),
    );
  });

  it('separates a tinted surface from the canvas without shouting', () => {
    // The three room tiles are blue-50, ok-wash and due-wash. A room is not a
    // status, so they must carry equal weight; in dark the mist tile was flat
    // while mint and sand were loud.
    const spread = ['blue-50', 'ok-wash', 'due-wash'].map((t) =>
      contrast(colour(palette, t), colour(palette, 'canvas')),
    );
    expect(Math.max(...spread) - Math.min(...spread)).toBeLessThanOrEqual(0.12);
  });
});
