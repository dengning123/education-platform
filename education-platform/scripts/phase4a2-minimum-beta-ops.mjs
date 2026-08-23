#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const CHECKER_VERSION = "phase4a2-minimum-beta-v1";
export const DEFAULT_API_BASE = "https://api.supabase.com";
export const DEFAULT_EXPECTED_IDENTITY = Object.freeze({
  semanticRelease: "fit-v0.1",
  deployedBuild: "099a348e6b2ea9dc757efa2faacc675ba673ad5d",
  boundaryVersion: "fit-edge-http-v1",
  functionVersion: 9,
});

export const EXPECTED_FUNCTIONS = Object.freeze([
  "fit-evaluate",
  "fit-normalization-prepare",
  "fit-normalization-review",
  "fit-normalization-resume",
]);

export const EXPECTED_ENDPOINTS = Object.freeze([
  "FIT_EVALUATE",
  "FIT_NORMALIZATION_PREPARE",
  "FIT_NORMALIZATION_REVIEW",
  "FIT_NORMALIZATION_RESUME",
]);

export const PUBLIC_ERROR_CODES = Object.freeze([
  "AUTHENTICATION_REQUIRED",
  "CORS_ORIGIN_DENIED",
  "DEPENDENCY_DEADLINE_EXCEEDED",
  "FIT_EVALUATION_FAILED_CLOSED",
  "FIT_EVALUATION_REJECTED",
  "FIT_NORMALIZATION_PREPARATION_FAILED_CLOSED",
  "FIT_NORMALIZATION_PREPARATION_REJECTED",
  "FIT_NORMALIZATION_REVIEW_FAILED_CLOSED",
  "FIT_NORMALIZATION_REVIEW_REJECTED",
  "FIT_NORMALIZATION_RESUME_FAILED_CLOSED",
  "FIT_NORMALIZATION_RESUME_REJECTED",
  "INVALID_JSON",
  "METHOD_NOT_ALLOWED",
  "PAYLOAD_TOO_LARGE",
  "PROFILE_NOT_FOUND",
  "REQUEST_ABORTED",
  "REQUEST_DEADLINE_EXCEEDED",
  "SERVICE_CONFIGURATION_MISSING",
  "UNSUPPORTED_MEDIA_TYPE",
]);

export const DATABASE_CHECK_CODES = Object.freeze([
  "ELIGIBILITY_COMPLETED_FINGERPRINT_INVARIANT",
  "ELIGIBILITY_STALE_BUILDING_GT_15M",
  "FINANCIAL_DRAFT_GT_72H",
  "FIT_COMPLETED_FINGERPRINT_INVARIANT",
  "FIT_STALE_BUILDING_GT_15M",
  "VERIFIED_FINANCIAL_GRAPH_INVARIANT",
]);

const CONFIG_VALUE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;
const PROJECT_REF_PATTERN = /^[a-z]{20}$/;
const ORGANIZATION_SLUG_PATTERN = /^[\w-]{1,128}$/;
const MAX_RESPONSE_BYTES = 1024 * 1024;
const REQUEST_TIMEOUT_MS = 20_000;
const SQL_QUERY_BEGIN = "-- PHASE4A2_COUNT_QUERY_BEGIN";
const SQL_QUERY_END = "-- PHASE4A2_COUNT_QUERY_END";

export class OperationalCheckError extends Error {
  constructor(code, status = null) {
    super(code);
    this.name = "OperationalCheckError";
    this.code = code;
    this.status = Number.isInteger(status) ? status : null;
  }
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function boundedCount(value, code = "INVALID_COUNT") {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new OperationalCheckError(code);
  return parsed;
}

function boundedVersion(value) {
  return boundedCount(value, "INVALID_FUNCTION_VERSION");
}

function validateProjectRef(value) {
  if (!PROJECT_REF_PATTERN.test(value)) throw new OperationalCheckError("INVALID_PROJECT_REF");
  return value;
}

function validateConfigValue(value, code) {
  if (!CONFIG_VALUE_PATTERN.test(value)) throw new OperationalCheckError(code);
  return value;
}

function parsePositiveInteger(value, code, maximum) {
  if (!/^[0-9]+$/.test(String(value))) throw new OperationalCheckError(code);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1 || parsed > maximum) {
    throw new OperationalCheckError(code);
  }
  return parsed;
}

