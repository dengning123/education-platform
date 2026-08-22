export class FitAdapterError extends Error {
  override readonly name = "FitAdapterError";

  constructor(message: string, readonly status = 500, readonly detail?: unknown) {
    super(message);
  }
}

export type QueryValue = string | number | boolean;

export interface FitDatabaseGateway {
  select<T>(table: string, query?: Readonly<Record<string, QueryValue>>): Promise<T[]>;
  insert<T>(table: string, rows: readonly unknown[]): Promise<T[]>;
  rpc<T>(functionName: string, args?: Readonly<Record<string, unknown>>): Promise<T>;
}

export class PostgrestGateway implements FitDatabaseGateway {
  constructor(
    private readonly baseUrl: string,
    private readonly apiKey: string,
    private readonly bearerToken: string = apiKey,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  private async request<T>(
    path: string,
    init: RequestInit,
    query: Readonly<Record<string, QueryValue>> = {},
  ): Promise<T> {
    const url = new URL(`${this.baseUrl.replace(/\/$/, "")}/rest/v1/${path}`);
    for (const [key, value] of Object.entries(query)) url.searchParams.set(key, String(value));
    const response = await this.fetchImpl(url, {
      ...init,
      headers: {
        apikey: this.apiKey,
        authorization: `Bearer ${this.bearerToken}`,
        "content-type": "application/json",
        ...(init.headers ?? {}),
      },
    });
    const text = await response.text();
    const body = text.length === 0 ? null : JSON.parse(text) as unknown;
    if (!response.ok) {
      const message = typeof body === "object" && body !== null && "message" in body
        ? String((body as { message: unknown }).message)
        : `Database request failed with HTTP ${response.status}`;
      throw new FitAdapterError(message, response.status, body);
    }
    return body as T;
  }

  select<T>(table: string, query: Readonly<Record<string, QueryValue>> = {}): Promise<T[]> {
    return this.request<T[]>(table, { method: "GET" }, query);
  }

  insert<T>(table: string, rows: readonly unknown[]): Promise<T[]> {
    if (rows.length === 0) return Promise.resolve([]);
    return this.request<T[]>(table, {
      method: "POST",
      headers: { prefer: "return=representation" },
      body: JSON.stringify(rows),
    }, { select: "*" });
  }

  rpc<T>(functionName: string, args: Readonly<Record<string, unknown>> = {}): Promise<T> {
    return this.request<T>(`rpc/${functionName}`, {
      method: "POST",
      body: JSON.stringify(args),
    });
  }
}

const fitInsertFunctions: Readonly<Record<string, string>> = {
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
  fit_dimension_reasons: "insert_fit_dimension_reason",
};

const generatedIdColumns: Readonly<Record<string, string>> = {
  fit_manifest_items: "manifest_item_id",
  fit_input_domain_states: "input_state_id",
  fit_dimension_results: "dimension_result_id",
  fit_signals: "signal_id",
};

/**
 * Production write gateway. Frozen Migration 012 revoked runtime-table DML
 * from service_role; every write therefore goes through its registered,
 * locking, SECURITY DEFINER composite-insert entry point.
 */
export class FitExecutorPostgrestGateway extends PostgrestGateway {
  override async insert<T>(table: string, rows: readonly unknown[]): Promise<T[]> {
    const functionName = fitInsertFunctions[table];
    if (functionName === undefined) {
      throw new FitAdapterError(`No frozen executor insert entry point for ${table}`, 500);
    }
    const inserted: unknown[] = [];
    for (const value of rows) {
      if (value === null || typeof value !== "object" || Array.isArray(value)) {
        throw new FitAdapterError(`Invalid composite row for ${table}`, 500);
      }
      const row = { ...(value as Record<string, unknown>) };
      const idColumn = generatedIdColumns[table];
      if (idColumn !== undefined && row[idColumn] === undefined) row[idColumn] = crypto.randomUUID();
      await this.rpc(functionName, { p_row: row });
      inserted.push(row);
    }
    return inserted as T[];
  }
}

export type FitEvaluationSnapshot = Readonly<Record<string, readonly Record<string, unknown>[]>>;

function equalFilter(actual: unknown, expected: string): boolean {
  if (actual === null || actual === undefined) return false;
  return String(actual) === expected;
}

/** Read-only, in-memory view over the bounded v016 source projection. */
export class FitSnapshotGateway implements FitDatabaseGateway {
  constructor(private readonly snapshot: FitEvaluationSnapshot) {}

  select<T>(table: string, query: Readonly<Record<string, QueryValue>> = {}): Promise<T[]> {
    const source = this.snapshot[table];
    if (source === undefined) throw new FitAdapterError(`Snapshot does not expose ${table}`, 500);
    let rows = [...source];
    for (const [column, rawFilter] of Object.entries(query)) {
      if (column === "select" || column === "order") continue;
      const filter = String(rawFilter);
      if (filter.startsWith("eq.")) {
        const expected = filter.slice(3);
        rows = rows.filter((row) => equalFilter(row[column], expected));
      } else if (filter === "is.null") {
        rows = rows.filter((row) => row[column] === null || row[column] === undefined);
      } else if (filter.startsWith("in.(") && filter.endsWith(")")) {
        const values = new Set(filter.slice(4, -1).split(",").filter((value) => value.length > 0));
        rows = rows.filter((row) => row[column] !== null && row[column] !== undefined && values.has(String(row[column])));
      } else {
        throw new FitAdapterError(`Snapshot filter is not closed for ${table}.${column}`, 500);
      }
    }
    const order = query.order;
    if (typeof order === "string" && order.length > 0) {
      const columns = order.split(",").map((value) => value.split(".")[0]!).filter((value) => value.length > 0);
      rows.sort((left, right) => {
        for (const column of columns) {
          const comparison = String(left[column] ?? "").localeCompare(String(right[column] ?? ""));
          if (comparison !== 0) return comparison;
        }
        return 0;
      });
    }
    return Promise.resolve(rows as T[]);
  }

  insert<T>(_table: string, _rows: readonly unknown[]): Promise<T[]> {
    throw new FitAdapterError("The Fit source snapshot is read-only", 500);
  }

  rpc<T>(_functionName: string, _args: Readonly<Record<string, unknown>> = {}): Promise<T> {
    throw new FitAdapterError("The Fit source snapshot cannot execute RPCs", 500);
  }
}

export function requireOne<T>(rows: readonly T[], label: string): T {
  if (rows.length !== 1 || rows[0] === undefined) {
    throw new FitAdapterError(`${label} requires exactly one row`, 422, { count: rows.length });
  }
  return rows[0];
}

export function postgresIn(values: readonly string[]): string {
  if (values.length === 0) return "in.()";
  for (const value of values) {
    if (!/^[A-Za-z0-9_.:-]+$/.test(value)) {
      throw new FitAdapterError("Unsafe PostgREST filter value", 400);
    }
  }
  return `in.(${values.join(",")})`;
}
