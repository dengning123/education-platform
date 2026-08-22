import {
  FIT_DIMENSIONS,
  type DecisionManifestItem,
  type FitEvaluationInput,
  type FitEvaluationOutput,
  type FitSignal,
} from "@education-platform/fit-engine";
import { FitAdapterError, type FitDatabaseGateway, requireOne } from "./database-gateway.js";

type InsertedManifest = { manifest_item_id: string };
type InsertedInputState = { input_state_id: string };
type InsertedResult = { dimension_result_id: string };
type InsertedSignal = { signal_id: string };
type CompletedEvaluation = {
  evaluation_state: string;
  candidate_input_fingerprint: string | null;
  result_fingerprint: string | null;
};

export type ApprovedFinancialNormalizationAssembly = Readonly<{
  normalizationId: string;
  amountManifestItemId: string;
  basisManifestItemId: string;
  amountObservationId: string;
  basisObservationId: string;
  fundingIntentId: string | null;
}>;

function lastKeyPart(key: string): string {
  const value = key.split(":").at(-1);
  if (value === undefined || value.length === 0) throw new FitAdapterError(`Invalid adapter manifest key ${key}`, 500);
  return value;
}

function itemType(item: Exclude<DecisionManifestItem, { kind: "DIRECT_FINANCIAL_COMPARABLE" | "APPROVED_FINANCIAL_NORMALIZATION" }>) {
  switch (item.kind) {
    case "FIT_INTENT": return "FIT_INTENT_DECLARATION";
    case "STUDENT_ACCESS_CONTEXT": return "FIT_STUDENT_ACCESS_CONTEXT";
    case "PHASE2_GOAL": return "PHASE2_STUDENT_GOAL";
    case "PHASE2_PREFERENCE": return "PHASE2_STUDENT_PREFERENCE";
    case "PHASE2_COURSE": return "PHASE2_STUDENT_COURSE";
    case "PHASE2_COMPLETENESS": return "PHASE2_STUDENT_COMPLETENESS";
    case "VERIFIED_MAPPING": return item.mappingKind === "PHASE2_STUDENT" ? "PHASE2_STUDENT_MAPPING" : item.mappingKind === "CATALOG" ? "CATALOG_MAPPING" : "FIT_CONTEXT_MAPPING";
    case "TAXONOMY_CONCEPT": return "TAXONOMY_CONCEPT";
    case "CANONICAL_PROGRAM_FACT": return "CATALOG_FIELD_OBSERVATION";
    case "HISTORICAL_CONTEXT_SELECTION": return "FIT_CONTEXT_CLAIM_SELECTION";
  }
}

async function insertManifestParent(
  database: FitDatabaseGateway,
  evaluationId: string,
  profileVersionId: string,
  item: DecisionManifestItem,
  forcedItemType?: string,
): Promise<string> {
  const row = requireOne(await database.insert<InsertedManifest>("fit_manifest_items", [{
    evaluation_id: evaluationId,
    profile_version_id: profileVersionId,
    method_id: item.ref.methodRegistryId,
    input_policy_id: item.ref.inputPolicyRegistryId,
    item_type: forcedItemType ?? (item.kind === "DIRECT_FINANCIAL_COMPARABLE" ? "CATALOG_FIELD_OBSERVATION" : item.kind === "APPROVED_FINANCIAL_NORMALIZATION" ? "FIT_FINANCIAL_NORMALIZATION" : itemType(item)),
    authority_role: item.ref.authorityRole,
    source_class_code: item.ref.sourceClass,
  }]), "inserted manifest item");
  return row.manifest_item_id;
}