function sqlString(value) {
  return `'${value.replaceAll("'", "''")}'`;
}

function sqlList(values) {
  return values.map(sqlString).join(",");
}

export function buildLogQueries(identity) {
  const endpoints = sqlList(EXPECTED_ENDPOINTS);
  const errorCodes = sqlList(PUBLIC_ERROR_CODES);
  return Object.freeze({
    applicationAggregate:
      "select " +
      "JSONExtractString(event_message, 'endpoint') as endpoint, " +
      "JSONExtractString(event_message, 'semanticRelease') as semantic_release, " +
      "JSONExtractString(event_message, 'deployedBuild') as deployed_build, " +
      "JSONExtractString(event_message, 'boundaryVersion') as boundary_version, " +
      "JSONExtractUInt(event_message, 'status') as status, " +
      "JSONExtractString(event_message, 'statusClass') as status_class, " +
      "if(JSONExtractRaw(event_message, 'errorCode') = 'null', 'NONE', " +
        "JSONExtractString(event_message, 'errorCode')) as error_code, " +
      "JSONExtractBool(event_message, 'coldStart') as cold_start, count() as event_count " +
      "from logs where source = 'function_logs' " +
      "and JSONExtractString(event_message, 'event') = 'FIT_EDGE_REQUEST_V2' " +
      "group by endpoint, semantic_release, deployed_build, boundary_version, " +
        "status, status_class, error_code, cold_start " +
      "order by endpoint, status, error_code, cold_start limit 200",
    contractCounts:
      "select count() as event_count, " +
      "countIf(length(JSONExtractKeys(event_message)) = 12) as exact_key_count, " +
      "countIf(match(JSONExtractString(event_message, 'requestId'), " +
        "'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')) " +
        "as valid_request_id_count, " +
      `countIf(JSONExtractString(event_message, 'endpoint') in (${endpoints})) as valid_endpoint_count, ` +
      `countIf(JSONExtractString(event_message, 'semanticRelease') = ${sqlString(identity.semanticRelease)}) ` +
        "as expected_semantic_release_count, " +
      `countIf(JSONExtractString(event_message, 'deployedBuild') = ${sqlString(identity.deployedBuild)}) ` +
        "as expected_build_count, " +
      `countIf(JSONExtractString(event_message, 'boundaryVersion') = ${sqlString(identity.boundaryVersion)}) ` +
        "as expected_boundary_count, " +
      "countIf(JSONExtractString(event_message, 'stage') = 'RESPONSE') as expected_stage_count, " +
      "countIf(JSONExtractUInt(event_message, 'status') between 100 and 599) as valid_status_count, " +
      "countIf(JSONExtractString(event_message, 'statusClass') = " +
        "concat(toString(intDiv(JSONExtractUInt(event_message, 'status'), 100)), 'xx')) " +
        "as valid_status_class_count, " +
      "countIf(JSONExtractUInt(event_message, 'durationMs') <= 600000) as bounded_duration_count, " +
      "countIf(JSONExtractRaw(event_message, 'errorCode') = 'null' or " +
        `JSONExtractString(event_message, 'errorCode') in (${errorCodes})) as valid_error_code_count ` +
      "from logs where source = 'function_logs' " +
      "and JSONExtractString(event_message, 'event') = 'FIT_EDGE_REQUEST_V2'",
    gatewayAuthAggregate:
      "select multiIf(" +
        "endsWith(toString(log_attributes['request.pathname']), '/fit-evaluate'), 'FIT_EVALUATE', " +
        "endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-prepare'), " +
          "'FIT_NORMALIZATION_PREPARE', " +
        "endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-review'), " +
          "'FIT_NORMALIZATION_REVIEW', " +
        "endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-resume'), " +
          "'FIT_NORMALIZATION_RESUME', 'OTHER') as endpoint, " +
      "toUInt16OrZero(toString(log_attributes['response.status_code'])) as status, " +
      "count() as event_count from logs where source = 'function_edge_logs' and " +
      "toUInt16OrZero(toString(log_attributes['response.status_code'])) in (401,403) and (" +
        "endsWith(toString(log_attributes['request.pathname']), '/fit-evaluate') or " +
        "endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-prepare') or " +
        "endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-review') or " +
        "endsWith(toString(log_attributes['request.pathname']), '/fit-normalization-resume')) " +
      "group by endpoint, status order by endpoint, status limit 20",
  });
}

