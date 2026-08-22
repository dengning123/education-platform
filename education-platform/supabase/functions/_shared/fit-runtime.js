// src/database-gateway.ts
var FitAdapterError = class extends Error {
  constructor(message, status = 500, detail) {
    super(message);
    this.status = status;
    this.detail = detail;
  }
  status;
  detail;
  name = "FitAdapterError";
};
var PostgrestGateway = class {
  constructor(baseUrl, apiKey, bearerToken = apiKey, fetchImpl = fetch) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.bearerToken = bearerToken;
    this.fetchImpl = fetchImpl;
  }
  baseUrl;
  apiKey;
  bearerToken;
  fetchImpl;
  async request(path, init, query = {}) {
    const url = new URL(`${this.baseUrl.replace(/\/$/, "")}/rest/v1/${path}`);
    for (const [key, value] of Object.entries(query)) url.searchParams.set(key, String(value));
    const response = await this.fetchImpl(url, {
      ...init,
      headers: {
        apikey: this.apiKey,
        authorization: `Bearer ${this.bearerToken}`,
        "content-type": "application/json",
        ...init.headers ?? {}
      }
    });
    const text2 = await response.text();
    const body = text2.length === 0 ? null : JSON.parse(text2);
    if (!response.ok) {
      const message = typeof body === "object" && body !== null && "message" in body ? String(body.message) : `Database request failed with HTTP ${response.status}`;
      throw new FitAdapterError(message, response.status, body);
    }
    return body;
  }
  select(table, query = {}) {
    return this.request(table, { method: "GET" }, query);
  }
  insert(table, rows) {
    if (rows.length === 0) return Promise.resolve([]);
    return this.request(table, {
      method: "POST",
      headers: { prefer: "return=representation" },
      body: JSON.stringify(rows)
    }, { select: "*" });
  }
  rpc(functionName, args = {}) {
    return this.request(`rpc/${functionName}`, {
      method: "POST",
      body: JSON.stringify(args)
    });
  }
};
var fitInsertFunctions = {
  fit_evaluation_methods: "insert_fit_evaluation_method",
  fit_manifest_items: "insert_fit_manifest_item",
  fit_manifest_intent_declarations: "insert_fit_manifest_intent_declaration",
  fit_manifest_student_access_contexts: "insert_fit_manifest_student_access_context",
  fit_manifest_phase2_goals: "insert_fit_manifest_phase2_goal",
  fit_manifest_phase2_preferences: "insert_fit_manifest_phase2_preference",
  fit_manifest_phase2_courses: "insert_fit_manifest_phase2_course",
  fit_manifest_phase2_completeness: "insert_fit_manifest_phase2_completeness",
  fit_manifest_phase2_mappings: "insert_fit_manifest_phase2_mapping",
  fit_manifest_catalog_observations: "insert_fit_manifest_catalog_observation",
  fit_manifest_catalog_mappings: "insert_fit_manifest_catalog_mapping",
  fit_manifest_taxonomy_concepts: "insert_fit_manifest_taxonomy_concept",
  fit_manifest_context_claim_selections: "insert_fit_manifest_context_claim_selection",
  fit_manifest_context_mappings: "insert_fit_manifest_context_mapping",
  fit_manifest_student_field_uses: "insert_fit_manifest_student_field_use",
  fit_financial_normalizations: "insert_fit_financial_normalization",
  fit_manifest_financial_normalizations: "insert_fit_manifest_financial_normalization",
  fit_input_domain_states: "insert_fit_input_domain_state",
  fit_dimension_results: "insert_fit_dimension_result",
  fit_signals: "insert_fit_signal",
  fit_signal_evidence: "insert_fit_signal_evidence",
  fit_dimension_reasons: "insert_fit_dimension_reason"
};
var generatedIdColumns = {
  fit_manifest_items: "manifest_item_id",
  fit_input_domain_states: "input_state_id",
  fit_dimension_results: "dimension_result_id",
  fit_signals: "signal_id"
};
var FitExecutorPostgrestGateway = class extends PostgrestGateway {
  async insert(table, rows) {
    const functionName = fitInsertFunctions[table];
    if (functionName === void 0) {
      throw new FitAdapterError(`No frozen executor insert entry point for ${table}`, 500);
    }
    const inserted = [];
    for (const value of rows) {
      if (value === null || typeof value !== "object" || Array.isArray(value)) {
        throw new FitAdapterError(`Invalid composite row for ${table}`, 500);
      }
      const row = { ...value };
      const idColumn = generatedIdColumns[table];
      if (idColumn !== void 0 && row[idColumn] === void 0) row[idColumn] = crypto.randomUUID();
      await this.rpc(functionName, { p_row: row });
      inserted.push(row);
    }
    return inserted;
  }
};
function equalFilter(actual, expected) {
  if (actual === null || actual === void 0) return false;
  return String(actual) === expected;
}
var FitSnapshotGateway = class {
  constructor(snapshot) {
    this.snapshot = snapshot;
  }
  snapshot;
  select(table, query = {}) {
    const source = this.snapshot[table];
    if (source === void 0) throw new FitAdapterError(`Snapshot does not expose ${table}`, 500);
    let rows = [...source];
    for (const [column, rawFilter] of Object.entries(query)) {
      if (column === "select" || column === "order") continue;
      const filter = String(rawFilter);
      if (filter.startsWith("eq.")) {
        const expected = filter.slice(3);
        rows = rows.filter((row) => equalFilter(row[column], expected));
      } else if (filter === "is.null") {
        rows = rows.filter((row) => row[column] === null || row[column] === void 0);
      } else if (filter.startsWith("in.(") && filter.endsWith(")")) {
        const values = new Set(filter.slice(4, -1).split(",").filter((value) => value.length > 0));
        rows = rows.filter((row) => row[column] !== null && row[column] !== void 0 && values.has(String(row[column])));
      } else {
        throw new FitAdapterError(`Snapshot filter is not closed for ${table}.${column}`, 500);
      }
    }
    const order = query.order;
    if (typeof order === "string" && order.length > 0) {
      const columns = order.split(",").map((value) => value.split(".")[0]).filter((value) => value.length > 0);
      rows.sort((left, right) => {
        for (const column of columns) {
          const comparison = String(left[column] ?? "").localeCompare(String(right[column] ?? ""));
          if (comparison !== 0) return comparison;
        }
        return 0;
      });
    }
    return Promise.resolve(rows);
  }
  insert(_table, _rows) {
    throw new FitAdapterError("The Fit source snapshot is read-only", 500);
  }
  rpc(_functionName, _args = {}) {
    throw new FitAdapterError("The Fit source snapshot cannot execute RPCs", 500);
  }
};
function requireOne(rows, label) {
  if (rows.length !== 1 || rows[0] === void 0) {
    throw new FitAdapterError(`${label} requires exactly one row`, 422, { count: rows.length });
  }
  return rows[0];
}
function postgresIn(values) {
  if (values.length === 0) return "in.()";
  for (const value of values) {
    if (!/^[A-Za-z0-9_.:-]+$/.test(value)) {
      throw new FitAdapterError("Unsafe PostgREST filter value", 400);
    }
  }
  return `in.(${values.join(",")})`;
}

// ../fit-engine/dist/src/contracts.js
var FIT_DIMENSIONS = [
  "ACADEMIC",
  "CAREER",
  "FINANCIAL",
  "GEOGRAPHIC_DELIVERY",
  "PERSONAL_PREFERENCE",
  "INTERNATIONAL_ACCESSIBILITY"
];

// ../fit-engine/dist/src/canonicalize.js
function compareText(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}
function sorted(values, key) {
  return [...values].sort((left, right) => compareText(key(left), key(right)));
}
function canonicalManifestItem(item) {
  if (item.kind === "FIT_INTENT" && item.intent.kind === "FINANCIAL_CONSTRAINT") {
    return {
      ...item,
      intent: { ...item.intent, components: [...item.intent.components].sort(compareText) }
    };
  }
  if (item.kind === "DIRECT_FINANCIAL_COMPARABLE") {
    return {
      ...item,
      comparable: {
        ...item.comparable,
        components: [...item.comparable.components].sort(compareText)
      }
    };
  }
  if (item.kind === "APPROVED_FINANCIAL_NORMALIZATION") {
    return {
      ...item,
      source: { ...item.source, components: [...item.source.components].sort(compareText) },
      target: { ...item.target, components: [...item.target.components].sort(compareText) }
    };
  }
  if (item.kind === "HISTORICAL_CONTEXT_SELECTION" && item.value?.claimCode === "CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION") {
    return {
      ...item,
      value: { ...item.value, citizenships: [...item.value.citizenships].sort(compareText) }
    };
  }
  return item;
}
function canonicalMethod(method) {
  return {
    ...method,
    sourceClassPolicies: sorted(method.sourceClassPolicies, (value) => `${value.sourceClassCode}\0${value.disposition}`),
    inputPolicies: sorted(method.inputPolicies, (value) => value.identity.id).map((policy) => ({
      ...policy,
      programFields: sorted(policy.programFields, (value) => `${value.recordType}\0${value.fieldName}`)
    })),
    mappingRelations: sorted(method.mappingRelations, (value) => value.relationRegistryId).map((relation) => ({
      ...relation,
      allowedAssessments: [...relation.allowedAssessments].sort(compareText)
    })),
    signalTypes: sorted(method.signalTypes, (value) => value.identity.id).map((signal) => ({
      ...signal,
      allowedInferenceCategories: [...signal.allowedInferenceCategories].sort(compareText)
    }))
  };
}
function canonicalContract(contract) {
  return {
    ...contract,
    semanticSourceClasses: sorted(contract.semanticSourceClasses, (value) => value.sourceClassRegistryId),
    mappingRelationDefinitions: sorted(contract.mappingRelationDefinitions, (value) => value.relationRegistryId),
    methods: {
      ACADEMIC: canonicalMethod(contract.methods.ACADEMIC),
      CAREER: canonicalMethod(contract.methods.CAREER),
      FINANCIAL: canonicalMethod(contract.methods.FINANCIAL),
      GEOGRAPHIC_DELIVERY: canonicalMethod(contract.methods.GEOGRAPHIC_DELIVERY),
      PERSONAL_PREFERENCE: canonicalMethod(contract.methods.PERSONAL_PREFERENCE),
      INTERNATIONAL_ACCESSIBILITY: canonicalMethod(contract.methods.INTERNATIONAL_ACCESSIBILITY)
    },
    reasons: sorted(contract.reasons, (value) => value.identity.id).map((reason) => ({
      ...reason,
      allowedAssessments: [...reason.allowedAssessments].sort(compareText)
    })),
    financialNormalizations: sorted(contract.financialNormalizations, (value) => value.identity.id)
  };
}
function canonicalInputState(state) {
  return { ...state, manifestItemKeys: [...state.manifestItemKeys].sort(compareText) };
}
function canonicalizeFitInput(input) {
  return {
    ...input,
    resolvedContract: canonicalContract(input.resolvedContract),
    methods: {
      ACADEMIC: { ...input.methods.ACADEMIC },
      CAREER: { ...input.methods.CAREER },
      FINANCIAL: { ...input.methods.FINANCIAL },
      GEOGRAPHIC_DELIVERY: { ...input.methods.GEOGRAPHIC_DELIVERY },
      PERSONAL_PREFERENCE: { ...input.methods.PERSONAL_PREFERENCE },
      INTERNATIONAL_ACCESSIBILITY: { ...input.methods.INTERNATIONAL_ACCESSIBILITY }
    },
    manifest: sorted(input.manifest.map(canonicalManifestItem), (item) => item.ref.manifestItemKey),
    inputStates: sorted(input.inputStates.map(canonicalInputState), (state) => `${state.methodRegistryId}\0${state.inputPolicyRegistryId}`)
  };
}
function canonicalSignals(signals) {
  return sorted(signals.map((signal) => ({
    ...signal,
    inputPolicyRegistryIds: [...signal.inputPolicyRegistryIds].sort(compareText),
    evidenceManifestRefs: [...signal.evidenceManifestRefs].sort(compareText)
  })), (signal) => `${signal.signalTypeRegistryId}\0${signal.intentManifestRef ?? ""}\0${signal.evidenceManifestRefs.join("\0")}`);
}
function canonicalReasons(reasons) {
  return sorted(reasons.map((reason) => ({
    ...reason,
    exactManifestRefs: [...reason.exactManifestRefs].sort(compareText)
  })), (reason) => `${reason.reasonDefinitionRegistryId}\0${reason.signalTypeRegistryId ?? ""}\0${reason.inputPolicyRegistryId ?? ""}`);
}
function canonicalLimitingInputs(inputs) {
  return sorted(inputs, (input) => `${input.inputPolicyRegistryId}\0${input.availability}`);
}
function jsonReady(value) {
  if (Array.isArray(value))
    return value.map(jsonReady);
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value).sort(([left], [right]) => compareText(left, right));
    const result = {};
    for (const [key, child] of entries)
      result[key] = jsonReady(child);
    return result;
  }
  return value;
}
function canonicalJson(value) {
  return JSON.stringify(jsonReady(value));
}
function deepFreeze(value) {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value))
      deepFreeze(child);
  }
  return value;
}

// ../fit-engine/dist/src/combine-signals.js
function combineSignals(facts) {
  if (facts.hasQualifiedStrongAlignment && !facts.hasMaterialSupport) {
    throw new Error("Qualified strong alignment requires material support");
  }
  if (facts.hasRequiredConstraintContradiction && !facts.hasMaterialContradiction) {
    throw new Error("A required contradiction must be material");
  }
  const hasDirection = facts.hasMaterialSupport || facts.hasMaterialContradiction || facts.hasQualifiedStrongAlignment;
  if (hasDirection !== facts.hasDirectionalBasis) {
    throw new Error("Directional basis projection is inconsistent");
  }
  if (facts.hasRequiredConstraintContradiction)
    return "MISALIGNMENT";
  if (facts.hasMaterialSupport && facts.hasMaterialContradiction)
    return "MIXED";
  if (facts.hasMaterialContradiction)
    return "MISALIGNMENT";
  if (facts.hasQualifiedStrongAlignment && facts.hasMaterialSupport) {
    return "STRONG_ALIGNMENT";
  }
  if (facts.hasMaterialSupport)
    return "ALIGNMENT";
  return "UNKNOWN";
}

// ../fit-engine/dist/src/confidence.js
function detectDirectionalSignalFacts(signals) {
  const directional = signals.filter((signal) => signal.material && signal.direction !== "LIMITING");
  const hasModel = directional.some((signal) => signal.inferenceCategory === "MODEL");
  const hasNonModel = directional.some((signal) => signal.inferenceCategory !== "MODEL");
  return {
    materialDirectionalCount: directional.length,
    hasNonModelMaterialDirection: hasNonModel,
    hasModelMaterialDirection: hasModel,
    isModelOnlyDirection: directional.length > 0 && !hasNonModel
  };
}

// ../fit-engine/dist/src/coverage.js
function detectInputStateFacts(states) {
  const unavailable = states.filter((state) => state.availability !== "INCLUDED");
  return {
    requiredUnavailable: unavailable.filter((state) => state.requirement === "REQUIRED"),
    optionalUnavailable: unavailable.filter((state) => state.requirement === "OPTIONAL"),
    included: states.filter((state) => state.availability === "INCLUDED"),
    hasSourceConflict: unavailable.some((state) => state.availability === "SOURCE_CONFLICT"),
    hasStaleSource: unavailable.some((state) => state.availability === "STALE_SOURCE")
  };
}
function availabilityReason(availability) {
  if (availability === "SOURCE_CONFLICT")
    return "SOURCE_CONFLICT";
  if (availability === "STALE_SOURCE")
    return "STALE_SOURCE";
  if (availability === "INAPPLICABLE")
    return "INPUT_INAPPLICABLE";
  if (availability === "INCOMPLETE")
    return "STUDENT_INPUT_INCOMPLETE";
  return "REQUIRED_INPUT_UNAVAILABLE";
}

// ../fit-engine/dist/src/decimal.js
function compareExactDecimal(left, right) {
  const parse = (value) => {
    const negative = value.startsWith("-");
    const unsigned = negative ? value.slice(1) : value;
    const [whole = "0", fraction = ""] = unsigned.split(".");
    return { negative, whole: whole.replace(/^0+(?=\d)/, ""), fraction: fraction.replace(/0+$/, "") };
  };
  const a = parse(left);
  const b = parse(right);
  const scale = Math.max(a.fraction.length, b.fraction.length);
  const magnitude = (value) => BigInt(`${value.whole}${value.fraction.padEnd(scale, "0")}` || "0") * (value.negative ? -1n : 1n);
  const aValue = magnitude(a);
  const bValue = magnitude(b);
  return aValue < bValue ? -1 : aValue > bValue ? 1 : 0;
}

// ../fit-engine/dist/src/reasons.js
function resolveReason(contract, dimension, code, assessment) {
  const reason = contract.reasons.find((candidate) => candidate.identity.code === code && (candidate.dimension === null || candidate.dimension === dimension));
  if (reason === void 0)
    throw new Error(`Reason ${code} is absent from the resolved registry`);
  if (!reason.allowedAssessments.includes(assessment)) {
    throw new Error(`Reason ${code} is incompatible with ${assessment}`);
  }
  return reason;
}
function reasonForSignal(contract, dimension, assessment, signal) {
  const code = signal.requiredConstraintContradiction ? "REQUIRED_CONSTRAINT_CONTRADICTED" : signal.direction === "SUPPORTING" ? "MATERIAL_EVIDENCE_SUPPORTS_ALIGNMENT" : signal.direction === "CONTRADICTING" ? "MATERIAL_EVIDENCE_CONTRADICTS_INTENT" : "EVIDENCE_INSUFFICIENT";
  const definition = resolveReason(contract, dimension, code, assessment);
  return {
    methodRegistryId: signal.methodRegistryId,
    reasonDefinitionRegistryId: definition.identity.id,
    reasonCode: code,
    direction: definition.direction,
    signalCode: signal.signalCode,
    signalTypeRegistryId: signal.signalTypeRegistryId,
    inputPolicyKey: null,
    inputPolicyRegistryId: signal.inputPolicyRegistryIds[0] ?? null,
    mappingRelationRegistryId: signal.mappingRelationRegistryId,
    exactManifestRefs: [
      ...signal.evidenceManifestRefs,
      ...signal.intentManifestRef === null ? [] : [signal.intentManifestRef]
    ]
  };
}
function limitingReason(contract, dimension, methodRegistryId, assessment, code, exactManifestRefs, state = null) {
  const definition = resolveReason(contract, dimension, code, assessment);
  return {
    methodRegistryId,
    reasonDefinitionRegistryId: definition.identity.id,
    reasonCode: code,
    direction: definition.direction,
    signalCode: null,
    signalTypeRegistryId: null,
    inputPolicyKey: state?.policyKey ?? null,
    inputPolicyRegistryId: state?.inputPolicyRegistryId ?? null,
    mappingRelationRegistryId: null,
    exactManifestRefs
  };
}
function limitingInput(contract, dimension, state, assessment) {
  if (state.availability === "INCLUDED")
    throw new Error("INCLUDED input is not limiting");
  const code = availabilityReason(state.availability);
  const definition = resolveReason(contract, dimension, code, assessment);
  return {
    methodRegistryId: state.methodRegistryId,
    reasonCode: code,
    reasonDefinitionRegistryId: definition.identity.id,
    inputPolicyKey: state.policyKey,
    inputPolicyRegistryId: state.inputPolicyRegistryId,
    availability: state.availability,
    completenessManifestRef: state.completenessManifestItemKey,
    provenanceManifestRef: state.provenanceManifestItemKey
  };
}
function reasonForUnavailableState(contract, dimension, state, assessment) {
  if (state.availability === "INCLUDED")
    throw new Error("INCLUDED input is not limiting");
  const refs = [state.completenessManifestItemKey, state.provenanceManifestItemKey].filter((value) => value !== null);
  return limitingReason(contract, dimension, state.methodRegistryId, assessment, availabilityReason(state.availability), refs, state);
}