async function insertManifestItem(
  database: FitDatabaseGateway,
  evaluationId: string,
  profileVersionId: string,
  intentSetId: string,
  item: Exclude<DecisionManifestItem, { kind: "DIRECT_FINANCIAL_COMPARABLE" | "APPROVED_FINANCIAL_NORMALIZATION" }>,
): Promise<string> {
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

async function insertDirectFinancial(
  database: FitDatabaseGateway,
  evaluationId: string,
  profileVersionId: string,
  item: Extract<DecisionManifestItem, { kind: "DIRECT_FINANCIAL_COMPARABLE" }>,
): Promise<readonly string[]> {
  const parts = item.sourcePinId.split(":");
  const amountObservationId = parts.at(-2);
  const basisObservationId = parts.at(-1);
  if (amountObservationId === undefined || basisObservationId === undefined) throw new FitAdapterError("Invalid direct Financial semantic source", 500);
  const amountManifestId = await insertManifestParent(database, evaluationId, profileVersionId, item, "CATALOG_FIELD_OBSERVATION");
  const basisManifestId = await insertManifestParent(database, evaluationId, profileVersionId, item, "CATALOG_FIELD_OBSERVATION");
  await database.insert("fit_manifest_catalog_observations", [
    { manifest_item_id: amountManifestId, evaluation_id: evaluationId, profile_version_id: profileVersionId, field_observation_id: amountObservationId },
    { manifest_item_id: basisManifestId, evaluation_id: evaluationId, profile_version_id: profileVersionId, field_observation_id: basisObservationId },
  ]);
  await database.rpc("pin_fit_financial_source_v014", {
    p_evaluation_id: evaluationId,
    p_amount_manifest_item_id: amountManifestId,
    p_basis_manifest_item_id: basisManifestId,
  });
  return [amountManifestId, basisManifestId];
}

async function insertApprovedFinancialNormalization(
  database: FitDatabaseGateway,
  evaluationId: string,
  profileVersionId: string,
  item: Extract<DecisionManifestItem, { kind: "APPROVED_FINANCIAL_NORMALIZATION" }>,
  assembly: ApprovedFinancialNormalizationAssembly,
): Promise<readonly string[]> {
  if (assembly.normalizationId !== item.ref.sourceId) {
    throw new FitAdapterError("Reviewed Financial normalization assembly identity drift", 500);
  }
  const manifestItemId = await insertManifestParent(database, evaluationId, profileVersionId, item);
  await database.insert("fit_manifest_financial_normalizations", [{
    manifest_item_id: manifestItemId,
    evaluation_id: evaluationId,
    profile_version_id: profileVersionId,
    financial_normalization_id: assembly.normalizationId,
  }]);
  return [manifestItemId, assembly.amountManifestItemId, assembly.basisManifestItemId];
}

function signalMatch(reasonRefs: readonly string[], signal: FitSignal): boolean {
  const refs = new Set([...signal.evidenceManifestRefs, ...(signal.intentManifestRef === null ? [] : [signal.intentManifestRef])]);
  return reasonRefs.every((value) => refs.has(value));
}

export async function persistFitEvaluation(
  database: FitDatabaseGateway,
  evaluationId: string,
  input: FitEvaluationInput,
  output: FitEvaluationOutput,
  approvedFinancialAssemblies: readonly ApprovedFinancialNormalizationAssembly[] = [],
): Promise<{ candidateInputFingerprint: string; resultFingerprint: string }> {
  await database.rpc("authorize_fit_evaluation_assembly", {
    p_evaluation_id: evaluationId,
    p_evaluator_build_hash: input.evaluator.buildHash,
  });
  const manifestIds = new Map<string, readonly string[]>();
  const intentIds = new Map<string, string>();
  const directPins = new Map<string, readonly string[]>();
  const reviewedWitnessManifestIds = new Map<string, string>();
  for (const assembly of approvedFinancialAssemblies) {
    for (const [observationId, manifestItemId] of [
      [assembly.amountObservationId, assembly.amountManifestItemId],
      [assembly.basisObservationId, assembly.basisManifestItemId],
    ] as const) {
      const existing = reviewedWitnessManifestIds.get(observationId);
      if (existing !== undefined && existing !== manifestItemId) {
        throw new FitAdapterError("Reviewed Financial witness has conflicting manifest identity", 500);
      }
      reviewedWitnessManifestIds.set(observationId, manifestItemId);
    }
  }
  for (const item of input.manifest) {
    let ids: readonly string[];
    if (item.kind === "APPROVED_FINANCIAL_NORMALIZATION") {
      const assembly = requireOne(approvedFinancialAssemblies.filter((candidate) => candidate.normalizationId === item.ref.sourceId), "reviewed Financial normalization assembly");
      ids = await insertApprovedFinancialNormalization(database, evaluationId, input.profile.versionId, item, assembly);
    } else if (item.kind === "DIRECT_FINANCIAL_COMPARABLE") {
      const cached = directPins.get(item.sourcePinId);
      ids = cached ?? await insertDirectFinancial(database, evaluationId, input.profile.versionId, item);
      directPins.set(item.sourcePinId, ids);
    } else if (item.kind === "CANONICAL_PROGRAM_FACT" && reviewedWitnessManifestIds.has(item.selectedObservationId)) {
      // Preparation already inserted and pinned this exact manifest row. Reuse
      // it rather than creating an incidental duplicate during resume.
      ids = [reviewedWitnessManifestIds.get(item.selectedObservationId)!];
    } else {
      ids = [await insertManifestItem(database, evaluationId, input.profile.versionId, input.intentSet.id, item)];
    }
    manifestIds.set(item.ref.manifestItemKey, ids);
    if (item.kind === "FIT_INTENT") intentIds.set(item.ref.manifestItemKey, item.intent.intentId);
  }
  for (const assembly of approvedFinancialAssemblies) {
    if (assembly.fundingIntentId === null) continue;
    const normalizationItem = requireOne(input.manifest.filter(
      (item) => item.kind === "APPROVED_FINANCIAL_NORMALIZATION" && item.ref.sourceId === assembly.normalizationId,
    ), "reviewed net Financial normalization manifest");
    const fundingItem = requireOne(input.manifest.filter(
      (item) => item.kind === "FIT_INTENT" && item.intent.kind === "FINANCIAL_CONSTRAINT" &&
        item.intent.intentId === assembly.fundingIntentId && item.intent.semantics === "AVAILABLE_FUNDING",
    ), "reviewed net Financial funding intent");
    const normalizationIds = manifestIds.get(normalizationItem.ref.manifestItemKey);
    const fundingIds = manifestIds.get(fundingItem.ref.manifestItemKey);
    if (normalizationIds === undefined || fundingIds === undefined) {
      throw new FitAdapterError("Reviewed net Financial composite provenance is incomplete", 500);
    }
    manifestIds.set(normalizationItem.ref.manifestItemKey, [...new Set([...normalizationIds, ...fundingIds])]);
  }

  const stateIds = new Map<string, string>();
  const stateRows = new Map<string, (typeof input.inputStates)[number]>();
  for (const state of input.inputStates) {
    // Frozen SQL v0.1 requires pointers only for the availability classes that
    // authorize them: INCOMPLETE uses completeness; STALE/SOURCE_CONFLICT use
    // same-policy provenance. NOT_SUPPLIED is authorized by its typed state and
    // explanation, so cross-policy limiting context is not persisted as a
    // provenance pointer.
    const completeness = state.availability !== "INCOMPLETE" || state.completenessManifestItemKey === null
      ? null
      : manifestIds.get(state.completenessManifestItemKey)?.[0] ?? null;
    const provenance = !["STALE_SOURCE", "SOURCE_CONFLICT"].includes(state.availability) || state.provenanceManifestItemKey === null
      ? null
      : manifestIds.get(state.provenanceManifestItemKey)?.[0] ?? null;
    const inserted = requireOne(await database.insert<InsertedInputState>("fit_input_domain_states", [{
      evaluation_id: evaluationId,
      profile_version_id: input.profile.versionId,
      method_id: state.methodRegistryId,
      input_policy_id: state.inputPolicyRegistryId,
      availability: state.availability,
      completeness_manifest_item_id: completeness,
      provenance_manifest_item_id: provenance,
      explanation: state.availability === "INCLUDED" ? null : "The exact selected evidence set did not supply this policy input.",
    }]), "inserted Fit input state");
    stateIds.set(state.inputPolicyRegistryId, inserted.input_state_id);
    stateRows.set(state.inputPolicyRegistryId, state);
  }

  for (const dimension of FIT_DIMENSIONS) {
    const decision = output.dimensions[dimension];
    const result = requireOne(await database.insert<InsertedResult>("fit_dimension_results", [{
      evaluation_id: evaluationId,
      dimension,
      assessment: decision.assessment,
      confidence: decision.confidence,
      evidence_coverage: decision.evidenceCoverage,
      method_id: decision.methodRegistryId,
      inference_category: decision.inferenceCategory,
      presentation_explanation: null,
    }]), "inserted Fit dimension result");
    const insertedSignals: { signal: FitSignal; signalId: string }[] = [];
    for (const signal of decision.signals) {
      const intentDeclarationId = signal.intentManifestRef === null ? null : intentIds.get(signal.intentManifestRef) ?? null;
      const inserted = requireOne(await database.insert<InsertedSignal>("fit_signals", [{
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
        international_high_impact: signal.internationalHighImpact,
      }]), "inserted Fit signal");
      insertedSignals.push({ signal, signalId: inserted.signal_id });
      const evidenceKeys = [...new Set([...signal.evidenceManifestRefs, ...(signal.intentManifestRef === null ? [] : [signal.intentManifestRef])])];
      const evidenceRows = evidenceKeys.flatMap((key) => {
        const ids = manifestIds.get(key);
        if (ids === undefined) throw new FitAdapterError(`Signal references unknown manifest key ${key}`, 500);
        return ids.map((manifest_item_id) => ({ signal_id: inserted.signal_id, evaluation_id: evaluationId, manifest_item_id }));
      });
      await database.insert("fit_signal_evidence", evidenceRows);
    }
    for (const reason of decision.reasons) {
      const signal = reason.signalTypeRegistryId === null ? undefined : insertedSignals.find((candidate) => candidate.signal.signalTypeRegistryId === reason.signalTypeRegistryId && signalMatch(reason.exactManifestRefs, candidate.signal));
      let inputStateId: string | null = null;
      if (signal === undefined) {
        if (reason.inputPolicyRegistryId !== null) inputStateId = stateIds.get(reason.inputPolicyRegistryId) ?? null;
        if (inputStateId === null) {
          const unavailable = [...stateRows.entries()].find(([, state]) => state.methodRegistryId === decision.methodRegistryId && state.availability !== "INCLUDED");
          inputStateId = unavailable === undefined ? null : stateIds.get(unavailable[0]) ?? null;
        }
      }
      if (signal === undefined && inputStateId === null) throw new FitAdapterError(`Reason ${reason.reasonCode} has no exact SQL provenance`, 422);
      await database.insert("fit_dimension_reasons", [{
        dimension_result_id: result.dimension_result_id,
        evaluation_id: evaluationId,
        reason_definition_id: reason.reasonDefinitionRegistryId,
        direction: reason.direction,
        signal_id: signal?.signalId ?? null,
        input_state_id: signal === undefined ? inputStateId : null,
        presentation_explanation: null,
      }]);
    }
  }
  const candidateInputFingerprint = await database.rpc<string>("seal_fit_evaluation_inputs", { p_evaluation_id: evaluationId });
  await database.rpc<string>("finalize_fit_evaluation", { p_evaluation_id: evaluationId });
  const completed = requireOne(await database.select<CompletedEvaluation>("fit_evaluations", {
    select: "evaluation_state,candidate_input_fingerprint,result_fingerprint",
    evaluation_id: `eq.${evaluationId}`,
  }), "completed Fit evaluation");
  if (
    completed.evaluation_state !== "COMPLETED"
    || completed.candidate_input_fingerprint !== candidateInputFingerprint
    || completed.result_fingerprint === null
    || !/^[0-9a-f]{64}$/.test(completed.result_fingerprint)
  ) {
    throw new FitAdapterError("Finalized Fit fingerprints are inconsistent", 500);
  }
  return { candidateInputFingerprint, resultFingerprint: completed.result_fingerprint };
}
