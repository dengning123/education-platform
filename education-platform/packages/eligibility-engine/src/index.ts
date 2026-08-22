export { aggregateTruth, evaluateEligibility } from "./evaluate.js";
export { ReasonCode } from "./reasons.js";
export type * from "./types.js";
export {
  aggregateV02,
  canonicalizeV02,
  deriveOutcomeV02,
  evaluateTreeV02,
  fingerprintV02,
  knowledgeToActualV02,
  leafClassV02,
  projectLeafV02,
  ReasonCodeV02,
} from "./v02/index.js";
export type {
  EligibilityOutcomeV02,
  EligibilityProjection,
  LeafClass,
  ProjectionValue,
  TruthValueV02,
} from "./v02/index.js";