async function fetchJson({ fetchImpl, apiBase, accessToken, path, init = {}, expectedStatuses }) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  let response;
  try {
    response = await fetchImpl(new URL(path, apiBase), {
      ...init,
      signal: controller.signal,
      headers: {
        authorization: `Bearer ${accessToken}`,
        accept: "application/json",
        ...init.headers,
      },
    });
  } catch {
    throw new OperationalCheckError("REMOTE_REQUEST_FAILED");
  } finally {
    clearTimeout(timer);
  }
  if (!expectedStatuses.includes(response.status)) {
    throw new OperationalCheckError("REMOTE_STATUS_REJECTED", response.status);
  }
  let text;
  try {
    text = await response.text();
  } catch {
    throw new OperationalCheckError("REMOTE_BODY_UNREADABLE", response.status);
  }
  if (text.length > MAX_RESPONSE_BYTES) throw new OperationalCheckError("REMOTE_BODY_TOO_LARGE");
  try {
    return text.length === 0 ? null : JSON.parse(text);
  } catch {
    throw new OperationalCheckError("REMOTE_JSON_INVALID", response.status);
  }
}

async function queryLogs(context, sql) {
  const url = new URL(`/v1/projects/${context.projectRef}/analytics/endpoints/logs`, context.apiBase);
  url.searchParams.set("sql", sql);
  url.searchParams.set("iso_timestamp_start", context.windowStart);
  url.searchParams.set("iso_timestamp_end", context.windowEnd);
  const body = await fetchJson({
    ...context,
    path: `${url.pathname}${url.search}`,
    expectedStatuses: [200],
  });
  if (!isRecord(body) || body.error !== null || !Array.isArray(body.result)) {
    throw new OperationalCheckError("LOG_QUERY_CONTRACT_INVALID");
  }
  return body.result;
}

function sanitizeDeployment(rows, expectedVersion) {
  if (!Array.isArray(rows)) throw new OperationalCheckError("DEPLOYMENT_RESPONSE_INVALID");
  const expected = new Set(EXPECTED_FUNCTIONS);
  const functions = rows.filter(isRecord)
    .filter((row) => expected.has(String(row.slug ?? row.name)))
    .map((row) => ({
      name: String(row.slug ?? row.name),
      status: row.status === "ACTIVE" ? "ACTIVE" : "UNEXPECTED",
      version: boundedVersion(row.version),
      verifyJwt: row.verify_jwt === true,
    }))
    .sort((left, right) => left.name.localeCompare(right.name));
  if (functions.length !== EXPECTED_FUNCTIONS.length || new Set(functions.map((row) => row.name)).size !== functions.length) {
    throw new OperationalCheckError("DEPLOYMENT_SET_MISMATCH");
  }
  const matchesExpected = functions.every((row) =>
    row.status === "ACTIVE" && row.version === expectedVersion && row.verifyJwt === true
  );
  return { functions, matchesExpected };
}