// ../fit-engine/dist/src/dimensions/shared.js
function dimensionContext(input, dimension) {
  const method = input.resolvedContract.methods[dimension];
  return {
    input,
    dimension,
    method,
    methodInput: input.methods[dimension],
    items: input.manifest.filter((item) => item.ref.methodRegistryId === method.identity.id),
    states: input.inputStates.filter((state) => state.methodRegistryId === method.identity.id)
  };
}
function intentItems(context) {
  return context.items.filter((item) => item.kind === "FIT_INTENT" && item.intent.dimension === context.dimension);
}
function makeSignal(context, spec) {
  const registered = context.method.signalTypes.find((candidate) => candidate.identity.code === spec.code && candidate.direction === spec.direction && candidate.material === spec.material);
  if (registered === void 0)
    throw new Error(`Signal ${spec.code} is not registered for ${context.dimension}`);
  if (!registered.allowedInferenceCategories.includes(spec.inferenceCategory)) {
    throw new Error(`Signal ${spec.code} does not permit ${spec.inferenceCategory}`);
  }
  const relationId = spec.mappingRelationRegistryId ?? null;
  if (relationId !== null && !context.method.mappingRelations.some((relation) => relation.relationRegistryId === relationId)) {
    throw new Error("Signal uses an unregistered mapping relation");
  }
  return {
    methodRegistryId: context.method.identity.id,
    signalTypeRegistryId: registered.identity.id,
    inputPolicyRegistryIds: [...spec.inputPolicyRegistryIds].sort(compareText),
    mappingRelationRegistryId: relationId,
    signalCode: spec.code,
    direction: spec.direction,
    material: spec.material,
    inferenceCategory: spec.inferenceCategory,
    evidenceManifestRefs: spec.evidence.map((item) => item.ref.manifestItemKey).sort(compareText),
    intentManifestRef: spec.intent?.ref.manifestItemKey ?? null,
    requiredConstraintContradiction: spec.requiredConstraintContradiction ?? false,
    internationalHighImpact: spec.internationalHighImpact ?? false,
    model: null
  };
}
function finalizeDimension(context, spec) {
  const signals = canonicalSignals(spec.signals ?? []);
  const hasMaterialSupport = signals.some((signal) => signal.material && signal.direction === "SUPPORTING");
  const hasMaterialContradiction = signals.some((signal) => signal.material && signal.direction === "CONTRADICTING");
  const hasRequiredConstraintContradiction = signals.some((signal) => signal.requiredConstraintContradiction);
  const hasQualifiedStrongAlignment = spec.qualifiedStrongAlignment ?? false;
  if (hasQualifiedStrongAlignment) {
    if (!context.method.permitsStrongAlignment)
      throw new Error("Method forbids strong alignment");
    if (!signals.some((signal) => {
      const registered = context.method.signalTypes.find((candidate) => candidate.identity.id === signal.signalTypeRegistryId);
      return registered?.permitsStrongAlignment === true;
    })) {
      throw new Error("No registered signal qualifies strong alignment");
    }
  }
  const assessment = combineSignals({
    hasMaterialSupport,
    hasMaterialContradiction,
    hasRequiredConstraintContradiction,
    hasQualifiedStrongAlignment,
    hasDirectionalBasis: hasMaterialSupport || hasMaterialContradiction
  });
  for (const signal of signals) {
    if (signal.mappingRelationRegistryId === null)
      continue;
    const relation = context.method.mappingRelations.find((candidate) => candidate.relationRegistryId === signal.mappingRelationRegistryId);
    if (relation === void 0 || !relation.allowedAssessments.includes(assessment)) {
      throw new Error("Mapping relation does not authorize the resulting assessment");
    }
  }
  const directionalFacts = detectDirectionalSignalFacts(signals);
  if (directionalFacts.hasModelMaterialDirection && spec.confidence === "HIGH") {
    throw new Error("Material model involvement caps confidence below HIGH");
  }
  if (directionalFacts.isModelOnlyDirection && (assessment !== "UNKNOWN" || spec.confidence !== "LOW")) {
    throw new Error("Model-only direction must fail closed");
  }
  if (spec.coverage === "INSUFFICIENT" && assessment !== "UNKNOWN") {
    throw new Error("INSUFFICIENT coverage permits only UNKNOWN");
  }
  if (assessment === "UNKNOWN" && signals.some((signal) => signal.material)) {
    throw new Error("UNKNOWN cannot retain a material directional signal");
  }
  const reasons = signals.filter((signal) => signal.material).map((signal) => reasonForSignal(context.input.resolvedContract, context.dimension, assessment, signal));
  for (const item of spec.customLimitingReasons ?? []) {
    reasons.push(limitingReason(context.input.resolvedContract, context.dimension, context.method.identity.id, assessment, item.code, item.refs, item.state ?? null));
  }
  const limitingInputs = [];
  for (const state of spec.limitingStates ?? []) {
    reasons.push(reasonForUnavailableState(context.input.resolvedContract, context.dimension, state, assessment));
    limitingInputs.push(limitingInput(context.input.resolvedContract, context.dimension, state, assessment));
  }
  if (reasons.length === 0)
    throw new Error(`Dimension ${context.dimension} requires a structured reason`);
  const exactManifestRefs = /* @__PURE__ */ new Set();
  for (const signal of signals) {
    signal.evidenceManifestRefs.forEach((value) => exactManifestRefs.add(value));
    if (signal.intentManifestRef !== null)
      exactManifestRefs.add(signal.intentManifestRef);
  }
  for (const reason of reasons)
    reason.exactManifestRefs.forEach((value) => exactManifestRefs.add(value));
  for (const limiting of limitingInputs) {
    if (limiting.completenessManifestRef !== null)
      exactManifestRefs.add(limiting.completenessManifestRef);
    if (limiting.provenanceManifestRef !== null)
      exactManifestRefs.add(limiting.provenanceManifestRef);
  }
  const methodCode = context.methodInput.methodCode;
  return {
    dimension: context.dimension,
    methodRegistryId: context.method.identity.id,
    methodCode,
    methodVersion: 1,
    assessment,
    confidence: spec.confidence,
    evidenceCoverage: spec.coverage,
    inferenceCategory: context.methodInput.inferenceCategory,
    signals,
    reasons: canonicalReasons(reasons),
    limitingInputs: canonicalLimitingInputs(limitingInputs),
    exactManifestRefs: [...exactManifestRefs].sort(compareText)
  };
}
function requiredInputUnknown(context) {
  const facts = detectInputStateFacts(context.states);
  if (facts.requiredUnavailable.length === 0)
    return null;
  return finalizeDimension(context, {
    confidence: "LOW",
    coverage: "INSUFFICIENT",
    limitingStates: facts.requiredUnavailable
  });
}
function unknownDecision(context, code, refs = [], coverage = "INSUFFICIENT") {
  return finalizeDimension(context, {
    confidence: "LOW",
    coverage,
    customLimitingReasons: [{ code, refs }]
  });
}

// ../fit-engine/dist/src/dimensions/academic.js
function evaluateAcademic(input) {
  const context = dimensionContext(input, "ACADEMIC");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null)
    return requiredUnknown;
  const intents = intentItems(context).filter((item) => item.intent.kind === "TAXONOMY_TARGET");
  if (intents.length === 0)
    return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const mappings = context.items.filter((item) => item.kind === "VERIFIED_MAPPING");
  const courses = context.items.filter((item) => item.kind === "CANONICAL_PROGRAM_FACT" && item.fact.recordType === "PROGRAM_COURSE");
  const signals = [];
  let unmatched = false;
  let qualifiedStrong = false;
  for (const intent of intents) {
    if (intent.intent.kind !== "TAXONOMY_TARGET")
      continue;
    const conceptId = intent.intent.conceptId;
    const matches = mappings.filter((mapping) => mapping.conceptId === conceptId);
    if (matches.length === 0) {
      unmatched = true;
      continue;
    }
    for (const mapping of matches) {
      const course = courses.find((candidate) => candidate.ref.sourceId === mapping.ref.sourceId);
      const supports = intent.intent.relation === "DESIRED";
      const relationPolicy = context.method.mappingRelations.find((candidate) => candidate.relationRegistryId === mapping.relationRegistryId);
      if (relationPolicy === void 0 || !relationPolicy.allowedAssessments.includes(supports ? "ALIGNMENT" : "MISALIGNMENT")) {
        unmatched = true;
        continue;
      }
      const highImportance = intent.intent.authority.importance === "REQUIRED" || intent.intent.authority.importance === "STRONGLY_PREFERRED";
      const direct = supports && highImportance && course !== void 0;
      if (direct)
        qualifiedStrong = true;
      signals.push(makeSignal(context, {
        code: direct ? "DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH" : supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
        direction: supports ? "SUPPORTING" : "CONTRADICTING",
        material: true,
        inferenceCategory: direct ? "DETERMINISTIC" : "REVIEWED_MAPPING",
        evidence: course === void 0 ? [mapping] : [mapping, course],
        intent,
        inputPolicyRegistryIds: [mapping.ref.inputPolicyRegistryId],
        mappingRelationRegistryId: direct ? null : mapping.relationRegistryId,
        requiredConstraintContradiction: !supports && intent.intent.authority.importance === "REQUIRED"
      }));
    }
  }
  if (signals.length === 0) {
    return unknownDecision(context, unmatched ? "NO_AUTHORITATIVE_MAPPING" : "EVIDENCE_INSUFFICIENT", intents.map((item) => item.ref.manifestItemKey));
  }
  return finalizeDimension(context, {
    signals,
    qualifiedStrongAlignment: qualifiedStrong,
    confidence: qualifiedStrong ? "HIGH" : "MEDIUM",
    coverage: unmatched ? "PARTIAL" : "SUFFICIENT"
  });
}

// ../fit-engine/dist/src/dimensions/career.js
function evaluateCareer(input) {
  const context = dimensionContext(input, "CAREER");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null)
    return requiredUnknown;
  const intents = intentItems(context).filter((item) => item.intent.kind === "TAXONOMY_TARGET");
  if (intents.length === 0)
    return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const mappings = context.items.filter((item) => item.kind === "VERIFIED_MAPPING" && ["CAREER_ASSOCIATION", "INDUSTRY_ASSOCIATION", "PROGRAM_RELATED_TO_CAREER"].includes(item.relation));
  const signals = [];
  let unmatched = false;
  for (const intent of intents) {
    if (intent.intent.kind !== "TAXONOMY_TARGET")
      continue;
    const conceptId = intent.intent.conceptId;
    const matches = mappings.filter((mapping) => mapping.conceptId === conceptId);
    if (matches.length === 0) {
      unmatched = true;
      continue;
    }
    for (const mapping of matches) {
      const supports = intent.intent.relation === "DESIRED";
      const relationPolicy = context.method.mappingRelations.find((candidate) => candidate.relationRegistryId === mapping.relationRegistryId);
      if (relationPolicy === void 0 || !relationPolicy.allowedAssessments.includes(supports ? "ALIGNMENT" : "MISALIGNMENT")) {
        unmatched = true;
        continue;
      }
      signals.push(makeSignal(context, {
        code: supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
        direction: supports ? "SUPPORTING" : "CONTRADICTING",
        material: true,
        inferenceCategory: "REVIEWED_MAPPING",
        evidence: [mapping],
        intent,
        inputPolicyRegistryIds: [mapping.ref.inputPolicyRegistryId],
        mappingRelationRegistryId: mapping.relationRegistryId,
        requiredConstraintContradiction: !supports && intent.intent.authority.importance === "REQUIRED"
      }));
    }
  }
  if (signals.length === 0) {
    return unknownDecision(context, unmatched ? "NO_AUTHORITATIVE_MAPPING" : "EVIDENCE_INSUFFICIENT", intents.map((item) => item.ref.manifestItemKey));
  }
  return finalizeDimension(context, {
    signals,
    confidence: "MEDIUM",
    coverage: unmatched ? "PARTIAL" : "SUFFICIENT"
  });
}

// ../fit-engine/dist/src/dimensions/financial.js
function comparableMatchesIntent(comparable, intent) {
  return comparable.currency === intent.currency && comparable.period === intent.period && comparable.scope === intent.scope && comparable.basis === intent.basis && [...comparable.components].sort(compareText).join("\0") === [...intent.components].sort(compareText).join("\0");
}
function evaluateFinancial(input) {
  const context = dimensionContext(input, "FINANCIAL");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null)
    return requiredUnknown;
  const intents = intentItems(context).filter((item) => item.intent.kind === "FINANCIAL_CONSTRAINT" && item.intent.semantics !== "AVAILABLE_FUNDING");
  if (intents.length === 0)
    return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const direct = context.items.filter((item) => item.kind === "DIRECT_FINANCIAL_COMPARABLE");
  const normalized = context.items.filter((item) => item.kind === "APPROVED_FINANCIAL_NORMALIZATION");
  const signals = [];
  let usedNormalization = false;
  for (const intentItem of intents) {
    if (intentItem.intent.kind !== "FINANCIAL_CONSTRAINT")
      continue;
    const candidates = [
      ...direct.filter((item) => item.financialConstraintIntentId === intentItem.intent.intentId).map((item) => ({ item, comparable: item.comparable, normalized: false })),
      ...normalized.filter((item) => item.financialConstraintIntentId === intentItem.intent.intentId).map((item) => ({ item, comparable: item.target, normalized: true }))
    ];
    if (candidates.length !== 1) {
      return unknownDecision(context, "FINANCIAL_INPUTS_INCOMPARABLE", [intentItem.ref.manifestItemKey, ...candidates.map(({ item }) => item.ref.manifestItemKey)]);
    }
    const candidate = candidates[0];
    if (candidate === void 0 || !comparableMatchesIntent(candidate.comparable, intentItem.intent)) {
      return unknownDecision(context, "FINANCIAL_INPUTS_INCOMPARABLE", [intentItem.ref.manifestItemKey, ...candidate === void 0 ? [] : [candidate.item.ref.manifestItemKey]]);
    }
    usedNormalization ||= candidate.normalized;
    const supports = compareExactDecimal(candidate.comparable.amount, intentItem.intent.amount) <= 0;
    const isHard = intentItem.intent.semantics === "HARD_TOTAL_COST_CEILING" || intentItem.intent.semantics === "HARD_TUITION_CEILING";
    signals.push(makeSignal(context, {
      code: supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
      direction: supports ? "SUPPORTING" : "CONTRADICTING",
      material: true,
      inferenceCategory: "DETERMINISTIC",
      evidence: [candidate.item],
      intent: intentItem,
      inputPolicyRegistryIds: [candidate.item.ref.inputPolicyRegistryId],
      requiredConstraintContradiction: !supports && isHard && intentItem.intent.authority.importance === "REQUIRED"
    }));
  }
  return finalizeDimension(context, {
    signals,
    confidence: usedNormalization ? "MEDIUM" : "HIGH",
    coverage: "SUFFICIENT"
  });
}

// ../fit-engine/dist/src/dimensions/geographic-delivery.js
function evaluateGeographicDelivery(input) {
  const context = dimensionContext(input, "GEOGRAPHIC_DELIVERY");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null)
    return requiredUnknown;
  const intents = intentItems(context);
  if (intents.length === 0)
    return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const locationIntents = intents.filter((item) => item.intent.kind === "LOCATION_CONSTRAINT");
  const deliveryIntents = intents.filter((item) => item.intent.kind === "DELIVERY_CONSTRAINT");
  const deliveryFact = context.items.find((item) => item.kind === "CANONICAL_PROGRAM_FACT" && item.fact.recordType === "PROGRAM_VERSION" && item.fact.field === "delivery_mode" && item.fact.value !== "UNKNOWN");
  if (deliveryIntents.length === 0 || deliveryFact === void 0) {
    return unknownDecision(context, "PROGRAM_FACT_UNKNOWN", intents.map((item) => item.ref.manifestItemKey), locationIntents.length > 0 && deliveryFact !== void 0 ? "PARTIAL" : "INSUFFICIENT");
  }
  const signals = [];
  for (const intent of deliveryIntents) {
    if (intent.intent.kind !== "DELIVERY_CONSTRAINT")
      continue;
    const equal = deliveryFact.fact.value === intent.intent.deliveryMode;
    const supports = intent.intent.relation === "DESIRED" ? equal : !equal;
    const requiredContradiction = !supports && intent.intent.authority.importance === "REQUIRED";
    if (locationIntents.length > 0 && !requiredContradiction)
      continue;
    signals.push(makeSignal(context, {
      code: supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
      direction: supports ? "SUPPORTING" : "CONTRADICTING",
      material: true,
      inferenceCategory: "DETERMINISTIC",
      evidence: [deliveryFact],
      intent,
      inputPolicyRegistryIds: [deliveryFact.ref.inputPolicyRegistryId],
      requiredConstraintContradiction: requiredContradiction
    }));
  }
  if (locationIntents.length > 0 && signals.length === 0) {
    return unknownDecision(context, "PROGRAM_FACT_UNKNOWN", [
      deliveryFact.ref.manifestItemKey,
      ...locationIntents.map((item) => item.ref.manifestItemKey)
    ], "PARTIAL");
  }
  return finalizeDimension(context, {
    signals,
    confidence: locationIntents.length > 0 ? "MEDIUM" : "HIGH",
    coverage: locationIntents.length > 0 ? "PARTIAL" : "SUFFICIENT"
  });
}

