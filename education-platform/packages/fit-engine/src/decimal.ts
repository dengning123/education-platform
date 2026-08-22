export function compareExactDecimal(left: string, right: string): -1 | 0 | 1 {
  const parse = (value: string) => {
    const negative = value.startsWith("-");
    const unsigned = negative ? value.slice(1) : value;
    const [whole = "0", fraction = ""] = unsigned.split(".");
    return { negative, whole: whole.replace(/^0+(?=\d)/, ""), fraction: fraction.replace(/0+$/, "") };
  };
  const a = parse(left);
  const b = parse(right);
  const scale = Math.max(a.fraction.length, b.fraction.length);
  const magnitude = (value: typeof a) =>
    BigInt(`${value.whole}${value.fraction.padEnd(scale, "0")}` || "0") *
    (value.negative ? -1n : 1n);
  const aValue = magnitude(a);
  const bValue = magnitude(b);
  return aValue < bValue ? -1 : aValue > bValue ? 1 : 0;
}