function sanitizeApplicationAggregate(rows, identity) {
  const endpoints = new Set(EXPECTED_ENDPOINTS);
  const errors = new Set(["NONE", ...PUBLIC_ERROR_CODES]);
  if (!Array.isArray(rows) || rows.length > 200) {
    throw new OperationalCheckError("APPLICATION_AGGREGATE_INVALID");
  }
  return rows.map((row) => {
    if (!isRecord(row)) throw new OperationalCheckError("APPLICATION_AGGREGATE_INVALID");
    const endpoint = String(row.endpoint);
    const semanticRelease = String(row.semantic_release);
    const deployedBuild = String(row.deployed_build);
    const boundaryVersion = String(row.boundary_version);
    const status = boundedCount(row.status, "INVALID_HTTP_STATUS");
    const statusClass = String(row.status_class);
    const errorCode = String(row.error_code);
    const coldStart = row.cold_start === true || row.cold_start === 1 || row.cold_start === "true";
    if (!endpoints.has(endpoint) || status < 100 || status > 599 ||
        statusClass !== `${Math.floor(status / 100)}xx` || !errors.has(errorCode) ||
        ![true, false, 0, 1, "true", "false"].includes(row.cold_start)) {
      throw new OperationalCheckError("APPLICATION_DIMENSION_OUTSIDE_CATALOG");
    }
    return {
      endpoint,
      identityMatches: semanticRelease === identity.semanticRelease &&
        deployedBuild === identity.deployedBuild && boundaryVersion === identity.boundaryVersion,
      status,
      statusClass,
      errorCode,
      coldStart,
      eventCount: boundedCount(row.event_count),
    };
  });
}

function sanitizeContractCounts(rows) {
  if (!Array.isArray(rows) || rows.length !== 1 || !isRecord(rows[0])) {
    throw new OperationalCheckError("CONTRACT_COUNTS_INVALID");
  }
  const row = rows[0];
  const map = {
    eventCount: "event_count",
    exactKeyCount: "exact_key_count",
    validRequestIdCount: "valid_request_id_count",
    validEndpointCount: "valid_endpoint_count",
    expectedSemanticReleaseCount: "expected_semantic_release_count",
    expectedBuildCount: "expected_build_count",
    expectedBoundaryCount: "expected_boundary_count",
    expectedStageCount: "expected_stage_count",
    validStatusCount: "valid_status_count",
    validStatusClassCount: "valid_status_class_count",
    boundedDurationCount: "bounded_duration_count",
    validErrorCodeCount: "valid_error_code_count",
  };
  const result = {};
  for (const [outputKey, rowKey] of Object.entries(map)) {
    result[outputKey] = boundedCount(row[rowKey]);
  }
  const eventCount = result.eventCount;
  result.complete = Object.entries(result)
    .filter(([key]) => key !== "eventCount" && key !== "complete")
    .every(([, value]) => value === eventCount);
  return result;
}

function sanitizeGatewayAuth(rows) {
  const endpoints = new Set(EXPECTED_ENDPOINTS);
  if (!Array.isArray(rows) || rows.length > 20) throw new OperationalCheckError("GATEWAY_AGGREGATE_INVALID");
  return rows.map((row) => {
    if (!isRecord(row)) throw new OperationalCheckError("GATEWAY_AGGREGATE_INVALID");
    const endpoint = String(row.endpoint);
    const status = boundedCount(row.status, "INVALID_GATEWAY_STATUS");
    if (!endpoints.has(endpoint) || (status !== 401 && status !== 403)) {
      throw new OperationalCheckError("GATEWAY_DIMENSION_OUTSIDE_CATALOG");
    }
    return { endpoint, status, eventCount: boundedCount(row.event_count) };
  });
}