// ../fit-engine/dist/src/dimensions/international-accessibility.js
function currentAt(item, asOf) {
  const at = Date.parse(asOf);
  return Date.parse(item.validFrom) <= at && (item.validTo === null || at <= Date.parse(item.validTo));
}
function evaluateInternationalAccessibility(input) {
  const context = dimensionContext(input, "INTERNATIONAL_ACCESSIBILITY");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null)
    return requiredUnknown;
  const intents = intentItems(context).filter((item) => item.intent.kind === "TAXONOMY_TARGET");
  if (intents.length === 0)
    return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const access = context.items.find((item) => item.kind === "STUDENT_ACCESS_CONTEXT");
  if (access === void 0) {
    return unknownDecision(context, "REQUIRED_INPUT_UNAVAILABLE", intents.map((item) => item.ref.manifestItemKey));
  }
  const mappings = context.items.filter((item) => item.kind === "VERIFIED_MAPPING" && ["PROGRAM_ASSOCIATED_WITH_PATH", "CLAIM_APPLIES_TO_CONCEPT"].includes(item.relation));
  const claims = context.items.filter((item) => item.kind === "HISTORICAL_CONTEXT_SELECTION" && item.knowledgeStatus === "KNOWN" && item.observationWorkflowStatusAtSelection === "VERIFIED" && item.authority === "OFFICIAL_REGULATORY" && item.value !== null && currentAt(item, input.evaluationAsOf));
  const signals = [];
  for (const intent of intents) {
    if (intent.intent.kind !== "TAXONOMY_TARGET")
      continue;
    const conceptId = intent.intent.conceptId;
    const relation = mappings.find((mapping) => mapping.conceptId === conceptId);
    const claim = claims.find((candidate) => (candidate.programVersionId === null || candidate.programVersionId === input.programVersionId) && (candidate.jurisdictionCode === null || candidate.jurisdictionCode === access.jurisdictionCode) && (candidate.pathCode === null || candidate.pathCode === access.targetPathCode));
    if (relation === void 0 || claim === void 0 || claim.value === null) {
      return unknownDecision(context, "INTERNATIONAL_EVIDENCE_INAPPLICABLE", [intent.ref.manifestItemKey, access.ref.manifestItemKey]);
    }
    const value = claim.value;
    const accessible = value.claimCode === "REGULATORY_WORK_AUTHORIZATION" ? value.allowed : value.claimCode === "JURISDICTION_PATH_ACCESSIBILITY" ? value.accessible : value.claimCode === "LICENSING_RESTRICTION" || value.claimCode === "CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION" ? !value.restricted : void 0;
    if (accessible === void 0) {
      return unknownDecision(context, "INTERNATIONAL_EVIDENCE_INAPPLICABLE", [claim.ref.manifestItemKey]);
    }
    const supports = intent.intent.relation === "DESIRED" ? accessible : !accessible;
    signals.push(makeSignal(context, {
      code: supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
      direction: supports ? "SUPPORTING" : "CONTRADICTING",
      material: true,
      inferenceCategory: "HYBRID",
      evidence: [claim, relation, access],
      intent,
      inputPolicyRegistryIds: [
        claim.ref.inputPolicyRegistryId,
        relation.ref.inputPolicyRegistryId,
        access.ref.inputPolicyRegistryId
      ],
      mappingRelationRegistryId: relation.relationRegistryId,
      requiredConstraintContradiction: !supports && intent.intent.authority.importance === "REQUIRED",
      internationalHighImpact: true
    }));
  }
  return finalizeDimension(context, {
    signals,
    confidence: "HIGH",
    coverage: "SUFFICIENT"
  });
}

// ../fit-engine/dist/src/dimensions/personal-preference.js
function evaluatePersonalPreference(input) {
  const context = dimensionContext(input, "PERSONAL_PREFERENCE");
  const requiredUnknown = requiredInputUnknown(context);
  if (requiredUnknown !== null)
    return requiredUnknown;
  const intents = intentItems(context);
  if (intents.length === 0)
    return unknownDecision(context, "STUDENT_PREFERENCE_UNSPECIFIED");
  const facts = context.items.filter((item) => item.kind === "CANONICAL_PROGRAM_FACT" && item.fact.recordType === "PROGRAM_VERSION");
  const signals = [];
  for (const intent of intents) {
    let fact;
    let supports;
    if (intent.intent.kind === "DURATION_CONSTRAINT") {
      fact = facts.find((candidate) => candidate.fact.field === "duration_months");
      if (fact !== void 0 && fact.fact.field === "duration_months") {
        const aboveMinimum = intent.intent.minimumMonths === null || compareExactDecimal(fact.fact.value, intent.intent.minimumMonths) >= 0;
        const belowMaximum = intent.intent.maximumMonths === null || compareExactDecimal(fact.fact.value, intent.intent.maximumMonths) <= 0;
        supports = aboveMinimum && belowMaximum;
      }
    } else if (intent.intent.kind === "PROGRAM_FEATURE_CONSTRAINT" && intent.intent.feature === "CAPSTONE_AVAILABLE") {
      fact = facts.find((candidate) => candidate.fact.field === "capstone_required");
      if (fact !== void 0 && fact.fact.field === "capstone_required") {
        supports = fact.fact.value === intent.intent.expected;
      }
    } else {
      return unknownDecision(context, "PROGRAM_FACT_UNKNOWN", [intent.ref.manifestItemKey]);
    }
    if (fact === void 0 || supports === void 0) {
      return unknownDecision(context, "PROGRAM_FACT_UNKNOWN", [intent.ref.manifestItemKey]);
    }
    signals.push(makeSignal(context, {
      code: supports ? "MATERIAL_SUPPORT" : "MATERIAL_CONTRADICTION",
      direction: supports ? "SUPPORTING" : "CONTRADICTING",
      material: true,
      inferenceCategory: "DETERMINISTIC",
      evidence: [fact],
      intent,
      inputPolicyRegistryIds: [fact.ref.inputPolicyRegistryId],
      requiredConstraintContradiction: !supports && intent.intent.authority.importance === "REQUIRED"
    }));
  }
  return finalizeDimension(context, {
    signals,
    confidence: "HIGH",
    coverage: "SUFFICIENT"
  });
}

// ../fit-engine/dist/src/validate-contract.js
var FitContractError = class extends Error {
  name = "FitContractError";
};
var METHOD_CONTRACT = {
  ACADEMIC: {
    code: "ACADEMIC_ALIGNMENT_V01",
    inferenceCategory: "HYBRID",
    permitsStrongAlignment: true
  },
  CAREER: {
    code: "CAREER_ALIGNMENT_V01",
    inferenceCategory: "HYBRID",
    permitsStrongAlignment: false
  },
  FINANCIAL: {
    code: "FINANCIAL_ALIGNMENT_V01",
    inferenceCategory: "DETERMINISTIC",
    permitsStrongAlignment: false
  },
  GEOGRAPHIC_DELIVERY: {
    code: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01",
    inferenceCategory: "HYBRID",
    permitsStrongAlignment: false
  },
  PERSONAL_PREFERENCE: {
    code: "PERSONAL_PREFERENCE_ALIGNMENT_V01",
    inferenceCategory: "HYBRID",
    permitsStrongAlignment: false
  },
  INTERNATIONAL_ACCESSIBILITY: {
    code: "INTERNATIONAL_ACCESSIBILITY_V01",
    inferenceCategory: "HYBRID",
    permitsStrongAlignment: false
  }
};
function fail(message) {
  throw new FitContractError(message);
}
function requireValue(condition, message) {
  if (!condition)
    fail(message);
}
function requireText(value, label) {
  requireValue(value.trim().length > 0, `${label} is required`);
}
function requireIsoDate(value, label) {
  requireText(value, label);
  requireValue(Number.isFinite(Date.parse(value)), `${label} must be an ISO timestamp`);
}
function assertExactKeys(value, expected, label) {
  const actual = Object.keys(value).sort();
  const required = [...expected].sort();
  requireValue(actual.length === required.length && actual.every((key, index) => key === required[index]), `${label} is not an exact closed object`);
}
function assertExactDecimal(value, label) {
  requireValue(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(value), `${label} must be an exact decimal string`);
}
function assertUnique(values, label) {
  const seen = /* @__PURE__ */ new Set();
  for (const value of values) {
    requireText(value, label);
    if (seen.has(value))
      fail(`Duplicate ${label}: ${value}`);
    seen.add(value);
  }
}
function assertNoProhibitedDecisionKeys(value, path = "input") {
  if (Array.isArray(value)) {
    value.forEach((child, index) => assertNoProhibitedDecisionKeys(child, `${path}[${index}]`));
    return;
  }
  if (value === null || typeof value !== "object")
    return;
  for (const [key, child] of Object.entries(value)) {
    if (/(eligibility|competitiveness|admissionProbability|acceptanceLikelihood|recommendation|prestige|ranking|percentile|score|weight)/i.test(key)) {
      fail(`Prohibited decision field at ${path}.${key}`);
    }
    assertNoProhibitedDecisionKeys(child, `${path}.${key}`);
  }
}
function validateIntent(intent) {
  const intentKeys = {
    TAXONOMY_TARGET: ["kind", "intentId", "dimension", "authority", "conceptId", "relation"],
    LOCATION_CONSTRAINT: ["kind", "intentId", "dimension", "authority", "relation", "countryCode", "regionCode", "locality"],
    DELIVERY_CONSTRAINT: ["kind", "intentId", "dimension", "authority", "deliveryMode", "relation"],
    FINANCIAL_CONSTRAINT: ["kind", "intentId", "dimension", "authority", "amount", "semantics", "currency", "scope", "period", "basis", "components"],
    DURATION_CONSTRAINT: ["kind", "intentId", "dimension", "authority", "minimumMonths", "maximumMonths"],
    PROGRAM_FEATURE_CONSTRAINT: ["kind", "intentId", "dimension", "authority", "feature", "expected"]
  };
  assertExactKeys(intent, intentKeys[intent.kind], `${intent.kind} intent`);
  assertExactKeys(intent.authority, ["importance", "basis", "importanceEvidenceManifestKey", "confirmedByStudent"], "intent authority");
  requireText(intent.intentId, "intentId");
  if (intent.authority.importance === "REQUIRED") {
    requireValue(intent.authority.confirmedByStudent, "REQUIRED intent must be confirmed by the student");
    requireValue(intent.authority.importanceEvidenceManifestKey !== null, "REQUIRED intent must carry importance evidence");
  }
  if (intent.kind === "FINANCIAL_CONSTRAINT") {
    assertExactDecimal(intent.amount, "financial amount");
    assertUnique(intent.components, "financial component");
  }
  if (intent.kind === "DURATION_CONSTRAINT") {
    if (intent.minimumMonths !== null)
      assertExactDecimal(intent.minimumMonths, "minimumMonths");
    if (intent.maximumMonths !== null)
      assertExactDecimal(intent.maximumMonths, "maximumMonths");
    requireValue(intent.minimumMonths !== null || intent.maximumMonths !== null, "Duration intent requires at least one bound");
  }
  if (intent.kind === "LOCATION_CONSTRAINT") {
    requireValue(intent.countryCode !== null || intent.regionCode !== null || intent.locality !== null, "Location intent requires an explicit location");
  }
  if (intent.kind === "PROGRAM_FEATURE_CONSTRAINT") {
    const personal = /* @__PURE__ */ new Set([
      "CAPSTONE_AVAILABLE",
      "RESEARCH_OPPORTUNITY",
      "FACULTY_ACCESS",
      "COHORT_STRUCTURE"
    ]);
    if (intent.dimension === "PERSONAL_PREFERENCE") {
      requireValue(personal.has(intent.feature), "Personal Preference received another dimension's semantics");
    } else {
      requireValue(intent.feature === "INTERNATIONAL_PATH_SUPPORT", "International Accessibility received Personal Preference semantics");
    }
  }
}
function validateMethodContract(dimension, method) {
  const expected = METHOD_CONTRACT[dimension];
  requireValue(method.dimension === dimension, `Resolved method dimension drift for ${dimension}`);
  requireValue(method.identity.code === expected.code, `Resolved method code drift for ${dimension}`);
  requireValue(method.identity.version === "1", `Resolved method version drift for ${dimension}`);
  requireValue(method.inferenceCategory === expected.inferenceCategory, `Resolved inference category drift for ${dimension}`);
  requireValue(method.permitsStrongAlignment === expected.permitsStrongAlignment, `Resolved strong-alignment permission drift for ${dimension}`);
  requireValue(method.definitionState.status === "VERIFIED", `${dimension} method is not verified`);
  requireValue(method.definitionState.retiredAt === null, `${dimension} method is retired`);
  requireText(method.materialityContractCanonicalJson, `${dimension} materiality contract`);
  JSON.parse(method.materialityContractCanonicalJson);
  assertUnique(method.inputPolicies.map((policy) => policy.identity.id), `${dimension} policy id`);
  assertUnique(method.inputPolicies.map((policy) => policy.policyKey), `${dimension} policy key`);
  assertUnique(method.signalTypes.map((signal) => signal.identity.id), `${dimension} signal id`);
  assertUnique(method.signalTypes.map((signal) => signal.identity.code), `${dimension} signal code`);
  assertUnique(method.mappingRelations.map((relation) => relation.relationRegistryId), `${dimension} relation id`);
  requireValue(method.inputPolicies.length > 0, `${dimension} has no input policies`);
  requireValue(method.signalTypes.length > 0, `${dimension} has no signal types`);
  for (const policy of method.inputPolicies) {
    requireValue(policy.methodRegistryId === method.identity.id, "Policy/method identity drift");
    requireValue(policy.identity.version === "1", "Input-policy version drift");
    requireValue(policy.disposition === "ALLOWED" || policy.disposition === "FORBIDDEN", "Invalid policy disposition");
    assertUnique(policy.programFields.map((field) => `${field.recordType}\0${field.fieldName}`), "program field tuple");
    for (const field of policy.programFields) {
      requireValue(field.methodRegistryId === method.identity.id, "Program field method drift");
      requireValue(field.inputPolicyRegistryId === policy.identity.id, "Program field policy drift");
    }
  }
  for (const signal of method.signalTypes) {
    requireValue(signal.methodRegistryId === method.identity.id, "Signal/method identity drift");
    requireValue(signal.allowedInferenceCategories.includes(method.inferenceCategory), "Method inference category is not allowed by its signal registry");
  }
}
function validateManifestItem(item, dimension, input) {
  const itemKeys = {
    FIT_INTENT: ["kind", "ref", "intent"],
    STUDENT_ACCESS_CONTEXT: ["kind", "ref", "citizenshipCountryCode", "residenceCountryCode", "jurisdictionCode", "currentStatusCode", "authorizationPathCode", "targetPathCode"],
    PHASE2_GOAL: ["kind", "ref", "exposedFields", "goalType", "conceptId", "goalText"],
    PHASE2_PREFERENCE: ["kind", "ref", "exposedFields", "preferenceType", "value"],
    PHASE2_COURSE: ["kind", "ref", "exposedFields", "courseCode", "courseTitle", "courseStatus", "term"],
    PHASE2_COMPLETENESS: ["kind", "ref", "educationContextId", "domain", "completeness"],
    VERIFIED_MAPPING: ["kind", "ref", "mappingKind", "relationRegistryId", "relation", "conceptId", "statusAtPin", "reviewedAtAtPin", "verificationEvidenceIdAtPin", "retiredAtAtPin"],
    TAXONOMY_CONCEPT: ["kind", "ref", "conceptId", "activeInPinnedRelease"],
    CANONICAL_PROGRAM_FACT: ["kind", "ref", "recordId", "knowledgeStatus", "selectedObservationId", "fact"],
    HISTORICAL_CONTEXT_SELECTION: ["kind", "ref", "claimId", "selectionId", "observationId", "knowledgeStatus", "observationWorkflowStatusAtSelection", "observationReviewedAtAtSelection", "authority", "validFrom", "validTo", "programVersionId", "geographyCode", "jurisdictionCode", "pathCode", "value"],
    DIRECT_FINANCIAL_COMPARABLE: ["kind", "ref", "sourcePinId", "financialContractVersion", "financialConstraintIntentId", "comparable"],
    APPROVED_FINANCIAL_NORMALIZATION: ["kind", "ref", "normalizationId", "fieldObservationId", "financialConstraintIntentId", "intentSetId", "financialContractVersion", "methodCode", "methodVersion", "verificationEvidenceId", "source", "target", "conversionEvidenceId"]
  };
  assertExactKeys(item, itemKeys[item.kind], `${item.kind} manifest item`);
  assertExactKeys(item.ref, ["manifestItemKey", "sourceId", "methodRegistryId", "inputPolicyRegistryId", "methodCode", "policyKey", "sourceClass", "authorityRole"], "manifest ref");
  const method = input.resolvedContract.methods[dimension];
  requireValue(item.ref.methodRegistryId === method.identity.id, "Manifest method identity drift");
  requireValue(item.ref.methodCode === METHOD_CONTRACT[dimension].code, "Manifest method code drift");
  const policy = method.inputPolicies.find((candidate) => candidate.identity.id === item.ref.inputPolicyRegistryId);
  requireValue(policy !== void 0, "Manifest references an unknown input policy");
  requireValue(policy.policyKey === item.ref.policyKey, "Manifest policy-key identity drift");
  requireValue(policy.disposition === "ALLOWED", "Manifest uses a forbidden input policy");
  const allowedDomains = item.kind === "FIT_INTENT" ? ["FIT_INTENTS"] : item.kind === "STUDENT_ACCESS_CONTEXT" ? ["FIT_ACCESS_CONTEXT"] : item.kind === "PHASE2_GOAL" ? ["STUDENT_GOALS"] : item.kind === "PHASE2_PREFERENCE" ? ["STUDENT_PREFERENCES"] : item.kind === "PHASE2_COURSE" ? ["STUDENT_COURSES"] : item.kind === "PHASE2_COMPLETENESS" ? ["STUDENT_COMPLETENESS"] : item.kind === "VERIFIED_MAPPING" ? ["CATALOG_MAPPINGS", "STUDENT_MAPPINGS", "FIT_CONTEXT_CLAIMS", "TAXONOMY_CONCEPTS"] : item.kind === "TAXONOMY_CONCEPT" ? ["TAXONOMY_CONCEPTS"] : item.kind === "CANONICAL_PROGRAM_FACT" ? ["PROGRAM_COURSES", "PROGRAM_COSTS", "PROGRAM_VERSIONS"] : item.kind === "HISTORICAL_CONTEXT_SELECTION" ? ["FIT_CONTEXT_CLAIMS"] : item.kind === "DIRECT_FINANCIAL_COMPARABLE" ? ["PROGRAM_COSTS"] : ["FINANCIAL_NORMALIZATIONS"];
  requireValue(allowedDomains.includes(policy.inputDomain), `Manifest kind ${item.kind} is incompatible with policy domain ${policy.inputDomain}`);
  const sourceClass = input.resolvedContract.semanticSourceClasses.find((candidate) => candidate.sourceClassCode === item.ref.sourceClass);
  requireValue(sourceClass !== void 0 && sourceClass.fitPermitted, "Manifest uses a prohibited source class");
  const sourcePolicy = method.sourceClassPolicies.find((candidate) => candidate.sourceClassCode === item.ref.sourceClass);
  requireValue(sourcePolicy?.disposition === "ALLOWED", "Method does not allow the manifest source class");
  if (item.kind === "FIT_INTENT") {
    validateIntent(item.intent);
    requireValue(item.intent.dimension === dimension, "Intent crossed a dimension boundary");
  }
  if (item.kind === "VERIFIED_MAPPING") {
    requireValue(item.retiredAtAtPin === null, "Retired mapping entered the decision manifest");
    requireText(item.verificationEvidenceIdAtPin, "mapping verification evidence");
    requireIsoDate(item.reviewedAtAtPin, "mapping reviewedAt");
    const definition = input.resolvedContract.mappingRelationDefinitions.find((candidate) => candidate.relationRegistryId === item.relationRegistryId);
    requireValue(definition?.relationCode === item.relation, "Mapping relation definition drift");
    requireValue(method.mappingRelations.some((candidate) => candidate.relationRegistryId === item.relationRegistryId && candidate.relationCode === item.relation), "Mapping relation is not permitted by the method");
  }
  if (item.kind === "HISTORICAL_CONTEXT_SELECTION") {
    requireIsoDate(item.validFrom, "context validFrom");
    if (item.validTo !== null)
      requireIsoDate(item.validTo, "context validTo");
    if (item.knowledgeStatus === "KNOWN") {
      requireValue(item.value !== null, "KNOWN context selection requires a typed value");
      requireValue(item.observationWorkflowStatusAtSelection === "VERIFIED", "KNOWN context selection must be verified");
    }
  }
  if (item.kind === "CANONICAL_PROGRAM_FACT") {
    requireValue(policy.programFields.some((field) => field.recordType === item.fact.recordType && field.fieldName === item.fact.field), "Canonical program fact is outside the exact policy field allowlist");
  }
  if (item.kind === "DIRECT_FINANCIAL_COMPARABLE") {
    requireValue(dimension === "FINANCIAL", "Direct Financial comparable crossed dimensions");
    requireValue(item.financialContractVersion === "FINANCIAL_BILLING_BASIS_V014", "Unknown direct Financial contract version");
    assertExactDecimal(item.comparable.amount, "direct comparable amount");
    assertUnique(item.comparable.components, "direct comparable component");
  }
  if (item.kind === "APPROVED_FINANCIAL_NORMALIZATION") {
    requireValue(dimension === "FINANCIAL", "Financial normalization crossed dimensions");
    requireValue(item.financialContractVersion === "FINANCIAL_BILLING_BASIS_V014", "Unknown Financial normalization contract");
    const normalization = input.resolvedContract.financialNormalizations.find((candidate) => candidate.identity.id === item.normalizationId);
    requireValue(normalization !== void 0, "Normalization is absent from the resolved registry");
    requireValue(normalization.identity.code === item.methodCode && normalization.identity.version === String(item.methodVersion), "Normalization method identity drift");
    requireValue(normalization.definitionState.status === "VERIFIED" && normalization.definitionState.retiredAt === null, "Normalization method is not active and verified");
    requireValue(normalization.sourceScope === item.source.scope && normalization.targetScope === item.target.scope && normalization.sourcePeriod === item.source.period && normalization.targetPeriod === item.target.period && normalization.sourceBasis === item.source.basis && normalization.targetBasis === item.target.basis && (normalization.sourceCurrency === null || normalization.sourceCurrency === item.source.currency) && (normalization.targetCurrency === null || normalization.targetCurrency === item.target.currency), "Normalization semantic contract drift");
    assertExactDecimal(item.source.amount, "normalization source amount");
    assertExactDecimal(item.target.amount, "normalization target amount");
    assertUnique(item.source.components, "normalization source component");
    assertUnique(item.target.components, "normalization target component");
  }
}
function validateFitInput(input) {
  assertExactKeys(input, ["schemaVersion", "contractRelease", "resolvedContract", "evaluator", "evaluationAsOf", "profile", "intentSet", "programVersionId", "taxonomyReleaseCode", "methods", "manifest", "inputStates"], "FitEvaluationInput");
  assertNoProhibitedDecisionKeys(input);
  requireValue(input.schemaVersion === "fit-v0.1", "Unsupported Fit schema version");
  requireIsoDate(input.evaluationAsOf, "evaluationAsOf");
  requireValue(input.contractRelease.releaseCode === "fit-v0.1", "Unsupported Fit release");
  requireValue(input.contractRelease.specificationVersion === "v0.1", "Unsupported Fit specification");
  requireValue(input.resolvedContract.release.code === "fit-v0.1", "Resolved release code drift");
  requireValue(input.resolvedContract.release.version === "v0.1", "Resolved release version drift");
  requireValue(input.contractRelease.registryId === input.resolvedContract.release.id && input.contractRelease.digest === input.resolvedContract.release.specificationDigest, "Release identity or digest drift");
  requireValue(input.resolvedContract.release.definitionState.status === "VERIFIED", "Release is not verified");
  requireValue(input.resolvedContract.release.definitionState.retiredAt === null, "Release is retired");
  requireValue(input.evaluator.registryId === input.resolvedContract.evaluatorBuild.id && input.evaluator.name === input.resolvedContract.evaluatorBuild.evaluatorName && input.evaluator.version === input.resolvedContract.evaluatorBuild.evaluatorVersion && input.evaluator.buildHash === input.resolvedContract.evaluatorBuild.buildHash, "Evaluator-build identity drift");
  requireValue(input.resolvedContract.evaluatorBuild.definitionState.status === "VERIFIED" && input.resolvedContract.evaluatorBuild.definitionState.retiredAt === null, "Evaluator build is not active and verified");
  requireText(input.profile.versionId, "profile version");
  requireText(input.profile.snapshotHash, "profile snapshot hash");
  requireText(input.intentSet.id, "intent set");
  requireText(input.intentSet.snapshotHash, "intent snapshot hash");
  requireText(input.programVersionId, "program version");
  requireText(input.taxonomyReleaseCode, "taxonomy release");
  const methodKeys = Object.keys(input.methods).sort();
  const contractMethodKeys = Object.keys(input.resolvedContract.methods).sort();
  const expectedKeys = [...FIT_DIMENSIONS].sort();
  requireValue(JSON.stringify(methodKeys) === JSON.stringify(expectedKeys), "Exactly six input methods are required");
  requireValue(JSON.stringify(contractMethodKeys) === JSON.stringify(expectedKeys), "Resolved contract must contain exactly six methods");
  assertUnique(input.resolvedContract.semanticSourceClasses.map((value) => value.sourceClassRegistryId), "semantic source-class id");
  assertUnique(input.resolvedContract.semanticSourceClasses.map((value) => value.sourceClassCode), "semantic source-class code");
  assertUnique(input.resolvedContract.mappingRelationDefinitions.map((value) => value.relationRegistryId), "mapping relation id");
  assertUnique(input.resolvedContract.reasons.map((reason) => reason.identity.id), "reason id");
  assertUnique(input.resolvedContract.reasons.map((reason) => reason.identity.code), "reason code");
  assertUnique(input.resolvedContract.financialNormalizations.map((value) => value.identity.id), "financial normalization id");
  for (const reason of input.resolvedContract.reasons) {
    requireValue(reason.contractReleaseRegistryId === input.resolvedContract.release.id, "Reason belongs to another release");
    requireValue(reason.definitionState.status === "VERIFIED" && reason.definitionState.retiredAt === null, "Reason is not active and verified");
  }
  const methodIdToDimension = /* @__PURE__ */ new Map();
  for (const dimension of FIT_DIMENSIONS) {
    const method = input.resolvedContract.methods[dimension];
    validateMethodContract(dimension, method);
    requireValue(!methodIdToDimension.has(method.identity.id), "Duplicate method registry identity");
    methodIdToDimension.set(method.identity.id, dimension);
    assertUnique(method.sourceClassPolicies.map((policy) => policy.sourceClassRegistryId), `${dimension} source-class policy`);
    for (const sourcePolicy of method.sourceClassPolicies) {
      requireValue(sourcePolicy.methodRegistryId === method.identity.id, "Source-class policy method drift");
      const definition = input.resolvedContract.semanticSourceClasses.find((candidate) => candidate.sourceClassRegistryId === sourcePolicy.sourceClassRegistryId);
      requireValue(definition !== void 0 && definition.sourceClassCode === sourcePolicy.sourceClassCode, "Source-class policy definition drift");
    }
    for (const relation of method.mappingRelations) {
      requireValue(relation.methodRegistryId === method.identity.id, "Mapping-policy method drift");
      const definition = input.resolvedContract.mappingRelationDefinitions.find((candidate) => candidate.relationRegistryId === relation.relationRegistryId);
      requireValue(definition !== void 0 && definition.relationCode === relation.relationCode, "Mapping-policy definition drift");
      requireValue(!relation.permitsStrongAlignment || method.permitsStrongAlignment, "Mapping policy exceeds the method strong-alignment permission");
    }
    for (const signal of method.signalTypes) {
      requireValue(!signal.permitsStrongAlignment || method.permitsStrongAlignment, "Signal exceeds the method strong-alignment permission");
    }
    const supplied = input.methods[dimension];
    assertExactKeys(supplied, ["registryId", "methodCode", "methodVersion", "inferenceCategory", "permitsStrongAlignment"], `${dimension} method input`);
    const expected = METHOD_CONTRACT[dimension];
    requireValue(supplied.registryId === method.identity.id && supplied.methodCode === expected.code && supplied.methodVersion === 1 && supplied.inferenceCategory === expected.inferenceCategory && supplied.permitsStrongAlignment === expected.permitsStrongAlignment, `Pinned method drift for ${dimension}`);
  }
  for (const normalization of input.resolvedContract.financialNormalizations) {
    requireValue(normalization.contractReleaseRegistryId === input.resolvedContract.release.id, "Financial normalization belongs to another release");
    requireValue(normalization.definitionState.status === "VERIFIED" && normalization.definitionState.retiredAt === null, "Financial normalization is not active and verified");
    requireText(normalization.normalizationContractCanonicalJson, "Financial normalization contract");
    JSON.parse(normalization.normalizationContractCanonicalJson);
  }
  assertUnique(input.manifest.map((item) => item.ref.manifestItemKey), "manifest item key");
  assertUnique(input.manifest.map((item) => `${item.ref.methodRegistryId}\0${item.kind}\0${item.ref.sourceId}`), "method/source manifest membership");
  assertUnique(input.inputStates.map((state) => `${state.methodRegistryId}\0${state.inputPolicyRegistryId}`), "input state");
  const manifestByKey = new Map(input.manifest.map((item) => [item.ref.manifestItemKey, item]));
  const referenced = /* @__PURE__ */ new Set();
  for (const state of input.inputStates) {
    assertExactKeys(state, ["methodRegistryId", "inputPolicyRegistryId", "methodCode", "policyKey", "requirement", "availability", "manifestItemKeys", "completenessManifestItemKey", "provenanceManifestItemKey"], "Fit input state");
    const dimension = methodIdToDimension.get(state.methodRegistryId);
    requireValue(dimension !== void 0, "Input state references an unknown method");
    const method = input.resolvedContract.methods[dimension];
    const policy = method.inputPolicies.find((candidate) => candidate.identity.id === state.inputPolicyRegistryId);
    requireValue(policy !== void 0, "Input state references an unknown policy");
    requireValue(state.methodCode === METHOD_CONTRACT[dimension].code && state.policyKey === policy.policyKey && state.requirement === policy.requirement, "Input-state registry projection drift");
    assertUnique(state.manifestItemKeys, "input-state manifest key");
    if (state.availability === "INCLUDED") {
      requireValue(state.manifestItemKeys.length > 0, "INCLUDED state requires exact manifest membership");
    } else {
      requireValue(state.manifestItemKeys.length === 0, "Unavailable input cannot supply a value");
      requireValue(state.completenessManifestItemKey !== null || state.provenanceManifestItemKey !== null, "Unavailable input requires completeness or provenance");
    }
    const stateRefs = [
      ...state.manifestItemKeys,
      state.completenessManifestItemKey,
      state.provenanceManifestItemKey
    ].filter((value) => value !== null);
    for (const key of stateRefs) {
      const item = manifestByKey.get(key);
      requireValue(item !== void 0, `Input state references missing manifest item ${key}`);
      requireValue(item.ref.methodRegistryId === state.methodRegistryId, "Input-state evidence crossed methods");
      referenced.add(key);
    }
  }
  requireValue(referenced.size === input.manifest.length, "Manifest contains unreferenced items");
  for (const item of input.manifest) {
    const dimension = methodIdToDimension.get(item.ref.methodRegistryId);
    requireValue(dimension !== void 0, "Manifest references an unknown method");
    validateManifestItem(item, dimension, input);
  }
}

