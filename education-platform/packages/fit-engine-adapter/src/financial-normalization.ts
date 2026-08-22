import { FitAdapterError } from "./database-gateway.js";

type ExactDecimal = Readonly<{ coefficient: bigint; scale: number }>;

function parseExactDecimal(value: string, label: string): ExactDecimal {
  if (!/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(value)) {
    throw new FitAdapterError(`${label} is not an exact decimal`, 422);
  }
  const negative = value.startsWith("-");
  const unsigned = negative ? value.slice(1) : value;
  const [integer = "0", fraction = ""] = unsigned.split(".");
  const coefficient = BigInt(`${integer}${fraction}`) * (negative ? -1n : 1n);
  return { coefficient, scale: fraction.length };
}

function powerOfTen(scale: number): bigint {
  return 10n ** BigInt(scale);
}

function formatExactDecimal(value: ExactDecimal): string {
  if (value.coefficient === 0n) return "0";
  const negative = value.coefficient < 0n;
  let digits = (negative ? -value.coefficient : value.coefficient).toString();
  if (value.scale > 0) {
    digits = digits.padStart(value.scale + 1, "0");
    const split = digits.length - value.scale;
    digits = `${digits.slice(0, split)}.${digits.slice(split)}`.replace(/0+$/, "").replace(/\.$/, "");
  }
  return `${negative ? "-" : ""}${digits}`;
}

export function multiplyExactDecimals(left: string, right: string): string {
  const a = parseExactDecimal(left, "left decimal");
  const b = parseExactDecimal(right, "right decimal");
  return formatExactDecimal({ coefficient: a.coefficient * b.coefficient, scale: a.scale + b.scale });
}

export function subtractExactDecimals(left: string, right: string): string {
  const a = parseExactDecimal(left, "left decimal");
  const b = parseExactDecimal(right, "right decimal");
  const scale = Math.max(a.scale, b.scale);
  return formatExactDecimal({
    coefficient: a.coefficient * powerOfTen(scale - a.scale) - b.coefficient * powerOfTen(scale - b.scale),
    scale,
  });
}

export function equalExactDecimals(left: string, right: string): boolean {
  return subtractExactDecimals(left, right) === "0";
}

export function calculateReviewedFinancialNormalization(input: Readonly<{
  formulaCode: string;
  sourceAmount: string;
  academicYears: string;
  fundingAmount: string | null;
  rounding: string;
  sourceCurrency: string;
  targetCurrency: string;
}>): string {
  if (input.rounding !== "NONE") {
    throw new FitAdapterError("The v017 calculation contract permits only exact no-rounding normalization", 422);
  }
  if (input.sourceCurrency.trim() !== input.targetCurrency.trim()) {
    throw new FitAdapterError("The v017 calculation contract does not authorize currency conversion", 422);
  }
  const annualized = multiplyExactDecimals(input.sourceAmount, input.academicYears);
  if (input.formulaCode === "MULTIPLY_SOURCE_BY_ACADEMIC_YEARS") {
    if (input.fundingAmount !== null) throw new FitAdapterError("Gross annualization forbids funding", 422);
    return annualized;
  }
  if (input.formulaCode === "MULTIPLY_SOURCE_BY_ACADEMIC_YEARS_THEN_SUBTRACT_FUNDING") {
    if (input.fundingAmount === null) throw new FitAdapterError("Net annualization requires funding", 422);
    return subtractExactDecimals(annualized, input.fundingAmount);
  }
  throw new FitAdapterError("Unsupported reviewed Financial calculation contract", 422);
}