async function checkOwnerMfa(context) {
  const projects = await fetchJson({
    ...context,
    path: "/v1/projects",
    expectedStatuses: [200],
  });
  if (!Array.isArray(projects)) throw new OperationalCheckError("PROJECT_LIST_INVALID");
  const project = projects.find((row) => isRecord(row) && (row.ref === context.projectRef || row.id === context.projectRef));
  const organizationSlug = isRecord(project) ? project.organization_slug : null;
  if (typeof organizationSlug !== "string" || !ORGANIZATION_SLUG_PATTERN.test(organizationSlug)) {
    throw new OperationalCheckError("ORGANIZATION_NOT_RESOLVED");
  }
  const members = await fetchJson({
    ...context,
    path: `/v1/organizations/${encodeURIComponent(organizationSlug)}/members`,
    expectedStatuses: [200],
  });
  if (!Array.isArray(members)) throw new OperationalCheckError("MEMBER_LIST_INVALID");
  // Deliberately access only role_name and mfa_enabled. Names, emails, user IDs,
  // avatars, and all other member fields are neither read nor emitted.
  const owners = members.filter((row) => isRecord(row) && String(row.role_name).toLowerCase() === "owner");
  const enabled = owners.filter((row) => row.mfa_enabled === true).length;
  const disabled = owners.filter((row) => row.mfa_enabled === false).length;
  const unknown = owners.length - enabled - disabled;
  return {
    status: owners.length > 0 && disabled === 0 && unknown === 0 ? "ENABLED" :
      disabled > 0 ? "DISABLED" : "UNKNOWN",
    ownerCount: owners.length,
    enabledOwnerCount: enabled,
    disabledOwnerCount: disabled,
    unknownOwnerCount: unknown,
  };
}

function stripSqlForValidation(sql) {
  return sql
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/--[^\n\r]*/g, " ")
    .replace(/'(?:''|[^'])*'/g, "''");
}

export function validateReadOnlySqlPack(sql) {
  if (typeof sql !== "string" || sql.length === 0 || sql.length > 200_000) {
    throw new OperationalCheckError("SQL_PACK_INVALID");
  }
  const normalized = stripSqlForValidation(sql).replace(/\s+/g, " ").trim();
  if (!/^begin read only\s*;/i.test(normalized) || !/rollback\s*;$/i.test(normalized)) {
    throw new OperationalCheckError("SQL_PACK_TRANSACTION_INVALID");
  }
  if (!sql.includes(SQL_QUERY_BEGIN) || !sql.includes(SQL_QUERY_END) ||
      sql.indexOf(SQL_QUERY_BEGIN) >= sql.indexOf(SQL_QUERY_END)) {
    throw new OperationalCheckError("SQL_PACK_MARKERS_INVALID");
  }
  const forbidden = /\b(insert|update|delete|merge|alter|create|drop|truncate|grant|revoke|copy|call|do|vacuum|analyze|refresh|reindex|cluster|lock)\b/i;
  if (forbidden.test(normalized) || /\bselect\s+\*/i.test(normalized) || /\bfor\s+update\b/i.test(normalized)) {
    throw new OperationalCheckError("SQL_PACK_MUTATION_OR_BROAD_READ");
  }
  const statement = sql.slice(
    sql.indexOf(SQL_QUERY_BEGIN) + SQL_QUERY_BEGIN.length,
    sql.indexOf(SQL_QUERY_END),
  ).trim();
  const statementNormalized = stripSqlForValidation(statement).replace(/\s+/g, " ").trim();
  if (!/^(with|select)\b/i.test(statementNormalized) || forbidden.test(statementNormalized)) {
    throw new OperationalCheckError("SQL_PACK_QUERY_INVALID");
  }
  for (const code of DATABASE_CHECK_CODES) {
    if (!sql.includes(`'${code}'`)) throw new OperationalCheckError("SQL_PACK_CHECK_SET_INCOMPLETE");
  }
  return statement;
}

function sanitizeDatabaseRows(body) {
  const rows = Array.isArray(body) ? body : isRecord(body) && Array.isArray(body.result) ? body.result : null;
  if (rows === null) throw new OperationalCheckError("DATABASE_RESPONSE_INVALID");
  const allowed = new Set(DATABASE_CHECK_CODES);
  const checks = rows.map((row) => {
    if (!isRecord(row) || Object.keys(row).some((key) => key !== "check_code" && key !== "violation_count")) {
      throw new OperationalCheckError("DATABASE_ROW_CONTRACT_INVALID");
    }
    const checkCode = String(row.check_code);
    if (!allowed.has(checkCode)) throw new OperationalCheckError("DATABASE_CHECK_CODE_INVALID");
    return { checkCode, violationCount: boundedCount(row.violation_count) };
  }).sort((left, right) => left.checkCode.localeCompare(right.checkCode));
  if (checks.length !== DATABASE_CHECK_CODES.length || new Set(checks.map((row) => row.checkCode)).size !== checks.length) {
    throw new OperationalCheckError("DATABASE_CHECK_SET_INCOMPLETE");
  }
  return checks;
}