// ../fit-engine/dist/src/evaluate-fit.js
function canonicalizeFitEvaluationInput(input) {
  const canonical = canonicalizeFitInput(input);
  validateFitInput(canonical);
  return deepFreeze(canonical);
}
function evaluateFit(input) {
  const canonical = canonicalizeFitEvaluationInput(input);
  const output = {
    schemaVersion: "fit-v0.1",
    dimensions: {
      ACADEMIC: evaluateAcademic(canonical),
      CAREER: evaluateCareer(canonical),
      FINANCIAL: evaluateFinancial(canonical),
      GEOGRAPHIC_DELIVERY: evaluateGeographicDelivery(canonical),
      PERSONAL_PREFERENCE: evaluatePersonalPreference(canonical),
      INTERNATIONAL_ACCESSIBILITY: evaluateInternationalAccessibility(canonical)
    }
  };
  return deepFreeze(output);
}
function canonicalFitOutputJson(output) {
  return canonicalJson(output);
}

// src/financial-normalization.ts
function parseExactDecimal(value, label) {
  if (!/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(value)) {
    throw new FitAdapterError(`${label} is not an exact decimal`, 422);
  }
  const negative = value.startsWith("-");
  const unsigned = negative ? value.slice(1) : value;
  const [integer = "0", fraction = ""] = unsigned.split(".");
  const coefficient = BigInt(`${integer}${fraction}`) * (negative ? -1n : 1n);
  return { coefficient, scale: fraction.length };
}
function powerOfTen(scale) {
  return 10n ** BigInt(scale);
}
function formatExactDecimal(value) {
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
function multiplyExactDecimals(left, right) {
  const a = parseExactDecimal(left, "left decimal");
  const b = parseExactDecimal(right, "right decimal");
  return formatExactDecimal({ coefficient: a.coefficient * b.coefficient, scale: a.scale + b.scale });
}
function subtractExactDecimals(left, right) {
  const a = parseExactDecimal(left, "left decimal");
  const b = parseExactDecimal(right, "right decimal");
  const scale = Math.max(a.scale, b.scale);
  return formatExactDecimal({
    coefficient: a.coefficient * powerOfTen(scale - a.scale) - b.coefficient * powerOfTen(scale - b.scale),
    scale
  });
}
function equalExactDecimals(left, right) {
  return subtractExactDecimals(left, right) === "0";
}
function calculateReviewedFinancialNormalization(input) {
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

// src/input-resolver.ts
var methodCodeByDimension = {
  ACADEMIC: "ACADEMIC_ALIGNMENT_V01",
  CAREER: "CAREER_ALIGNMENT_V01",
  FINANCIAL: "FINANCIAL_ALIGNMENT_V01",
  GEOGRAPHIC_DELIVERY: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01",
  PERSONAL_PREFERENCE: "PERSONAL_PREFERENCE_ALIGNMENT_V01",
  INTERNATIONAL_ACCESSIBILITY: "INTERNATIONAL_ACCESSIBILITY_V01"
};
function methodFor(contract, dimension) {
  return contract.methods[dimension];
}
function policyFor(method, domain, field) {
  const rows = method.inputPolicies.filter((policy) => policy.disposition === "ALLOWED" && policy.inputDomain === domain && (field === void 0 || policy.fieldName === field));
  return requireOne(rows, `${method.dimension} ${domain}${field === void 0 ? "" : `/${field}`} policy`);
}
function ref(method, policy, manifestItemKey, sourceId, sourceClass, authorityRole) {
  return {
    manifestItemKey,
    sourceId,
    methodRegistryId: method.identity.id,
    inputPolicyRegistryId: policy.identity.id,
    methodCode: method.identity.code,
    policyKey: policy.policyKey,
    sourceClass,
    authorityRole
  };
}
function isoDate(value) {
  return value.includes("T") ? value : `${value}T00:00:00.000Z`;
}
function decimal(value, label) {
  if (typeof value !== "number" && typeof value !== "string" || !/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(String(value))) {
    throw new FitAdapterError(`${label} is not an exact decimal`, 422);
  }
  return String(value);
}
function typedContextValue(claimCode, value) {
  switch (claimCode) {
    case "REGULATORY_WORK_AUTHORIZATION":
      return { claimCode, allowed: Boolean(value.allowed), authorizationType: value.authorizationType === null ? null : String(value.authorizationType) };
    case "LICENSING_RESTRICTION":
      return { claimCode, restricted: Boolean(value.restricted), licenseType: value.licenseType === null ? null : String(value.licenseType) };
    case "CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION":
      return { claimCode, restricted: Boolean(value.restricted), citizenships: Array.isArray(value.citizenships) ? value.citizenships.map(String) : [], clearanceType: value.clearanceType === null ? null : String(value.clearanceType) };
    case "JURISDICTION_PATH_ACCESSIBILITY":
      return { claimCode, accessible: Boolean(value.accessible), restrictionCode: value.restrictionCode === null ? null : String(value.restrictionCode) };
    case "REVIEWED_CAREER_OUTCOME": {
      const scope = value.applicabilityScope;
      if (scope === null || typeof scope !== "object" || Array.isArray(scope)) throw new FitAdapterError("Career context lacks applicabilityScope", 422);
      const applicability = scope;
      return {
        claimCode,
        outcome: String(value.outcome),
        populationDenominator: String(value.populationDenominator),
        cohortPeriod: String(value.cohortPeriod),
        geography: String(value.geography),
        reportingCoverage: String(value.reportingCoverage),
        outcomeDefinition: String(value.outcomeDefinition),
        sampleSource: String(value.sampleSource),
        applicabilityScope: {
          population: String(applicability.population),
          program: String(applicability.program),
          geography: String(applicability.geography),
          period: String(applicability.period)
        }
      };
    }
    default:
      throw new FitAdapterError(`Unsupported context claim code ${claimCode}`, 422);
  }
}
async function typedIntent(database, row, manifestItemKey) {
  const authority = {
    importance: row.importance,
    basis: row.importance_basis,
    importanceEvidenceManifestKey: row.importance === "REQUIRED" ? manifestItemKey : null,
    confirmedByStudent: row.importance_confirmed_by_student
  };
  const query = { select: "*", intent_declaration_id: `eq.${row.intent_declaration_id}` };
  switch (row.semantic_type) {
    case "TAXONOMY_TARGET": {
      const child = requireOne(await database.select("fit_intent_taxonomy_targets", query), "taxonomy intent child");
      return { kind: "TAXONOMY_TARGET", intentId: row.intent_declaration_id, dimension: row.dimension, authority, conceptId: child.concept_id, relation: child.relation };
    }
    case "LOCATION_CONSTRAINT": {
      const child = requireOne(await database.select("fit_intent_location_constraints", query), "location intent child");
      return { kind: "LOCATION_CONSTRAINT", intentId: row.intent_declaration_id, dimension: "GEOGRAPHIC_DELIVERY", authority, relation: child.relation, countryCode: child.country_code, regionCode: child.region_code, locality: child.locality };
    }
    case "DELIVERY_CONSTRAINT": {
      const child = requireOne(await database.select("fit_intent_delivery_constraints", query), "delivery intent child");
      return { kind: "DELIVERY_CONSTRAINT", intentId: row.intent_declaration_id, dimension: "GEOGRAPHIC_DELIVERY", authority, deliveryMode: child.delivery_mode, relation: child.relation };
    }
    case "FINANCIAL_CONSTRAINT": {
      const child = requireOne(await database.select("fit_intent_financial_constraints", query), "financial intent child");
      return { kind: "FINANCIAL_CONSTRAINT", intentId: row.intent_declaration_id, dimension: "FINANCIAL", authority, amount: decimal(child.amount, "financial intent amount"), semantics: child.constraint_semantics, currency: child.currency.trim(), scope: child.financial_scope, period: child.financial_period, basis: child.financial_basis, components: child.components };
    }
    case "DURATION_CONSTRAINT": {
      const child = requireOne(await database.select("fit_intent_duration_constraints", query), "duration intent child");
      return { kind: "DURATION_CONSTRAINT", intentId: row.intent_declaration_id, dimension: "PERSONAL_PREFERENCE", authority, minimumMonths: child.minimum_months === null ? null : decimal(child.minimum_months, "minimum months"), maximumMonths: child.maximum_months === null ? null : decimal(child.maximum_months, "maximum months") };
    }
    case "PROGRAM_FEATURE_CONSTRAINT": {
      const child = requireOne(await database.select("fit_intent_program_feature_constraints", query), "program feature intent child");
      return { kind: "PROGRAM_FEATURE_CONSTRAINT", intentId: row.intent_declaration_id, dimension: row.dimension, authority, feature: child.feature_key, expected: child.expected };
    }
  }
}
function programFact(row) {
  const value = row.observed_value;
  if (row.record_type === "PROGRAM_COURSE" && (row.field_name === "course_name" || row.field_name === "official_description")) {
    return { recordType: "PROGRAM_COURSE", field: row.field_name, value: String(value) };
  }
  if (row.record_type === "PROGRAM_COST" && ["tuition_amount", "mandatory_fees", "estimated_living_cost", "estimated_total_cost", "currency", "billing_basis"].includes(row.field_name)) {
    return { recordType: "PROGRAM_COST", field: row.field_name, value: String(value) };
  }
  if (row.record_type === "PROGRAM_VERSION") {
    if (row.field_name === "delivery_mode") return { recordType: "PROGRAM_VERSION", field: "delivery_mode", value: String(value) };
    if (row.field_name === "duration_months") return { recordType: "PROGRAM_VERSION", field: "duration_months", value: decimal(value, "duration_months") };
    if (row.field_name === "full_time" || row.field_name === "capstone_required") return { recordType: "PROGRAM_VERSION", field: row.field_name, value: Boolean(value) };
    if (row.field_name === "stem_status") return { recordType: "PROGRAM_VERSION", field: "stem_status", value: String(value) };
  }
  throw new FitAdapterError(`Unsupported canonical field ${row.record_type}.${row.field_name}`, 422);
}
function directComparable(selection, amount, basis, cost, intent) {
  if (amount.record_type !== "PROGRAM_COST" || basis.record_type !== "PROGRAM_COST" || amount.record_id !== basis.record_id || basis.field_name !== "billing_basis") {
    throw new FitAdapterError("Direct Financial observations must be an amount/billing-basis pair on one cost row", 422);
  }
  const field = amount.field_name;
  const scope = field === "estimated_total_cost" ? "TOTAL_COST" : "COMPONENT";
  const component = field === "tuition_amount" ? "TUITION" : field === "mandatory_fees" ? "MANDATORY_FEES" : field === "estimated_living_cost" ? "LIVING_COST" : field === "estimated_total_cost" ? "TOTAL_COST" : null;
  const period = basis.observed_value === "PER_YEAR" ? "ACADEMIC_YEAR" : basis.observed_value === "TOTAL_PROGRAM" ? "PROGRAM_DURATION" : null;
  if (component === null || period === null || cost.currency === null || cost.billing_basis !== basis.observed_value) {
    throw new FitAdapterError("Direct Financial source is not v014-comparable", 422);
  }
  const comparable = { amount: decimal(amount.observed_value, "program amount"), currency: cost.currency.trim(), period, scope, basis: "GROSS", components: [component] };
  if (intent.intentId !== selection.financialIntentId || intent.currency !== comparable.currency || intent.period !== comparable.period || intent.scope !== comparable.scope || intent.basis !== comparable.basis || [...intent.components].sort().join("\0") !== [...comparable.components].sort().join("\0")) {
    throw new FitAdapterError("Direct Financial tuple does not exactly match its frozen intent", 422);
  }
  return comparable;
}
async function resolveFitEvaluationInput(database, contract, request, evaluationAsOf) {
  const [profile, intentSet] = await Promise.all([
    database.select("student_profile_versions", { select: "profile_version_id,snapshot_hash,status", profile_version_id: `eq.${request.profileVersionId}` }).then((rows) => requireOne(rows, "profile version")),
    database.select("fit_intent_sets", { select: "intent_set_id,profile_version_id,snapshot_hash,status", intent_set_id: `eq.${request.intentSetId}` }).then((rows) => requireOne(rows, "intent set"))
  ]);
  if (profile.status !== "FROZEN" || profile.snapshot_hash === null || intentSet.status !== "FROZEN" || intentSet.snapshot_hash === null || intentSet.profile_version_id !== profile.profile_version_id) {
    throw new FitAdapterError("Fit input requires matching frozen profile and intent snapshots", 409);
  }
  const intents = await database.select("fit_intent_declarations", { select: "*", intent_set_id: `eq.${request.intentSetId}`, order: "dimension,intent_declaration_id" });
  const manifest = [];
  const intentById = /* @__PURE__ */ new Map();
  for (const row of intents) {
    const method = methodFor(contract, row.dimension);
    const policy = policyFor(method, "FIT_INTENTS");
    const key = `intent:${method.identity.id}:${row.intent_declaration_id}`;
    const intent = await typedIntent(database, row, key);
    intentById.set(row.intent_declaration_id, intent);
    manifest.push({ kind: "FIT_INTENT", ref: ref(method, policy, key, row.intent_declaration_id, "STUDENT_RAW_INTENT", "AUTHORITATIVE"), intent });
    if (row.source_student_goal_id !== null) {
      const source = requireOne(await database.select("student_goals", { select: "student_goal_id,profile_version_id,goal_type,concept_id,goal_text", student_goal_id: `eq.${row.source_student_goal_id}`, profile_version_id: `eq.${request.profileVersionId}` }), "source student goal");
      const sourcePolicy = policyFor(method, "STUDENT_GOALS");
      manifest.push({ kind: "PHASE2_GOAL", ref: ref(method, sourcePolicy, `goal:${method.identity.id}:${source.student_goal_id}`, source.student_goal_id, "STUDENT_RAW_INTENT", "AUTHORITATIVE"), exposedFields: ["GOAL_TYPE", "CONCEPT_ID", "GOAL_TEXT"], goalType: source.goal_type, conceptId: source.concept_id, goalText: source.goal_text });
    }
    if (row.source_student_preference_id !== null) {
      const source = requireOne(await database.select("student_preferences", { select: "student_preference_id,profile_version_id,preference_type,value", student_preference_id: `eq.${row.source_student_preference_id}`, profile_version_id: `eq.${request.profileVersionId}` }), "source student preference");
      const sourcePolicy = policyFor(method, "STUDENT_PREFERENCES");
      manifest.push({ kind: "PHASE2_PREFERENCE", ref: ref(method, sourcePolicy, `preference:${method.identity.id}:${source.student_preference_id}`, source.student_preference_id, "STUDENT_RAW_INTENT", "AUTHORITATIVE"), exposedFields: ["PREFERENCE_TYPE", "VALUE"], preferenceType: source.preference_type, value: JSON.stringify(source.value) });
    }
  }
  if (request.evidence.studentCourseIds.length > 0) {
    const rows = await database.select("student_courses", { select: "student_course_id,profile_version_id,course_code,course_title,course_status,term", profile_version_id: `eq.${request.profileVersionId}`, student_course_id: postgresIn(request.evidence.studentCourseIds) });
    if (rows.length !== request.evidence.studentCourseIds.length) throw new FitAdapterError("A selected student course is outside the profile", 422);
    const method = contract.methods.ACADEMIC;
    const policy = policyFor(method, "STUDENT_COURSES");
    for (const row of rows) manifest.push({ kind: "PHASE2_COURSE", ref: ref(method, policy, `student-course:${row.student_course_id}`, row.student_course_id, "STUDENT_RAW_ACADEMIC_HISTORY", "LIMITING_CONTEXT"), exposedFields: ["COURSE_CODE", "COURSE_TITLE", "COURSE_STATUS", "TERM"], courseCode: row.course_code, courseTitle: row.course_title, courseStatus: row.course_status, term: row.term });
  }
  if (request.evidence.studentMappingIds.length > 0) {
    const rows = await database.select("student_record_concept_mappings", { select: "*", profile_version_id: `eq.${request.profileVersionId}`, student_mapping_id: postgresIn(request.evidence.studentMappingIds) });
    if (rows.length !== request.evidence.studentMappingIds.length) throw new FitAdapterError("A selected student mapping is outside the profile", 422);
    const method = contract.methods.ACADEMIC;
    const policy = policyFor(method, "STUDENT_MAPPINGS");
    for (const row of rows) {
      if (row.mapping_status !== "VERIFIED" || row.retired_at !== null || row.reviewed_at === null || row.student_evidence_id === null) throw new FitAdapterError("Student mapping is not active and VERIFIED", 422);
      manifest.push({ kind: "VERIFIED_MAPPING", ref: ref(method, policy, `student-mapping:${row.student_mapping_id}`, row.student_record_id, "TAXONOMY_MAPPING", "AUTHORITATIVE"), mappingKind: "PHASE2_STUDENT", relationRegistryId: "STUDENT_COURSE_EQUIVALENCY", relation: "STUDENT_COURSE_EQUIVALENCY", conceptId: row.concept_id, statusAtPin: "VERIFIED", reviewedAtAtPin: row.reviewed_at, verificationEvidenceIdAtPin: row.student_evidence_id, retiredAtAtPin: null });
    }
  }
  const [programCourses, programCosts] = await Promise.all([
    database.select("program_courses", { select: "course_id", program_version_id: `eq.${request.programVersionId}`, retired_at: "is.null" }),
    database.select("program_costs", { select: "cost_id,program_version_id,currency,billing_basis", program_version_id: `eq.${request.programVersionId}`, retired_at: "is.null" })
  ]);
  const normalizationRows = request.evidence.approvedFinancialNormalizationIds.length === 0 ? [] : await database.select("fit_financial_normalizations", {
    select: "*",
    financial_normalization_id: postgresIn(request.evidence.approvedFinancialNormalizationIds)
  });
  const normalizationReviews = request.evidence.approvedFinancialNormalizationIds.length === 0 ? [] : await database.select("fit_financial_normalization_reviews_v014", {
    select: "*",
    financial_normalization_id: postgresIn(request.evidence.approvedFinancialNormalizationIds)
  });
  const normalizationPins = request.evidence.approvedFinancialNormalizationIds.length === 0 ? [] : await database.select("fit_financial_source_pins_v014", { select: "*" });
  const normalizationInputs = request.evidence.approvedFinancialNormalizationIds.length === 0 ? [] : await database.select("fit_financial_conversion_inputs_v014", { select: "*" });
  if (normalizationRows.length !== request.evidence.approvedFinancialNormalizationIds.length || normalizationReviews.length !== normalizationRows.length || normalizationPins.length !== normalizationRows.length) {
    throw new FitAdapterError("Approved Financial normalization snapshot is incomplete", 422);
  }
  const allowedProgramRecords = /* @__PURE__ */ new Set([request.programVersionId, ...programCourses.map((row) => row.course_id), ...programCosts.map((row) => row.cost_id)]);
  const directObservationIds = new Set(request.evidence.directFinancialComparisons.flatMap((row) => [row.amountObservationId, row.billingBasisObservationId]));
  const normalizedObservationIds = normalizationRows.flatMap((row) => {
    const pin = normalizationPins.find((candidate) => candidate.evaluation_id === row.evaluation_id && candidate.amount_observation_id === row.field_observation_id);
    return pin === void 0 ? [row.field_observation_id] : [row.field_observation_id, pin.billing_basis_observation_id];
  });
  const requestedObservationIds = [.../* @__PURE__ */ new Set([...request.evidence.canonicalObservationIds, ...directObservationIds, ...normalizedObservationIds])];
  const observations = requestedObservationIds.length === 0 ? [] : await database.select("field_observations", { select: "observation_id,record_type,record_id,field_name,observed_value,knowledge_status", observation_id: postgresIn(requestedObservationIds) });
  const selections = requestedObservationIds.length === 0 ? [] : await database.select("canonical_field_selections", { select: "observation_id,record_type,record_id,field_name", observation_id: postgresIn(requestedObservationIds) });
  if (observations.length !== requestedObservationIds.length || selections.length !== requestedObservationIds.length || observations.some((row) => row.knowledge_status !== "KNOWN" || !allowedProgramRecords.has(row.record_id))) {
    throw new FitAdapterError("Canonical observations must be current KNOWN facts for the selected program", 422);
  }
  const financialWitnessOnly = directObservationIds;
  for (const row of observations.filter((observation) => !financialWitnessOnly.has(observation.observation_id))) {
    for (const dimension of FIT_DIMENSIONS) {
      const method = contract.methods[dimension];
      const policy = method.inputPolicies.find((candidate) => candidate.disposition === "ALLOWED" && candidate.programFields.some((field) => field.recordType === row.record_type && field.fieldName === row.field_name));
      if (policy === void 0) continue;
      const sourceId = row.record_type === "PROGRAM_COURSE" ? row.record_id : row.observation_id;
      const duplicate = manifest.some((item) => item.ref.methodRegistryId === method.identity.id && item.kind === "CANONICAL_PROGRAM_FACT" && item.ref.sourceId === sourceId);
      if (duplicate) continue;
      manifest.push({ kind: "CANONICAL_PROGRAM_FACT", ref: ref(method, policy, `observation:${method.identity.id}:${row.observation_id}`, sourceId, "PROGRAM_CANONICAL_FACT", "AUTHORITATIVE"), recordId: row.record_id, knowledgeStatus: "KNOWN", selectedObservationId: row.observation_id, fact: programFact(row) });
    }
  }
  if (request.evidence.catalogMappingIds.length > 0) {
    const rows = await database.select("catalog_concept_mappings", { select: "*", mapping_id: postgresIn(request.evidence.catalogMappingIds) });
    if (rows.length !== request.evidence.catalogMappingIds.length) throw new FitAdapterError("Unknown catalog mapping selection", 422);
    for (const row of rows) {
      if (!allowedProgramRecords.has(row.record_id) || row.mapping_status !== "VERIFIED" || row.retired_at !== null || row.reviewed_at === null || row.verification_evidence_id === null) throw new FitAdapterError("Catalog mapping is not an active VERIFIED mapping for the program", 422);
      for (const dimension of FIT_DIMENSIONS) {
        const method = contract.methods[dimension];
        if (!method.mappingRelations.some((relation) => relation.relationCode === row.relation)) continue;
        const candidatePolicies = method.inputPolicies.filter((policy2) => policy2.disposition === "ALLOWED" && policy2.inputDomain === "CATALOG_MAPPINGS");
        if (candidatePolicies.length === 0) continue;
        const policy = dimension === "ACADEMIC" ? candidatePolicies.find((candidate) => candidate.fieldName === "ACADEMIC_MAPPING") ?? candidatePolicies[0] : candidatePolicies[0];
        if (policy === void 0) continue;
        if (manifest.some((item) => item.ref.methodRegistryId === method.identity.id && item.kind === "VERIFIED_MAPPING" && item.ref.sourceId === row.record_id)) continue;
        manifest.push({ kind: "VERIFIED_MAPPING", ref: ref(method, policy, `catalog-mapping:${method.identity.id}:${row.mapping_id}`, row.record_id, "TAXONOMY_MAPPING", "AUTHORITATIVE"), mappingKind: "CATALOG", relationRegistryId: row.relation, relation: row.relation, conceptId: row.concept_id, statusAtPin: "VERIFIED", reviewedAtAtPin: row.reviewed_at, verificationEvidenceIdAtPin: row.verification_evidence_id, retiredAtAtPin: null });
      }
    }
  }
  if (request.evidence.taxonomyConceptIds.length > 0) {
    const [concepts, releases] = await Promise.all([
      database.select("taxonomy_concepts", { select: "concept_id,introduced_in_release,retired_in_release", concept_id: postgresIn(request.evidence.taxonomyConceptIds) }),
      database.select("taxonomy_releases", { select: "release_code,release_ordinal" })
    ]);
    if (concepts.length !== request.evidence.taxonomyConceptIds.length) throw new FitAdapterError("Unknown taxonomy concept selection", 422);
    const ordinal = new Map(releases.map((row) => [row.release_code, Number(row.release_ordinal)]));
    const pinned = ordinal.get(request.taxonomyReleaseCode);
    if (pinned === void 0) throw new FitAdapterError("Unknown taxonomy release", 422);
    for (const concept of concepts) {
      if ((ordinal.get(concept.introduced_in_release) ?? Infinity) > pinned || concept.retired_in_release !== null && (ordinal.get(concept.retired_in_release) ?? -Infinity) <= pinned) throw new FitAdapterError("Taxonomy concept is inactive in the pinned release", 422);
      for (const dimension of ["ACADEMIC", "CAREER", "INTERNATIONAL_ACCESSIBILITY"]) {
        const method = contract.methods[dimension];
        const policy = method.inputPolicies.find((candidate) => candidate.disposition === "ALLOWED" && candidate.inputDomain === "TAXONOMY_CONCEPTS");
        if (policy === void 0) continue;
        manifest.push({ kind: "TAXONOMY_CONCEPT", ref: ref(method, policy, `concept:${method.identity.id}:${concept.concept_id}`, concept.concept_id, "TAXONOMY_MAPPING", "LIMITING_CONTEXT"), conceptId: concept.concept_id, activeInPinnedRelease: true });
      }
    }
  }
  if (request.evidence.contextClaimIds.length > 0) {
    const claims = await database.select("fit_context_claims", { select: "*", context_claim_id: postgresIn(request.evidence.contextClaimIds) });
    const definitions = await database.select("fit_context_claim_definitions", { select: "claim_definition_id,claim_code,semantic_source_class_code" });
    const selectionsRows = await database.select("fit_context_claim_selections", { select: "*", context_claim_id: postgresIn(request.evidence.contextClaimIds) });
    const observationIds = selectionsRows.flatMap((row) => row.context_observation_id === null ? [] : [row.context_observation_id]);
    const contextObservations = observationIds.length === 0 ? [] : await database.select("fit_context_claim_observations", { select: "*", context_observation_id: postgresIn(observationIds) });
    if (claims.length !== request.evidence.contextClaimIds.length || selectionsRows.length !== claims.length) throw new FitAdapterError("Context claims require exact current selections", 422);
    for (const claim of claims) {
      if (claim.program_version_id !== null && claim.program_version_id !== request.programVersionId) throw new FitAdapterError("Context claim belongs to another program", 422);
      const definition = requireOne(definitions.filter((row) => row.claim_definition_id === claim.claim_definition_id), "context definition");
      const selection = requireOne(selectionsRows.filter((row) => row.context_claim_id === claim.context_claim_id), "context selection");
      const observation = selection.context_observation_id === null ? null : requireOne(contextObservations.filter((row) => row.context_observation_id === selection.context_observation_id), "context observation");
      const dimension = definition.claim_code === "REVIEWED_CAREER_OUTCOME" ? "CAREER" : "INTERNATIONAL_ACCESSIBILITY";
      const method = contract.methods[dimension];
      const policy = policyFor(method, "FIT_CONTEXT_CLAIMS");
      manifest.push({
        kind: "HISTORICAL_CONTEXT_SELECTION",
        ref: ref(method, policy, `context-claim:${method.identity.id}:${claim.context_claim_id}`, claim.context_claim_id, definition.semantic_source_class_code, observation === null ? "LIMITING_CONTEXT" : "AUTHORITATIVE"),
        claimId: claim.context_claim_id,
        selectionId: selection.context_selection_id,
        observationId: selection.context_observation_id,
        knowledgeStatus: selection.knowledge_status,
        observationWorkflowStatusAtSelection: observation?.workflow_status === "VERIFIED" ? "VERIFIED" : null,
        observationReviewedAtAtSelection: observation?.reviewed_at ?? null,
        authority: observation?.authority ?? null,
        validFrom: isoDate(claim.valid_from),
        validTo: claim.valid_to === null ? null : isoDate(claim.valid_to),
        programVersionId: claim.program_version_id,
        geographyCode: claim.geography_code,
        jurisdictionCode: claim.jurisdiction_code,
        pathCode: claim.path_code,
        value: observation === null ? null : typedContextValue(definition.claim_code, observation.observed_value)
      });
    }
  }
  if (request.evidence.contextMappingIds.length > 0) {
    const rows = await database.select("fit_context_concept_mappings", { select: "*", context_mapping_id: postgresIn(request.evidence.contextMappingIds) });
    const claimIds = rows.map((row) => row.context_claim_id);
    const claims = claimIds.length === 0 ? [] : await database.select("fit_context_claims", { select: "*", context_claim_id: postgresIn(claimIds) });
    const definitions = await database.select("fit_context_claim_definitions", { select: "claim_definition_id,claim_code,semantic_source_class_code" });
    if (rows.length !== request.evidence.contextMappingIds.length) throw new FitAdapterError("Unknown context mapping selection", 422);
    for (const row of rows) {
      if (row.mapping_status !== "VERIFIED" || row.retired_at !== null || row.reviewed_at === null || row.verification_evidence_id === null) throw new FitAdapterError("Context mapping is not active and VERIFIED", 422);
      const claim = requireOne(claims.filter((candidate) => candidate.context_claim_id === row.context_claim_id), "context mapping claim");
      if (claim.program_version_id !== null && claim.program_version_id !== request.programVersionId) throw new FitAdapterError("Context mapping belongs to another program", 422);
      const definition = requireOne(definitions.filter((candidate) => candidate.claim_definition_id === claim.claim_definition_id), "context mapping definition");
      for (const dimension of FIT_DIMENSIONS) {
        const method = contract.methods[dimension];
        if (!method.mappingRelations.some((relation) => relation.relationCode === row.relation_code)) continue;
        const policy = method.inputPolicies.find((candidate) => candidate.disposition === "ALLOWED" && candidate.inputDomain === "FIT_CONTEXT_CLAIMS");
        if (policy === void 0) continue;
        manifest.push({ kind: "VERIFIED_MAPPING", ref: ref(method, policy, `context-mapping:${method.identity.id}:${row.context_mapping_id}`, row.context_claim_id, definition.semantic_source_class_code, "AUTHORITATIVE"), mappingKind: "FIT_CONTEXT", relationRegistryId: row.relation_code, relation: row.relation_code, conceptId: row.concept_id, statusAtPin: "VERIFIED", reviewedAtAtPin: row.reviewed_at, verificationEvidenceIdAtPin: row.verification_evidence_id, retiredAtAtPin: null });
      }
    }
  }
  if (request.evidence.accessContextId !== null) {
    const access = await database.rpc("get_fit_student_access_context_v016", { p_profile_version_id: request.profileVersionId, p_access_context_id: request.evidence.accessContextId });
    const method = contract.methods.INTERNATIONAL_ACCESSIBILITY;
    const policy = policyFor(method, "FIT_ACCESS_CONTEXT");
    manifest.push({ kind: "STUDENT_ACCESS_CONTEXT", ref: ref(method, policy, `access:${access.access_context_id}`, access.access_context_id, "STUDENT_RAW_ACCESS_CONTEXT", "AUTHORITATIVE"), citizenshipCountryCode: access.citizenship_country_code, residenceCountryCode: access.residence_country_code, jurisdictionCode: access.jurisdiction_code, currentStatusCode: access.current_status_code, authorizationPathCode: access.authorization_path_code, targetPathCode: access.target_path_code });
  }
  for (const selection of request.evidence.directFinancialComparisons) {
    const intent = intentById.get(selection.financialIntentId);
    if (intent === void 0 || intent.kind !== "FINANCIAL_CONSTRAINT" || intent.semantics === "AVAILABLE_FUNDING") throw new FitAdapterError("Direct Financial selection requires a frozen cost constraint", 422);
    const amount = requireOne(observations.filter((row) => row.observation_id === selection.amountObservationId), "direct amount observation");
    const basis = requireOne(observations.filter((row) => row.observation_id === selection.billingBasisObservationId), "direct billing-basis observation");
    const cost = requireOne(programCosts.filter((row) => row.cost_id === amount.record_id), "direct program cost");
    const method = contract.methods.FINANCIAL;
    const policy = policyFor(method, "PROGRAM_COSTS");
    const semanticSource = `financial-source:${selection.amountObservationId}:${selection.billingBasisObservationId}`;
    manifest.push({ kind: "DIRECT_FINANCIAL_COMPARABLE", ref: ref(method, policy, `direct-financial:${selection.financialIntentId}`, `${amount.record_id}:${selection.financialIntentId}`, "PROGRAM_CANONICAL_FACT", "AUTHORITATIVE"), sourcePinId: semanticSource, financialContractVersion: "FINANCIAL_BILLING_BASIS_V014", financialConstraintIntentId: selection.financialIntentId, comparable: directComparable(selection, amount, basis, cost, intent) });
  }
  for (const row of normalizationRows) {
    if (row.profile_version_id !== request.profileVersionId || row.intent_set_id !== request.intentSetId) {
      throw new FitAdapterError("Financial normalization belongs to another frozen request", 422);
    }
    const review = requireOne(normalizationReviews.filter((candidate) => candidate.financial_normalization_id === row.financial_normalization_id), "normalization review");
    if (review.status !== "VERIFIED" || review.verification_evidence_id === null || review.retired_at !== null) {
      throw new FitAdapterError("Financial normalization is not active and VERIFIED", 422);
    }
    const intent = intentById.get(row.financial_constraint_id);
    if (intent === void 0 || intent.kind !== "FINANCIAL_CONSTRAINT" || intent.semantics === "AVAILABLE_FUNDING") {
      throw new FitAdapterError("Financial normalization target is not a frozen cost constraint", 422);
    }
    const registered = requireOne(contract.financialNormalizations.filter((candidate) => candidate.identity.id === row.normalization_method_id), "registered Financial normalization method");
    const inputs = normalizationInputs.filter((candidate) => candidate.financial_normalization_id === row.financial_normalization_id);
    const sourceInput = requireOne(inputs.filter((candidate) => candidate.input_role === "SOURCE_AMOUNT"), "normalization source input");
    const yearsInput = requireOne(inputs.filter((candidate) => candidate.input_role === "ACADEMIC_YEARS"), "normalization academic-years input");
    const roundingInput = requireOne(inputs.filter((candidate) => candidate.input_role === "ROUNDING"), "normalization rounding input");
    const fundingInputs = inputs.filter((candidate) => candidate.input_role === "AVAILABLE_FUNDING");
    const methodContract = JSON.parse(registered.normalizationContractCanonicalJson);
    const computedAmount = calculateReviewedFinancialNormalization({
      formulaCode: String(methodContract.formulaCode ?? ""),
      sourceAmount: decimal(sourceInput.numeric_value, "normalization source input"),
      academicYears: decimal(yearsInput.numeric_value, "normalization academic years"),
      fundingAmount: fundingInputs.length === 0 ? null : decimal(requireOne(fundingInputs, "normalization funding input").numeric_value, "normalization funding"),
      rounding: roundingInput.text_value ?? "",
      sourceCurrency: row.original_currency,
      targetCurrency: row.target_currency
    });
    if (!equalExactDecimals(
      decimal(sourceInput.numeric_value, "normalization source input"),
      decimal(row.original_amount, "normalization original amount")
    )) {
      throw new FitAdapterError("Reviewed Financial normalization source amount drift", 422);
    }
    const method = contract.methods.FINANCIAL;
    const policy = policyFor(method, "FINANCIAL_NORMALIZATIONS");
    manifest.push({
      kind: "APPROVED_FINANCIAL_NORMALIZATION",
      ref: ref(method, policy, `normalized-financial:${row.financial_constraint_id}`, row.financial_normalization_id, "FIT_CONTEXT_FINANCIAL", "AUTHORITATIVE"),
      normalizationId: row.normalization_method_id,
      fieldObservationId: row.field_observation_id,
      financialConstraintIntentId: row.financial_constraint_id,
      intentSetId: row.intent_set_id,
      financialContractVersion: "FINANCIAL_BILLING_BASIS_V014",
      methodCode: registered.identity.code,
      methodVersion: Number(registered.identity.version),
      verificationEvidenceId: review.verification_evidence_id,
      source: {
        amount: decimal(row.original_amount, "normalization original amount"),
        currency: row.original_currency.trim(),
        period: row.original_period,
        scope: row.original_scope,
        basis: row.original_basis,
        components: row.original_components
      },
      target: {
        amount: computedAmount,
        currency: row.target_currency.trim(),
        period: row.target_period,
        scope: row.target_scope,
        basis: row.target_basis,
        components: row.target_components
      },
      conversionEvidenceId: row.conversion_evidence_id
    });
  }
  const inputStates = FIT_DIMENSIONS.flatMap((dimension) => {
    const method = contract.methods[dimension];
    const methodManifest = manifest.filter((item) => item.ref.methodRegistryId === method.identity.id);
    if (methodManifest.length === 0) throw new FitAdapterError(`${dimension} has no exact intent or provenance manifest`, 422);
    return method.inputPolicies.filter((policy) => policy.disposition === "ALLOWED").map((policy) => {
      const keys = methodManifest.filter((item) => item.ref.inputPolicyRegistryId === policy.identity.id).map((item) => item.ref.manifestItemKey);
      const included = keys.length > 0;
      return {
        methodRegistryId: method.identity.id,
        inputPolicyRegistryId: policy.identity.id,
        methodCode: methodCodeByDimension[dimension],
        policyKey: policy.policyKey,
        requirement: policy.requirement,
        availability: included ? "INCLUDED" : "NOT_SUPPLIED",
        manifestItemKeys: keys,
        completenessManifestItemKey: null,
        provenanceManifestItemKey: included ? null : methodManifest[0].ref.manifestItemKey
      };
    });
  });
  return {
    schemaVersion: "fit-v0.1",
    contractRelease: { registryId: contract.release.id, releaseCode: "fit-v0.1", specificationVersion: "v0.1", digest: contract.release.specificationDigest },
    resolvedContract: contract,
    evaluator: { registryId: contract.evaluatorBuild.id, name: contract.evaluatorBuild.evaluatorName, version: contract.evaluatorBuild.evaluatorVersion, buildHash: contract.evaluatorBuild.buildHash },
    evaluationAsOf,
    profile: { versionId: profile.profile_version_id, snapshotHash: profile.snapshot_hash },
    intentSet: { id: intentSet.intent_set_id, snapshotHash: intentSet.snapshot_hash },
    programVersionId: request.programVersionId,
    taxonomyReleaseCode: request.taxonomyReleaseCode,
    methods: {
      ACADEMIC: { registryId: contract.methods.ACADEMIC.identity.id, methodCode: "ACADEMIC_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: true },
      CAREER: { registryId: contract.methods.CAREER.identity.id, methodCode: "CAREER_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
      FINANCIAL: { registryId: contract.methods.FINANCIAL.identity.id, methodCode: "FINANCIAL_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "DETERMINISTIC", permitsStrongAlignment: false },
      GEOGRAPHIC_DELIVERY: { registryId: contract.methods.GEOGRAPHIC_DELIVERY.identity.id, methodCode: "GEOGRAPHIC_DELIVERY_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
      PERSONAL_PREFERENCE: { registryId: contract.methods.PERSONAL_PREFERENCE.identity.id, methodCode: "PERSONAL_PREFERENCE_ALIGNMENT_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false },
      INTERNATIONAL_ACCESSIBILITY: { registryId: contract.methods.INTERNATIONAL_ACCESSIBILITY.identity.id, methodCode: "INTERNATIONAL_ACCESSIBILITY_V01", methodVersion: 1, inferenceCategory: "HYBRID", permitsStrongAlignment: false }
    },
    manifest,
    inputStates
  };
}

// src/persistence.ts
function lastKeyPart(key) {
  const value = key.split(":").at(-1);
  if (value === void 0 || value.length === 0) throw new FitAdapterError(`Invalid adapter manifest key ${key}`, 500);
  return value;
}
function itemType(item) {
  switch (item.kind) {
    case "FIT_INTENT":
      return "FIT_INTENT_DECLARATION";
    case "STUDENT_ACCESS_CONTEXT":
      return "FIT_STUDENT_ACCESS_CONTEXT";
    case "PHASE2_GOAL":
      return "PHASE2_STUDENT_GOAL";
    case "PHASE2_PREFERENCE":
      return "PHASE2_STUDENT_PREFERENCE";
    case "PHASE2_COURSE":
      return "PHASE2_STUDENT_COURSE";
    case "PHASE2_COMPLETENESS":
      return "PHASE2_STUDENT_COMPLETENESS";
    case "VERIFIED_MAPPING":
      return item.mappingKind === "PHASE2_STUDENT" ? "PHASE2_STUDENT_MAPPING" : item.mappingKind === "CATALOG" ? "CATALOG_MAPPING" : "FIT_CONTEXT_MAPPING";
    case "TAXONOMY_CONCEPT":
      return "TAXONOMY_CONCEPT";
    case "CANONICAL_PROGRAM_FACT":
      return "CATALOG_FIELD_OBSERVATION";
    case "HISTORICAL_CONTEXT_SELECTION":
      return "FIT_CONTEXT_CLAIM_SELECTION";
  }
}
async function insertManifestParent(database, evaluationId, profileVersionId, item, forcedItemType) {
  const row = requireOne(await database.insert("fit_manifest_items", [{
    evaluation_id: evaluationId,
    profile_version_id: profileVersionId,
    method_id: item.ref.methodRegistryId,
    input_policy_id: item.ref.inputPolicyRegistryId,
    item_type: forcedItemType ?? (item.kind === "DIRECT_FINANCIAL_COMPARABLE" ? "CATALOG_FIELD_OBSERVATION" : item.kind === "APPROVED_FINANCIAL_NORMALIZATION" ? "FIT_FINANCIAL_NORMALIZATION" : itemType(item)),
    authority_role: item.ref.authorityRole,
    source_class_code: item.ref.sourceClass
  }]), "inserted manifest item");
  return row.manifest_item_id;
}
async function insertManifestItem(database, evaluationId, profileVersionId, intentSetId, item) {
  const manifestItemId = await insertManifestParent(database, evaluationId, profileVersionId, item);
  const common = { manifest_item_id: manifestItemId, evaluation_id: evaluationId, profile_version_id: profileVersionId };
  switch (item.kind) {
    case "FIT_INTENT":
      await database.insert("fit_manifest_intent_declarations", [{ ...common, method_id: item.ref.methodRegistryId, intent_declaration_id: item.intent.intentId, intent_set_id: intentSetId }]);
      break;
    case "STUDENT_ACCESS_CONTEXT":
      await database.insert("fit_manifest_student_access_contexts", [{ ...common, access_context_id: item.ref.sourceId }]);
      break;
    case "PHASE2_GOAL":
      await database.insert("fit_manifest_phase2_goals", [{ ...common, student_goal_id: item.ref.sourceId }]);
      await database.insert("fit_manifest_student_field_uses", item.exposedFields.map((field_name) => ({ manifest_item_id: manifestItemId, evaluation_id: evaluationId, field_name })));
      break;
    case "PHASE2_PREFERENCE":
      await database.insert("fit_manifest_phase2_preferences", [{ ...common, student_preference_id: item.ref.sourceId }]);
      await database.insert("fit_manifest_student_field_uses", item.exposedFields.map((field_name) => ({ manifest_item_id: manifestItemId, evaluation_id: evaluationId, field_name })));
      break;
    case "PHASE2_COURSE":
      await database.insert("fit_manifest_phase2_courses", [{ ...common, student_course_id: item.ref.sourceId }]);
      await database.insert("fit_manifest_student_field_uses", item.exposedFields.map((field_name) => ({ manifest_item_id: manifestItemId, evaluation_id: evaluationId, field_name })));
      break;
    case "PHASE2_COMPLETENESS":
      await database.insert("fit_manifest_phase2_completeness", [{ ...common, completeness_id: item.ref.sourceId }]);
      await database.insert("fit_manifest_student_field_uses", ["EDUCATION_CONTEXT_ID", "DOMAIN", "COMPLETENESS"].map((field_name) => ({ manifest_item_id: manifestItemId, evaluation_id: evaluationId, field_name })));
      break;
    case "VERIFIED_MAPPING":
      if (item.mappingKind === "PHASE2_STUDENT") await database.insert("fit_manifest_phase2_mappings", [{ ...common, student_mapping_id: lastKeyPart(item.ref.manifestItemKey) }]);
      else if (item.mappingKind === "CATALOG") await database.insert("fit_manifest_catalog_mappings", [{ ...common, catalog_mapping_id: lastKeyPart(item.ref.manifestItemKey) }]);
      else await database.insert("fit_manifest_context_mappings", [{ ...common, context_mapping_id: lastKeyPart(item.ref.manifestItemKey), mapping_status_at_pin: item.statusAtPin, mapping_reviewed_at_at_pin: item.reviewedAtAtPin, mapping_verification_evidence_id_at_pin: item.verificationEvidenceIdAtPin, mapping_retired_at_at_pin: item.retiredAtAtPin }]);
      break;
    case "TAXONOMY_CONCEPT":
      await database.insert("fit_manifest_taxonomy_concepts", [{ ...common, concept_id: item.conceptId }]);
      break;
    case "CANONICAL_PROGRAM_FACT":
      await database.insert("fit_manifest_catalog_observations", [{ ...common, field_observation_id: item.selectedObservationId }]);
      break;
    case "HISTORICAL_CONTEXT_SELECTION":
      await database.insert("fit_manifest_context_claim_selections", [{ ...common, context_claim_id: item.claimId, context_selection_id: item.selectionId, context_observation_id: item.observationId, knowledge_status: item.knowledgeStatus }]);
      break;
  }
  return manifestItemId;
}
async function insertDirectFinancial(database, evaluationId, profileVersionId, item) {
  const parts = item.sourcePinId.split(":");
  const amountObservationId = parts.at(-2);
  const basisObservationId = parts.at(-1);
  if (amountObservationId === void 0 || basisObservationId === void 0) throw new FitAdapterError("Invalid direct Financial semantic source", 500);
  const amountManifestId = await insertManifestParent(database, evaluationId, profileVersionId, item, "CATALOG_FIELD_OBSERVATION");
  const basisManifestId = await insertManifestParent(database, evaluationId, profileVersionId, item, "CATALOG_FIELD_OBSERVATION");
  await database.insert("fit_manifest_catalog_observations", [
    { manifest_item_id: amountManifestId, evaluation_id: evaluationId, profile_version_id: profileVersionId, field_observation_id: amountObservationId },
    { manifest_item_id: basisManifestId, evaluation_id: evaluationId, profile_version_id: profileVersionId, field_observation_id: basisObservationId }
  ]);
  await database.rpc("pin_fit_financial_source_v014", {
    p_evaluation_id: evaluationId,
    p_amount_manifest_item_id: amountManifestId,
    p_basis_manifest_item_id: basisManifestId
  });
  return [amountManifestId, basisManifestId];
}
async function insertApprovedFinancialNormalization(database, evaluationId, profileVersionId, item, assembly) {
  if (assembly.normalizationId !== item.ref.sourceId) {
    throw new FitAdapterError("Reviewed Financial normalization assembly identity drift", 500);
  }
  const manifestItemId = await insertManifestParent(database, evaluationId, profileVersionId, item);
  await database.insert("fit_manifest_financial_normalizations", [{
    manifest_item_id: manifestItemId,
    evaluation_id: evaluationId,
    profile_version_id: profileVersionId,
    financial_normalization_id: assembly.normalizationId
  }]);
  return [manifestItemId, assembly.amountManifestItemId, assembly.basisManifestItemId];
}
function signalMatch(reasonRefs, signal) {
  const refs = /* @__PURE__ */ new Set([...signal.evidenceManifestRefs, ...signal.intentManifestRef === null ? [] : [signal.intentManifestRef]]);
  return reasonRefs.every((value) => refs.has(value));
}
async function persistFitEvaluation(database, evaluationId, input, output, approvedFinancialAssemblies = []) {
  await database.rpc("authorize_fit_evaluation_assembly", {
    p_evaluation_id: evaluationId,
    p_evaluator_build_hash: input.evaluator.buildHash
  });
  const manifestIds = /* @__PURE__ */ new Map();
  const intentIds = /* @__PURE__ */ new Map();
  const directPins = /* @__PURE__ */ new Map();
  const reviewedWitnessManifestIds = /* @__PURE__ */ new Map();
  for (const assembly of approvedFinancialAssemblies) {
    for (const [observationId, manifestItemId] of [
      [assembly.amountObservationId, assembly.amountManifestItemId],
      [assembly.basisObservationId, assembly.basisManifestItemId]
    ]) {
      const existing = reviewedWitnessManifestIds.get(observationId);
      if (existing !== void 0 && existing !== manifestItemId) {
        throw new FitAdapterError("Reviewed Financial witness has conflicting manifest identity", 500);
      }
      reviewedWitnessManifestIds.set(observationId, manifestItemId);
    }
  }
  for (const item of input.manifest) {
    let ids;
    if (item.kind === "APPROVED_FINANCIAL_NORMALIZATION") {
      const assembly = requireOne(approvedFinancialAssemblies.filter((candidate) => candidate.normalizationId === item.ref.sourceId), "reviewed Financial normalization assembly");
      ids = await insertApprovedFinancialNormalization(database, evaluationId, input.profile.versionId, item, assembly);
    } else if (item.kind === "DIRECT_FINANCIAL_COMPARABLE") {
      const cached = directPins.get(item.sourcePinId);
      ids = cached ?? await insertDirectFinancial(database, evaluationId, input.profile.versionId, item);
      directPins.set(item.sourcePinId, ids);
    } else if (item.kind === "CANONICAL_PROGRAM_FACT" && reviewedWitnessManifestIds.has(item.selectedObservationId)) {
      ids = [reviewedWitnessManifestIds.get(item.selectedObservationId)];
    } else {
      ids = [await insertManifestItem(database, evaluationId, input.profile.versionId, input.intentSet.id, item)];
    }
    manifestIds.set(item.ref.manifestItemKey, ids);
    if (item.kind === "FIT_INTENT") intentIds.set(item.ref.manifestItemKey, item.intent.intentId);
  }
  for (const assembly of approvedFinancialAssemblies) {
    if (assembly.fundingIntentId === null) continue;
    const normalizationItem = requireOne(input.manifest.filter(
      (item) => item.kind === "APPROVED_FINANCIAL_NORMALIZATION" && item.ref.sourceId === assembly.normalizationId
    ), "reviewed net Financial normalization manifest");
    const fundingItem = requireOne(input.manifest.filter(
      (item) => item.kind === "FIT_INTENT" && item.intent.kind === "FINANCIAL_CONSTRAINT" && item.intent.intentId === assembly.fundingIntentId && item.intent.semantics === "AVAILABLE_FUNDING"
    ), "reviewed net Financial funding intent");
    const normalizationIds = manifestIds.get(normalizationItem.ref.manifestItemKey);
    const fundingIds = manifestIds.get(fundingItem.ref.manifestItemKey);
    if (normalizationIds === void 0 || fundingIds === void 0) {
      throw new FitAdapterError("Reviewed net Financial composite provenance is incomplete", 500);
    }
    manifestIds.set(normalizationItem.ref.manifestItemKey, [.../* @__PURE__ */ new Set([...normalizationIds, ...fundingIds])]);
  }
  const stateIds = /* @__PURE__ */ new Map();
  const stateRows = /* @__PURE__ */ new Map();
  for (const state of input.inputStates) {
    const completeness = state.availability !== "INCOMPLETE" || state.completenessManifestItemKey === null ? null : manifestIds.get(state.completenessManifestItemKey)?.[0] ?? null;
    const provenance = !["STALE_SOURCE", "SOURCE_CONFLICT"].includes(state.availability) || state.provenanceManifestItemKey === null ? null : manifestIds.get(state.provenanceManifestItemKey)?.[0] ?? null;
    const inserted = requireOne(await database.insert("fit_input_domain_states", [{
      evaluation_id: evaluationId,
      profile_version_id: input.profile.versionId,
      method_id: state.methodRegistryId,
      input_policy_id: state.inputPolicyRegistryId,
      availability: state.availability,
      completeness_manifest_item_id: completeness,
      provenance_manifest_item_id: provenance,
      explanation: state.availability === "INCLUDED" ? null : "The exact selected evidence set did not supply this policy input."
    }]), "inserted Fit input state");
    stateIds.set(state.inputPolicyRegistryId, inserted.input_state_id);
    stateRows.set(state.inputPolicyRegistryId, state);
  }
  for (const dimension of FIT_DIMENSIONS) {
    const decision = output.dimensions[dimension];
    const result = requireOne(await database.insert("fit_dimension_results", [{
      evaluation_id: evaluationId,
      dimension,
      assessment: decision.assessment,
      confidence: decision.confidence,
      evidence_coverage: decision.evidenceCoverage,
      method_id: decision.methodRegistryId,
      inference_category: decision.inferenceCategory,
      presentation_explanation: null
    }]), "inserted Fit dimension result");
    const insertedSignals = [];
    for (const signal of decision.signals) {
      const intentDeclarationId = signal.intentManifestRef === null ? null : intentIds.get(signal.intentManifestRef) ?? null;
      const inserted = requireOne(await database.insert("fit_signals", [{
        evaluation_id: evaluationId,
        dimension_result_id: result.dimension_result_id,
        dimension,
        method_id: signal.methodRegistryId,
        signal_type_id: signal.signalTypeRegistryId,
        direction: signal.direction,
        material: signal.material,
        inference_category: signal.inferenceCategory,
        model_version: signal.model?.version ?? null,
        model_build_hash: signal.model?.buildHash ?? null,
        evidence_metadata: {},
        intent_declaration_id: intentDeclarationId,
        required_constraint_contradiction: signal.requiredConstraintContradiction,
        international_high_impact: signal.internationalHighImpact
      }]), "inserted Fit signal");
      insertedSignals.push({ signal, signalId: inserted.signal_id });
      const evidenceKeys = [.../* @__PURE__ */ new Set([...signal.evidenceManifestRefs, ...signal.intentManifestRef === null ? [] : [signal.intentManifestRef]])];
      const evidenceRows = evidenceKeys.flatMap((key) => {
        const ids = manifestIds.get(key);
        if (ids === void 0) throw new FitAdapterError(`Signal references unknown manifest key ${key}`, 500);
        return ids.map((manifest_item_id) => ({ signal_id: inserted.signal_id, evaluation_id: evaluationId, manifest_item_id }));
      });
      await database.insert("fit_signal_evidence", evidenceRows);
    }
    for (const reason of decision.reasons) {
      const signal = reason.signalTypeRegistryId === null ? void 0 : insertedSignals.find((candidate) => candidate.signal.signalTypeRegistryId === reason.signalTypeRegistryId && signalMatch(reason.exactManifestRefs, candidate.signal));
      let inputStateId = null;
      if (signal === void 0) {
        if (reason.inputPolicyRegistryId !== null) inputStateId = stateIds.get(reason.inputPolicyRegistryId) ?? null;
        if (inputStateId === null) {
          const unavailable = [...stateRows.entries()].find(([, state]) => state.methodRegistryId === decision.methodRegistryId && state.availability !== "INCLUDED");
          inputStateId = unavailable === void 0 ? null : stateIds.get(unavailable[0]) ?? null;
        }
      }
      if (signal === void 0 && inputStateId === null) throw new FitAdapterError(`Reason ${reason.reasonCode} has no exact SQL provenance`, 422);
      await database.insert("fit_dimension_reasons", [{
        dimension_result_id: result.dimension_result_id,
        evaluation_id: evaluationId,
        reason_definition_id: reason.reasonDefinitionRegistryId,
        direction: reason.direction,
        signal_id: signal?.signalId ?? null,
        input_state_id: signal === void 0 ? inputStateId : null,
        presentation_explanation: null
      }]);
    }
  }
  const candidateInputFingerprint = await database.rpc("seal_fit_evaluation_inputs", { p_evaluation_id: evaluationId });
  await database.rpc("finalize_fit_evaluation", { p_evaluation_id: evaluationId });
  const completed = requireOne(await database.select("fit_evaluations", {
    select: "evaluation_state,candidate_input_fingerprint,result_fingerprint",
    evaluation_id: `eq.${evaluationId}`
  }), "completed Fit evaluation");
  if (completed.evaluation_state !== "COMPLETED" || completed.candidate_input_fingerprint !== candidateInputFingerprint || completed.result_fingerprint === null || !/^[0-9a-f]{64}$/.test(completed.result_fingerprint)) {
    throw new FitAdapterError("Finalized Fit fingerprints are inconsistent", 500);
  }
  return { candidateInputFingerprint, resultFingerprint: completed.result_fingerprint };
}

// src/registry-resolver.ts
function requireReviewed(row, label) {
  if (row.status !== "VERIFIED" || row.reviewed_by === null || row.reviewed_at === null || row.retired_at !== null) {
    throw new FitAdapterError(`${label} is not active and VERIFIED`, 409);
  }
  return {
    status: "VERIFIED",
    reviewedBy: row.reviewed_by,
    reviewedAt: row.reviewed_at,
    retiredAt: null,
    retirementReason: null
  };
}
function requireVerifiedArtifact(row, label) {
  if (row.verification_evidence_id === null) {
    throw new FitAdapterError(`${label} has no verification evidence`, 409);
  }
  return {
    ...requireReviewed(row, label),
    verificationEvidenceId: row.verification_evidence_id
  };
}
async function resolveFitContract(database, options) {
  const release = requireOne(await database.select("fit_contract_releases", {
    select: "*",
    release_code: "eq.fit-v0.1",
    status: "eq.VERIFIED",
    retired_at: "is.null"
  }), "fit-v0.1 release");
  const build = requireOne(await database.select("fit_evaluator_builds", {
    select: "*",
    contract_release_id: `eq.${release.contract_release_id}`,
    evaluator_name: `eq.${options.evaluatorName}`,
    evaluator_version: `eq.${options.evaluatorVersion}`,
    status: "eq.VERIFIED",
    retired_at: "is.null"
  }), "production evaluator build");
  const [
    methodRows,
    sourceClasses,
    sourcePolicies,
    inputPolicies,
    programFields,
    relationDefinitions,
    relationPolicies,
    signalTypes,
    reasons,
    normalizations
  ] = await Promise.all([
    database.select("fit_dimension_methods", { select: "*", contract_release_id: `eq.${release.contract_release_id}` }),
    database.select("fit_semantic_source_classes", { select: "*" }),
    database.select("fit_method_source_class_policies", { select: "*" }),
    database.select("fit_method_input_policies", { select: "*" }),
    database.select("fit_method_program_field_policies", { select: "*" }),
    database.select("fit_mapping_relation_definitions", { select: "*" }),
    database.select("fit_method_mapping_relation_policies", { select: "*" }),
    database.select("fit_signal_types", { select: "*" }),
    database.select("fit_reason_definitions", { select: "*", contract_release_id: `eq.${release.contract_release_id}` }),
    database.select("fit_financial_normalization_methods", { select: "*", contract_release_id: `eq.${release.contract_release_id}` })
  ]);
  const verifiedMethods = methodRows.filter((row) => row.status === "VERIFIED" && row.retired_at === null);
  if (verifiedMethods.length !== FIT_DIMENSIONS.length) {
    throw new FitAdapterError("fit-v0.1 requires exactly six active VERIFIED methods", 409, {
      count: verifiedMethods.length
    });
  }
  const methods = Object.fromEntries(FIT_DIMENSIONS.map((dimension) => {
    const row = requireOne(verifiedMethods.filter((method2) => method2.dimension === dimension), `${dimension} method`);
    const method = {
      identity: { id: row.method_id, code: row.method_code, version: String(row.method_version) },
      dimension,
      inferenceCategory: row.inference_category,
      permitsStrongAlignment: row.permits_strong_alignment,
      materialityContractCanonicalJson: canonicalJson(row.materiality_contract),
      definitionState: requireVerifiedArtifact(row, `${dimension} method`),
      sourceClassPolicies: sourcePolicies.filter((policy) => policy.method_id === row.method_id).map((policy) => ({
        methodRegistryId: row.method_id,
        sourceClassRegistryId: policy.source_class_code,
        sourceClassCode: policy.source_class_code,
        disposition: policy.disposition
      })),
      inputPolicies: inputPolicies.filter((policy) => policy.method_id === row.method_id).map((policy) => {
        const policyKey = `${row.method_code}/${policy.input_domain}/${policy.field_name}`;
        return {
          identity: { id: policy.input_policy_id, code: policyKey, version: "1" },
          methodRegistryId: row.method_id,
          policyKey,
          inputDomain: policy.input_domain,
          fieldName: policy.field_name,
          disposition: policy.disposition,
          requirement: policy.requirement,
          acceptableAuthority: policy.acceptable_authority,
          acceptableClaimStatus: policy.acceptable_claim_status,
          programFields: programFields.filter((field) => field.method_id === row.method_id && field.input_policy_id === policy.input_policy_id).map((field) => ({
            methodRegistryId: row.method_id,
            inputPolicyRegistryId: policy.input_policy_id,
            recordType: field.record_type,
            fieldName: field.field_name
          })),
          permitsDeterministicUse: policy.permits_deterministic_use,
          permitsModelUse: policy.permits_model_use
        };
      }),
      mappingRelations: relationPolicies.filter((policy) => policy.method_id === row.method_id).map((policy) => ({
        methodRegistryId: row.method_id,
        relationRegistryId: policy.relation_code,
        relationCode: policy.relation_code,
        allowedAssessments: policy.allowed_assessments,
        permitsStrongAlignment: policy.permits_strong_alignment
      })),
      signalTypes: signalTypes.filter((signal) => signal.method_id === row.method_id).map((signal) => ({
        identity: { id: signal.signal_type_id, code: signal.signal_code, version: "1" },
        methodRegistryId: row.method_id,
        direction: signal.direction,
        material: signal.material,
        allowedInferenceCategories: signal.allowed_inference_categories,
        permitsStrongAlignment: signal.permits_strong_alignment,
        description: signal.description
      }))
    };
    return [dimension, method];
  }));
  return {
    release: {
      id: release.contract_release_id,
      code: "fit-v0.1",
      version: "v0.1",
      specificationDigest: release.specification_digest,
      upstreamContractVersion: "phase2-eligibility-v0.1",
      definitionState: requireReviewed(release, "fit-v0.1 release")
    },
    evaluatorBuild: {
      id: build.evaluator_build_id,
      code: build.evaluator_name,
      version: build.evaluator_version,
      evaluatorName: build.evaluator_name,
      evaluatorVersion: build.evaluator_version,
      buildHash: build.build_hash,
      definitionState: requireVerifiedArtifact(build, "production evaluator build")
    },
    semanticSourceClasses: sourceClasses.map((row) => ({
      sourceClassRegistryId: row.source_class_code,
      sourceClassCode: row.source_class_code,
      ownerLayer: row.owner_layer,
      fitPermitted: row.fit_permitted,
      description: row.description
    })),
    mappingRelationDefinitions: relationDefinitions.map((row) => ({
      relationRegistryId: row.relation_code,
      relationCode: row.relation_code,
      relationDomain: row.relation_domain,
      description: row.description
    })),
    methods,
    reasons: reasons.filter((row) => row.status === "VERIFIED" && row.retired_at === null).map((row) => ({
      identity: { id: row.reason_definition_id, code: row.reason_code, version: "1" },
      contractReleaseRegistryId: row.contract_release_id,
      dimension: row.dimension,
      reasonFamily: row.reason_family,
      direction: row.direction,
      allowedAssessments: row.allowed_assessments,
      description: row.description,
      definitionState: requireReviewed(row, `reason ${row.reason_code}`)
    })),
    financialNormalizations: normalizations.filter((row) => row.status === "VERIFIED" && row.retired_at === null).map((row) => ({
      identity: { id: row.normalization_method_id, code: row.method_code, version: String(row.method_version) },
      contractReleaseRegistryId: row.contract_release_id,
      sourceScope: row.source_scope,
      targetScope: row.target_scope,
      sourcePeriod: row.source_period,
      targetPeriod: row.target_period,
      sourceBasis: row.source_basis,
      targetBasis: row.target_basis,
      sourceCurrency: row.source_currency?.trim() ?? null,
      targetCurrency: row.target_currency?.trim() ?? null,
      normalizationContractCanonicalJson: canonicalJson(row.normalization_contract),
      definitionState: requireVerifiedArtifact(row, `normalization ${row.method_code}`)
    }))
  };
}

// src/execute.ts
var PRODUCTION_EVALUATOR_NAME = "education-platform-fit-engine";
var PRODUCTION_EVALUATOR_VERSION = "0.1.0";
async function executeFitEvaluation(database, request, sourceDatabase = database) {
  if (request.evidence.approvedFinancialNormalizationIds.length !== 0) {
    throw new FitAdapterError("Reviewed Financial normalizations must resume their existing BUILDING evaluation", 400);
  }
  const contract = await resolveFitContract(sourceDatabase, {
    evaluatorName: PRODUCTION_EVALUATOR_NAME,
    evaluatorVersion: PRODUCTION_EVALUATOR_VERSION
  });
  const evaluationId = await database.rpc("start_fit_evaluation", {
    p_profile_version_id: request.profileVersionId,
    p_intent_set_id: request.intentSetId,
    p_program_version_id: request.programVersionId,
    p_taxonomy_release_code: request.taxonomyReleaseCode,
    p_contract_release_id: contract.release.id,
    p_evaluator_build_id: contract.evaluatorBuild.id,
    p_supersedes_evaluation_id: request.supersedesEvaluationId,
    p_eligibility_context_evaluation_id: request.eligibilityContextEvaluationId
  });
  try {
    const evaluation = requireOne(await database.select("fit_evaluations", {
      select: "evaluation_id,evaluation_as_of,evaluation_state",
      evaluation_id: `eq.${evaluationId}`
    }), "started Fit evaluation");
    if (evaluation.evaluation_state !== "BUILDING") throw new FitAdapterError("New Fit evaluation is not BUILDING", 409);
    const input = canonicalizeFitEvaluationInput(await resolveFitEvaluationInput(
      sourceDatabase,
      contract,
      request,
      evaluation.evaluation_as_of
    ));
    const output = evaluateFit(input);
    canonicalFitOutputJson(output);
    const fingerprints = await persistFitEvaluation(database, evaluationId, input, output);
    return { evaluationId, ...fingerprints, output };
  } catch (error) {
    if (error instanceof FitAdapterError) {
      throw new FitAdapterError(error.message, error.status, { evaluationId, detail: error.detail });
    }
    throw new FitAdapterError("Fit evaluation failed closed", 500, {
      evaluationId,
      cause: error instanceof Error ? error.message : String(error)
    });
  }
}

// src/snapshot.ts
async function loadFitEvaluationSnapshot(database, request, evaluationId) {
  let resumeSnapshot = {};
  if (request.evidence.approvedFinancialNormalizationIds.length > 0) {
    if (evaluationId === void 0) throw new FitAdapterError("Approved normalization requires a resume evaluation", 400);
    const value = await database.rpc("get_fit_financial_normalization_resume_snapshot_v017", {
      p_evaluation_id: evaluationId,
      p_financial_normalization_ids: request.evidence.approvedFinancialNormalizationIds
    });
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      throw new FitAdapterError("Financial normalization resume snapshot is not a closed object", 500);
    }
    resumeSnapshot = value;
  }
  const normalizationObservationIds = (resumeSnapshot.fit_financial_normalizations ?? []).map((row) => row.field_observation_id).filter((value) => typeof value === "string");
  const basisObservationIds = (resumeSnapshot.fit_financial_source_pins_v014 ?? []).map((row) => row.billing_basis_observation_id).filter((value) => typeof value === "string");
  const observationIds = [.../* @__PURE__ */ new Set([
    ...request.evidence.canonicalObservationIds,
    ...request.evidence.directFinancialComparisons.flatMap((row) => [row.amountObservationId, row.billingBasisObservationId]),
    ...normalizationObservationIds,
    ...basisObservationIds
  ])];
  const snapshot = await database.rpc("get_fit_evaluation_snapshot_v016", {
    p_profile_version_id: request.profileVersionId,
    p_intent_set_id: request.intentSetId,
    p_program_version_id: request.programVersionId,
    p_taxonomy_release_code: request.taxonomyReleaseCode,
    p_observation_ids: observationIds,
    p_catalog_mapping_ids: request.evidence.catalogMappingIds,
    p_student_course_ids: request.evidence.studentCourseIds,
    p_student_mapping_ids: request.evidence.studentMappingIds,
    p_taxonomy_concept_ids: request.evidence.taxonomyConceptIds,
    p_context_claim_ids: request.evidence.contextClaimIds,
    p_context_mapping_ids: request.evidence.contextMappingIds
  });
  if (snapshot === null || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    throw new FitAdapterError("Fit source snapshot is not a closed object", 500);
  }
  const merged = { ...snapshot, ...resumeSnapshot };
  for (const [table, rows] of Object.entries(merged)) {
    if (!Array.isArray(rows) || rows.some((row) => row === null || typeof row !== "object" || Array.isArray(row))) {
      throw new FitAdapterError(`Fit source snapshot table ${table} is invalid`, 500);
    }
  }
  return new FitSnapshotGateway(merged);
}

// src/normalization-workflow.ts
async function prepareFitFinancialNormalization(database, request) {
  const sourceDatabase = await loadFitEvaluationSnapshot(database, request.evaluation);
  const contract = await resolveFitContract(sourceDatabase, {
    evaluatorName: PRODUCTION_EVALUATOR_NAME,
    evaluatorVersion: PRODUCTION_EVALUATOR_VERSION
  });
  const evaluationId = await database.rpc("start_fit_evaluation", {
    p_profile_version_id: request.evaluation.profileVersionId,
    p_intent_set_id: request.evaluation.intentSetId,
    p_program_version_id: request.evaluation.programVersionId,
    p_taxonomy_release_code: request.evaluation.taxonomyReleaseCode,
    p_contract_release_id: contract.release.id,
    p_evaluator_build_id: contract.evaluatorBuild.id,
    p_supersedes_evaluation_id: request.evaluation.supersedesEvaluationId,
    p_eligibility_context_evaluation_id: request.evaluation.eligibilityContextEvaluationId
  });
  await database.rpc("authorize_fit_evaluation_assembly", {
    p_evaluation_id: evaluationId,
    p_evaluator_build_hash: contract.evaluatorBuild.buildHash
  });
  try {
    const prepared = await database.rpc("prepare_fit_financial_normalization_v017", {
      p_evaluation_id: evaluationId,
      p_amount_observation_id: request.draft.amountObservationId,
      p_billing_basis_observation_id: request.draft.billingBasisObservationId,
      p_financial_constraint_id: request.draft.financialIntentId,
      p_normalization_method_code: request.draft.normalizationMethodCode,
      p_normalization_method_version: request.draft.normalizationMethodVersion,
      p_conversion_evidence_id: request.draft.conversionEvidenceId,
      p_academic_years: request.draft.academicYears,
      p_rounding: request.draft.rounding,
      p_funding_intent_id: request.draft.fundingIntentId
    });
    if (prepared.evaluationId !== evaluationId || prepared.reviewState !== "DRAFT") {
      throw new FitAdapterError("Prepared Financial normalization response drift", 500);
    }
    return prepared;
  } catch (error) {
    if (error instanceof FitAdapterError) throw new FitAdapterError(error.message, error.status, { evaluationId, detail: error.detail });
    throw error;
  }
}
async function resumeFitEvaluation(database, request) {
  const sourceDatabase = await loadFitEvaluationSnapshot(database, request.evaluation, request.evaluationId);
  const contract = await resolveFitContract(sourceDatabase, {
    evaluatorName: PRODUCTION_EVALUATOR_NAME,
    evaluatorVersion: PRODUCTION_EVALUATOR_VERSION
  });
  const evaluation = requireOne(await sourceDatabase.select("fit_evaluations", {
    select: "*",
    evaluation_id: `eq.${request.evaluationId}`
  }), "resumable Fit evaluation");
  if (evaluation.evaluation_state !== "BUILDING" || evaluation.candidate_input_fingerprint !== null || evaluation.profile_version_id !== request.evaluation.profileVersionId || evaluation.intent_set_id !== request.evaluation.intentSetId || evaluation.program_version_id !== request.evaluation.programVersionId || evaluation.taxonomy_release_code !== request.evaluation.taxonomyReleaseCode || evaluation.contract_release_id !== contract.release.id || evaluation.evaluator_build_id !== contract.evaluatorBuild.id) {
    throw new FitAdapterError("Resume request does not exactly match an unsealed BUILDING evaluation", 409);
  }
  const normalization = requireOne(await sourceDatabase.select("fit_financial_normalizations", {
    select: "financial_normalization_id,evaluation_id,source_pin_id",
    financial_normalization_id: `eq.${request.normalizationId}`
  }), "reviewed Financial normalization");
  const sourcePin = requireOne((await sourceDatabase.select("fit_financial_source_pins_v014", { select: "*" })).filter((candidate) => candidate.source_pin_id === normalization.source_pin_id && candidate.evaluation_id === request.evaluationId), "Financial source pin");
  const fundingInputs = (await sourceDatabase.select("fit_financial_conversion_inputs_v014", { select: "*" })).filter((candidate) => candidate.financial_normalization_id === normalization.financial_normalization_id && candidate.input_role === "AVAILABLE_FUNDING");
  if (fundingInputs.length > 1 || fundingInputs.length === 1 && fundingInputs[0].intent_declaration_id === null) {
    throw new FitAdapterError("Reviewed Financial funding provenance is invalid", 422);
  }
  const assembly = {
    normalizationId: normalization.financial_normalization_id,
    amountManifestItemId: sourcePin.amount_manifest_item_id,
    basisManifestItemId: sourcePin.basis_manifest_item_id,
    amountObservationId: sourcePin.amount_observation_id,
    basisObservationId: sourcePin.billing_basis_observation_id,
    fundingIntentId: fundingInputs[0]?.intent_declaration_id ?? null
  };
  const input = canonicalizeFitEvaluationInput(await resolveFitEvaluationInput(
    sourceDatabase,
    contract,
    request.evaluation,
    evaluation.evaluation_as_of
  ));
  const output = evaluateFit(input);
  canonicalFitOutputJson(output);
  const fingerprints = await persistFitEvaluation(database, request.evaluationId, input, output, [assembly]);
  return { evaluationId: request.evaluationId, ...fingerprints, output };
}

// src/request.ts
function object(value, label) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new FitAdapterError(`${label} must be an object`, 400);
  }
  return value;
}
function exactKeys(value, keys, label) {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    throw new FitAdapterError(`${label} must use the exact closed request contract`, 400);
  }
}
function text(value, label) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new FitAdapterError(`${label} is required`, 400);
  }
  return value;
}
function nullableText(value, label) {
  return value === null ? null : text(value, label);
}
function textArray(value, label) {
  if (!Array.isArray(value)) throw new FitAdapterError(`${label} must be an array`, 400);
  const values = value.map((item, index) => text(item, `${label}[${index}]`));
  if (new Set(values).size !== values.length) throw new FitAdapterError(`${label} contains duplicates`, 400);
  return values;
}
function exactDecimal(value, label) {
  const result = text(value, label);
  if (!/^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(result) || Number(result) <= 0) {
    throw new FitAdapterError(`${label} must be a positive exact decimal string`, 400);
  }
  return result;
}
function parseFitEvaluationRequest(value) {
  const request = object(value, "request");
  exactKeys(request, [
    "profileVersionId",
    "intentSetId",
    "programVersionId",
    "taxonomyReleaseCode",
    "supersedesEvaluationId",
    "eligibilityContextEvaluationId",
    "evidence"
  ], "request");
  const evidence = object(request.evidence, "request.evidence");
  exactKeys(evidence, [
    "canonicalObservationIds",
    "catalogMappingIds",
    "studentCourseIds",
    "studentMappingIds",
    "taxonomyConceptIds",
    "contextClaimIds",
    "contextMappingIds",
    "accessContextId",
    "directFinancialComparisons",
    "approvedFinancialNormalizationIds"
  ], "request.evidence");
  if (!Array.isArray(evidence.directFinancialComparisons)) {
    throw new FitAdapterError("directFinancialComparisons must be an array", 400);
  }
  const directFinancialComparisons = evidence.directFinancialComparisons.map((item, index) => {
    const row = object(item, `directFinancialComparisons[${index}]`);
    exactKeys(row, ["financialIntentId", "amountObservationId", "billingBasisObservationId"], `directFinancialComparisons[${index}]`);
    return {
      financialIntentId: text(row.financialIntentId, "financialIntentId"),
      amountObservationId: text(row.amountObservationId, "amountObservationId"),
      billingBasisObservationId: text(row.billingBasisObservationId, "billingBasisObservationId")
    };
  });
  const directKeys = directFinancialComparisons.map((item) => item.financialIntentId);
  if (new Set(directKeys).size !== directKeys.length) {
    throw new FitAdapterError("Only one direct Financial comparison is allowed per intent", 400);
  }
  return {
    profileVersionId: text(request.profileVersionId, "profileVersionId"),
    intentSetId: text(request.intentSetId, "intentSetId"),
    programVersionId: text(request.programVersionId, "programVersionId"),
    taxonomyReleaseCode: text(request.taxonomyReleaseCode, "taxonomyReleaseCode"),
    supersedesEvaluationId: nullableText(request.supersedesEvaluationId, "supersedesEvaluationId"),
    eligibilityContextEvaluationId: nullableText(request.eligibilityContextEvaluationId, "eligibilityContextEvaluationId"),
    evidence: {
      canonicalObservationIds: textArray(evidence.canonicalObservationIds, "canonicalObservationIds"),
      catalogMappingIds: textArray(evidence.catalogMappingIds, "catalogMappingIds"),
      studentCourseIds: textArray(evidence.studentCourseIds, "studentCourseIds"),
      studentMappingIds: textArray(evidence.studentMappingIds, "studentMappingIds"),
      taxonomyConceptIds: textArray(evidence.taxonomyConceptIds, "taxonomyConceptIds"),
      contextClaimIds: textArray(evidence.contextClaimIds, "contextClaimIds"),
      contextMappingIds: textArray(evidence.contextMappingIds, "contextMappingIds"),
      accessContextId: nullableText(evidence.accessContextId, "accessContextId"),
      directFinancialComparisons,
      approvedFinancialNormalizationIds: textArray(evidence.approvedFinancialNormalizationIds, "approvedFinancialNormalizationIds")
    }
  };
}
function parseFitFinancialNormalizationDraftRequest(value) {
  const request = object(value, "request");
  exactKeys(request, ["evaluation", "draft"], "request");
  const evaluation = parseFitEvaluationRequest(request.evaluation);
  if (evaluation.evidence.directFinancialComparisons.length !== 0 || evaluation.evidence.approvedFinancialNormalizationIds.length !== 0) {
    throw new FitAdapterError("Normalization preparation cannot include completed Financial comparisons", 400);
  }
  const draft = object(request.draft, "request.draft");
  exactKeys(draft, [
    "financialIntentId",
    "amountObservationId",
    "billingBasisObservationId",
    "normalizationMethodCode",
    "normalizationMethodVersion",
    "conversionEvidenceId",
    "academicYears",
    "rounding",
    "fundingIntentId"
  ], "request.draft");
  if (draft.normalizationMethodCode !== "ANNUAL_TO_PROGRAM" && draft.normalizationMethodCode !== "ANNUAL_TO_NET_PROGRAM") {
    throw new FitAdapterError("Unsupported normalization method", 400);
  }
  if (draft.normalizationMethodVersion !== 1) throw new FitAdapterError("Unsupported normalization method version", 400);
  if (draft.rounding !== "NONE") {
    throw new FitAdapterError("The v017 normalization methods permit only exact no-rounding arithmetic", 400);
  }
  const fundingIntentId = nullableText(draft.fundingIntentId, "fundingIntentId");
  if (draft.normalizationMethodCode === "ANNUAL_TO_NET_PROGRAM" !== (fundingIntentId !== null)) {
    throw new FitAdapterError("Net normalization requires exactly one funding intent; gross normalization forbids it", 400);
  }
  return {
    evaluation,
    draft: {
      financialIntentId: text(draft.financialIntentId, "financialIntentId"),
      amountObservationId: text(draft.amountObservationId, "amountObservationId"),
      billingBasisObservationId: text(draft.billingBasisObservationId, "billingBasisObservationId"),
      normalizationMethodCode: draft.normalizationMethodCode,
      normalizationMethodVersion: 1,
      conversionEvidenceId: text(draft.conversionEvidenceId, "conversionEvidenceId"),
      academicYears: exactDecimal(draft.academicYears, "academicYears"),
      rounding: "NONE",
      fundingIntentId
    }
  };
}
function parseFitFinancialNormalizationReviewRequest(value) {
  const request = object(value, "request");
  exactKeys(request, ["normalizationId", "verificationEvidenceId"], "request");
  return {
    normalizationId: text(request.normalizationId, "normalizationId"),
    verificationEvidenceId: text(request.verificationEvidenceId, "verificationEvidenceId")
  };
}
function parseFitEvaluationResumeRequest(value) {
  const request = object(value, "request");
  exactKeys(request, ["evaluationId", "normalizationId", "evaluation"], "request");
  const evaluationId = text(request.evaluationId, "evaluationId");
  const normalizationId = text(request.normalizationId, "normalizationId");
  const evaluation = parseFitEvaluationRequest(request.evaluation);
  if (evaluation.evidence.directFinancialComparisons.length !== 0 || evaluation.evidence.approvedFinancialNormalizationIds.length !== 1 || evaluation.evidence.approvedFinancialNormalizationIds[0] !== normalizationId) {
    throw new FitAdapterError("Resume requires exactly the reviewed normalization and no direct Financial comparison", 400);
  }
  return { evaluationId, normalizationId, evaluation };
}
export {
  FitAdapterError,
  FitExecutorPostgrestGateway,
  FitSnapshotGateway,
  PRODUCTION_EVALUATOR_NAME,
  PRODUCTION_EVALUATOR_VERSION,
  PostgrestGateway,
  calculateReviewedFinancialNormalization,
  equalExactDecimals,
  executeFitEvaluation,
  loadFitEvaluationSnapshot,
  multiplyExactDecimals,
  parseFitEvaluationRequest,
  parseFitEvaluationResumeRequest,
  parseFitFinancialNormalizationDraftRequest,
  parseFitFinancialNormalizationReviewRequest,
  persistFitEvaluation,
  postgresIn,
  prepareFitFinancialNormalization,
  requireOne,
  resolveFitContract,
  resolveFitEvaluationInput,
  resumeFitEvaluation,
  subtractExactDecimals
};
