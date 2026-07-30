/* eslint-disable @typescript-eslint/no-require-imports */
const defaultTheme = require('tailwindcss/defaultTheme');

// Light theme colors
const radixUILightColors = require('./colors/light');
// Dark theme colors
const radixUIDarkColors = require('./colors/dark');

// Black with alpha variations
const blackA = require('./colors/blackA');
// White with alpha variations
const whiteA = require('./colors/whiteA');

const foxdeskAppColors = {
  ...blackA,
  ...whiteA,
  ...radixUILightColors,
  ...radixUIDarkColors,
};
// Semantic tokens — the redesign's single source of truth.
// Components reference roles, never raw scale steps, so the look is defined here alone.
const semanticColors = {
  brand: {
    // Deep fox orange (~#C0420C). Primary action fills (5.2:1 with white text)
    // and brand-colored text on light surfaces (4.5:1+). Safe for text pairs.
    DEFAULT: 'hsl(18, 88%, 40%)',
    // Vivid step for non-text glyphs only: unread dots, active icon tints.
    // NEVER paired with text — fails 4.5:1.
    vivid: 'hsl(24, 94%, 50%)',
    // Tinted fill: selected rows, chips, pressed states.
    subtle: 'hsl(24, 100%, 95.5%)',
    // Borders and dividers on tinted surfaces.
    muted: 'hsl(25, 100%, 87%)',
  },
  // Informational links and link-styled text stay blue; never used for actions.
  link: radixUILightColors.blue[800],
  status: {
    open: 'hsl(18, 88%, 40%)',
    pending: 'hsl(42, 100%, 55%)', // existing #FFBA1A
    snoozed: 'hsl(226, 70%, 55.5%)', // existing #3E63DD
    resolved: 'hsl(173, 84%, 33%)', // existing #0D9B8A
  },
  // Warm neutrals (Radix sand) — the "warm precision" base replacing cool grays
  // on redesigned surfaces.
  surface: {
    DEFAULT: '#ffffff',
    // Chips, secondary buttons, quiet fills.
    subtle: radixUILightColors.sand[50],
    // Pressed states, stronger fills.
    muted: radixUILightColors.sand[100],
  },
  ink: {
    // Primary text.
    DEFAULT: radixUILightColors.sand[950],
    // Secondary text: previews, inactive chip labels (6.2:1 on white).
    secondary: radixUILightColors.sand[900],
    // Meta text: timestamps, counts, carets (4.9:1 on white).
    muted: 'hsl(50, 3%, 44%)',
  },
  outline: {
    // Hairlines and borders on white.
    DEFAULT: radixUILightColors.sand[200],
    // Borders on tinted fills.
    soft: radixUILightColors.sand[100],
  },
};

export const twConfig = {
  theme: {
    ...defaultTheme,
    extend: {
      colors: { ...foxdeskAppColors, ...semanticColors },
      fontSize: {
        xs: '12px',
        cxs: '13px',
        md: '15px',
      },
      borderRadius: {
        // Two radii only: controls (buttons, inputs, chips) and sheets/cards.
        control: '12px',
        sheet: '20px',
      },
      // We are using individual static Inter font files (e.g., Inter-400-20.ttf) to load different font weights and styles
      // Please refer to the following links for more information:
      // https://medium.com/timeless/adding-custom-variable-fonts-in-react-native-47e0d062bcfc
      // https://medium.com/timeless/adding-custom-variable-fonts-in-react-native-part-ii-d11a979a38f3
      // - Normal/Regular: "inter-normal-20" (400)
      // - Slightly heavier than Regular: "inter-420-20" (400)
      // - Medium: "inter-medium-24" (500)
      // - Between Medium and Semi-bold: "inter-580-24" (600)
      // - Semi-bold: "inter-semibold-24" (600)
      // -  Last numbers (20, 24 etc) are optical sizes.
      fontFamily: {
        'inter-normal-20': ['Inter-400-20'],
        'inter-420-20': ['Inter-420-20'],
        'inter-medium-24': ['Inter-500-24'],
        'inter-580-24': ['Inter-580-24'],
        'inter-semibold-20': ['Inter-600-20'],
      },
    },
  },
  plugins: [],
};