async function runDatabaseChecks(context, sqlPack) {
  const statement = validateReadOnlySqlPack(sqlPack);
  const body = await fetchJson({
    ...context,
    path: `/v1/projects/${context.projectRef}/database/query/read-only`,
    init: {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ query: statement, parameters: [] }),
    },
    expectedStatuses: [200, 201],
  });
  return sanitizeDatabaseRows(body);
}

function sum(rows, predicate) {
  return rows.filter(predicate).reduce((total, row) => total + row.eventCount, 0);
}

function databaseViolation(checks, checkCode) {
  return checks.find((row) => row.checkCode === checkCode)?.violationCount ?? 0;
}

export async function runOperationalCheck({
  projectRef,
  accessToken,
  expectedIdentity = DEFAULT_EXPECTED_IDENTITY,
  windowMinutes = 1440,
  includeDatabase = false,
  databaseSqlPack = null,
  ownerConfigured = false,
  notificationChannelConfigured = false,
  fetchImpl = fetch,
  apiBase = DEFAULT_API_BASE,
  now = () => new Date(),
}) {
  validateProjectRef(projectRef);
  if (typeof accessToken !== "string" || accessToken.trim().length < 8) {
    throw new OperationalCheckError("ACCESS_TOKEN_MISSING");
  }
  const identity = {
    semanticRelease: validateConfigValue(expectedIdentity.semanticRelease, "SEMANTIC_RELEASE_INVALID"),
    deployedBuild: validateConfigValue(expectedIdentity.deployedBuild, "DEPLOYED_BUILD_INVALID"),
    boundaryVersion: validateConfigValue(expectedIdentity.boundaryVersion, "BOUNDARY_VERSION_INVALID"),
    functionVersion: parsePositiveInteger(expectedIdentity.functionVersion, "FUNCTION_VERSION_INVALID", 1_000_000),
  };
  const minutes = parsePositiveInteger(windowMinutes, "WINDOW_INVALID", 1440);
  const end = now();
  if (!(end instanceof Date) || Number.isNaN(end.getTime())) throw new OperationalCheckError("CLOCK_INVALID");
  const start = new Date(end.getTime() - minutes * 60_000);
  const context = {
    projectRef,
    accessToken,
    fetchImpl,
    apiBase,
    windowStart: start.toISOString(),
    windowEnd: end.toISOString(),
  };
  const queries = buildLogQueries(identity);
  const [deploymentBody, applicationRows, contractRows, gatewayRows, ownerMfa] = await Promise.all([
    fetchJson({ ...context, path: `/v1/projects/${projectRef}/functions`, expectedStatuses: [200] }),
    queryLogs(context, queries.applicationAggregate),
    queryLogs(context, queries.contractCounts),
    queryLogs(context, queries.gatewayAuthAggregate),
    checkOwnerMfa(context),
  ]);
  const deployment = sanitizeDeployment(deploymentBody, identity.functionVersion);
  const application = sanitizeApplicationAggregate(applicationRows, identity);
  const contract = sanitizeContractCounts(contractRows);
  const gatewayAuth = sanitizeGatewayAuth(gatewayRows);
  const databaseChecks = includeDatabase
    ? await runDatabaseChecks(context, databaseSqlPack)
    : null;

  const internal5xxCount = sum(application, (row) => row.status >= 500);
  const deadlineFailureCount = sum(application, (row) =>
    row.errorCode === "DEPENDENCY_DEADLINE_EXCEEDED" || row.errorCode === "REQUEST_DEADLINE_EXCEEDED"
  );
  const boundary403Count = sum(application, (row) => row.status === 403);
  const gateway401Count = sum(gatewayAuth, (row) => row.status === 401);
  const gateway403Count = sum(gatewayAuth, (row) => row.status === 403);
  const eventCount = application.reduce((total, row) => total + row.eventCount, 0);
  const identityMismatchCount = sum(application, (row) => !row.identityMatches);
  const blockers = [];
  const reviewFindings = [];

  if (!deployment.matchesExpected) blockers.push("DEPLOYMENT_METADATA_MISMATCH");
  if (!contract.complete || contract.eventCount !== eventCount) blockers.push("STRUCTURED_EVENT_CONTRACT_MISMATCH");
  if (identityMismatchCount > 0) blockers.push("RELEASE_IDENTITY_MISMATCH");
  if (internal5xxCount >= 5) blockers.push("REPEATED_INTERNAL_5XX");
  else if (internal5xxCount > 0) reviewFindings.push("INTERNAL_5XX_PRESENT");
  if (deadlineFailureCount > 0) reviewFindings.push("DEADLINE_FAILURE_PRESENT");
  if (ownerMfa.status !== "ENABLED") blockers.push("OWNER_MFA_NOT_ENABLED");
  if (!ownerConfigured) blockers.push("OPERATIONAL_OWNER_UNASSIGNED");
  if (!notificationChannelConfigured) blockers.push("MANUAL_NOTIFICATION_CHANNEL_UNASSIGNED");
  blockers.push("PRIVACY_DELETION_INTEGRITY_SIGNAL_UNAVAILABLE");

  if (databaseChecks !== null) {
    if (databaseViolation(databaseChecks, "FIT_COMPLETED_FINGERPRINT_INVARIANT") > 0 ||
        databaseViolation(databaseChecks, "ELIGIBILITY_COMPLETED_FINGERPRINT_INVARIANT") > 0 ||
        databaseViolation(databaseChecks, "VERIFIED_FINANCIAL_GRAPH_INVARIANT") > 0) {
      blockers.push("DATABASE_INTEGRITY_INVARIANT_FAILED");
    }
    if (databaseViolation(databaseChecks, "FIT_STALE_BUILDING_GT_15M") > 0 ||
        databaseViolation(databaseChecks, "ELIGIBILITY_STALE_BUILDING_GT_15M") > 0) {
      blockers.push("STALE_BUILDING_PRESENT");
    }
    if (databaseViolation(databaseChecks, "FINANCIAL_DRAFT_GT_72H") > 0) {
      reviewFindings.push("STALE_FINANCIAL_DRAFT_PRESENT");
    }
  } else {
    blockers.push("DATABASE_CHECKS_NOT_RUN");
  }

  const uniqueBlockers = [...new Set(blockers)].sort();
  const uniqueReviewFindings = [...new Set(reviewFindings)].sort();
  return {
    checkerVersion: CHECKER_VERSION,
    window: { minutes, start: context.windowStart, end: context.windowEnd },
    expectedIdentity: identity,
    deployment,
    structuredEventContract: contract,
    operationalCounts: {
      boundaryEventCount: eventCount,
      identityMismatchCount,
      internal5xxCount,
      deadlineFailureCount,
      boundary403Count,
      gateway401Count,
      gateway403Count,
    },
    applicationAggregates: application,
    gatewayAuthAggregates: gatewayAuth,
    database: databaseChecks === null ? { status: "NOT_RUN", checks: [] } : {
      status: "RAN_VIA_SUPABASE_READ_ONLY_ENDPOINT",
      checks: databaseChecks,
    },
    ownerMfa,
    operationsConfiguration: {
      ownerConfigured: ownerConfigured === true,
      notificationChannelConfigured: notificationChannelConfigured === true,
      configurationLocation: "OUT_OF_REPOSITORY_PRIVATE_OPERATIONS_REGISTER",
    },
    privacyDeletionIntegritySignal: "UNAVAILABLE",
    blockers: uniqueBlockers,
    reviewFindings: uniqueReviewFindings,
    verdict: uniqueBlockers.length === 0 ? "PRIVATE_BETA_SAFEGUARDS_PASS" : "PRIVATE_BETA_BLOCKED",
  };
}

