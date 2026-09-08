/* =====================================================================
   Chart palette — EDL brand.

   The two corporate colours cannot be used raw as series colours. The
   maroon #6B002C is too dark and the yellow #FEF200 too light to sit in
   the readable lightness band, so each is stepped into range: the maroon
   becomes the wine of slot 1, the yellow becomes the gold of slot 2.

   Validated against the white card surface with the data-viz validator:

     worst adjacent CVD separation   ΔE 9.1   (target >= 8)
     worst adjacent normal vision    ΔE 22.9  (floor  >= 15)

   Gold and aqua measure below 3:1 on white. That is allowed only where
   the value is legible some other way, so every chart drawing them ships
   direct value labels, and the depot table repeats every figure as text.

   Slots are handed out in this fixed order and never cycled. A seventh
   category folds into "Other" rather than inventing a colour, because a
   generated hue collapses onto an existing one under colour blindness.
   ===================================================================== */

export const SERIES = [
  '#A31D52', // 1  wine    — EDL maroon, stepped into the band
  '#EDA100', // 2  gold    — EDL yellow, stepped into the band
  '#1BAF7A', // 3  aqua
  '#4A3AA7', // 4  violet
  '#EB6834', // 5  orange
  '#2A78D6', // 6  blue
];

/* How many slices a part-to-whole chart may draw before the tail folds
   into "Other". Six is the readable ceiling for a donut. */
export const SLICE_CAP = 6;

/* Chrome and ink. Every value clears WCAG on white: primary 18.1:1,
   secondary 6.4:1, muted 4.7:1. */
export const INK = {
  brand: '#6B002C',
  primary: '#2B0A16',
  secondary: '#6B5A62',
  muted: '#7E7178',
  grid: '#EFE9EC',
  surface: '#FFFFFF',
};

/* Shared Recharts tooltip chrome, so all three charts match. */
export const TOOLTIP_STYLE = {
  borderRadius: 8,
  border: `1px solid ${INK.grid}`,
  boxShadow: '0 4px 14px rgba(43, 10, 22, 0.10)',
  fontSize: 12,
  padding: '6px 10px',
};

export const TOOLTIP_LABEL_STYLE = {
  color: INK.primary,
  fontWeight: 600,
  marginBottom: 2,
};
