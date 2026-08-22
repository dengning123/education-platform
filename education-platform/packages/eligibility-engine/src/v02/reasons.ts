import { REASON_CODES, MISSING_DATA_CODES } from "./generated.js";

export const ReasonCodeV02 = Object.fromEntries(
  REASON_CODES.map((code) => [code, code]),
) as { readonly [K in (typeof REASON_CODES)[number]]: K };

export const MissingDataCodeV02 = Object.fromEntries(
  MISSING_DATA_CODES.map((code) => [code, code]),
) as { readonly [K in (typeof MISSING_DATA_CODES)[number]]: K };