export function parseArgs(argv) {
  const options = {
    projectRef: null,
    expectedIdentity: { ...DEFAULT_EXPECTED_IDENTITY },
    windowMinutes: 1440,
    includeDatabase: false,
    databaseQueryFile: resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../supabase/snippets/phase4a2_minimum_beta_invariants.sql",
    ),
    ownerConfigured: false,
    notificationChannelConfigured: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) throw new OperationalCheckError("CLI_ARGUMENT_MISSING");
      return argv[index];
    };
    if (arg === "--project-ref") options.projectRef = next();
    else if (arg === "--expected-semantic-release") options.expectedIdentity.semanticRelease = next();
    else if (arg === "--expected-deployed-build") options.expectedIdentity.deployedBuild = next();
    else if (arg === "--expected-boundary-version") options.expectedIdentity.boundaryVersion = next();
    else if (arg === "--expected-function-version") options.expectedIdentity.functionVersion = next();
    else if (arg === "--window-minutes") options.windowMinutes = next();
    else if (arg === "--include-database") options.includeDatabase = true;
    else if (arg === "--database-query-file") options.databaseQueryFile = resolve(next());
    else if (arg === "--owner-configured") options.ownerConfigured = true;
    else if (arg === "--notification-channel-configured") options.notificationChannelConfigured = true;
    else throw new OperationalCheckError("CLI_ARGUMENT_UNKNOWN");
  }
  if (options.projectRef === null) throw new OperationalCheckError("PROJECT_REF_REQUIRED");
  validateProjectRef(options.projectRef);
  options.windowMinutes = parsePositiveInteger(options.windowMinutes, "WINDOW_INVALID", 1440);
  options.expectedIdentity.semanticRelease = validateConfigValue(
    options.expectedIdentity.semanticRelease,
    "SEMANTIC_RELEASE_INVALID",
  );
  options.expectedIdentity.deployedBuild = validateConfigValue(
    options.expectedIdentity.deployedBuild,
    "DEPLOYED_BUILD_INVALID",
  );
  options.expectedIdentity.boundaryVersion = validateConfigValue(
    options.expectedIdentity.boundaryVersion,
    "BOUNDARY_VERSION_INVALID",
  );
  options.expectedIdentity.functionVersion = parsePositiveInteger(
    options.expectedIdentity.functionVersion,
    "FUNCTION_VERSION_INVALID",
    1_000_000,
  );
  return options;
}

