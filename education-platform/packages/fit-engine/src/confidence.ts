import type { FitSignal } from "./contracts.js";

export type DirectionalSignalFacts = Readonly<{
  materialDirectionalCount: number;
  hasNonModelMaterialDirection: boolean;
  hasModelMaterialDirection: boolean;
  isModelOnlyDirection: boolean;
}>;

export function detectDirectionalSignalFacts(
  signals: readonly FitSignal[],
): DirectionalSignalFacts {
  const directional = signals.filter(
    (signal) => signal.material && signal.direction !== "LIMITING",
  );
  const hasModel = directional.some((signal) => signal.inferenceCategory === "MODEL");
  const hasNonModel = directional.some((signal) => signal.inferenceCategory !== "MODEL");
  return {
    materialDirectionalCount: directional.length,
    hasNonModelMaterialDirection: hasNonModel,
    hasModelMaterialDirection: hasModel,
    isModelOnlyDirection: directional.length > 0 && !hasNonModel,
  };
}