export async function main(argv = process.argv.slice(2)) {
  let accessToken = process.env.SUPABASE_ACCESS_TOKEN ?? "";
  delete process.env.SUPABASE_ACCESS_TOKEN;
  try {
    const options = parseArgs(argv);
    const databaseSqlPack = options.includeDatabase
      ? await readFile(options.databaseQueryFile, "utf8")
      : null;
    const result = await runOperationalCheck({
      projectRef: options.projectRef,
      accessToken,
      expectedIdentity: options.expectedIdentity,
      windowMinutes: options.windowMinutes,
      includeDatabase: options.includeDatabase,
      databaseSqlPack,
      ownerConfigured: options.ownerConfigured,
      notificationChannelConfigured: options.notificationChannelConfigured,
    });
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return result.verdict === "PRIVATE_BETA_SAFEGUARDS_PASS" ? 0 : 2;
  } catch (error) {
    const safe = error instanceof OperationalCheckError ? error : new OperationalCheckError("CHECKER_FAILED_CLOSED");
    process.stdout.write(`${JSON.stringify({
      checkerVersion: CHECKER_VERSION,
      verdict: "CHECKER_ERROR",
      error: safe.code,
      status: safe.status,
    })}\n`);
    return 1;
  } finally {
    accessToken = "";
  }
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) {
  process.exitCode = await main();
}
