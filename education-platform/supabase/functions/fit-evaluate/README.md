# Fit evaluation API

`POST /functions/v1/fit-evaluate` accepts the closed request contract exported
by `@education-platform/fit-engine-adapter`. The Supabase gateway verifies the
JWT and the function independently confirms ownership of the frozen profile
before it uses the service role for registry resolution and controlled Fit
assembly.

The endpoint returns six categorical dimension results and the database
fingerprints. It does not return or compute a score, weight, ranking,
probability, recommendation, Eligibility result, or Competitiveness result.

Build the checked-in deployment artifact before serving or deploying:

```sh
cd packages/fit-engine-adapter
pnpm install
pnpm bundle:edge
```

The current v0.1 endpoint supports already comparable Financial source facts,
including the Migration 014 amount-plus-`billing_basis` witness pair. If a
comparison requires an evaluation-scoped Financial normalization, the endpoint
returns a closed `422` response. Creating, independently reviewing, verifying,
and resuming such an artifact is a separate workflow and must not be simulated
by the service role.

Local integration coverage runs against a disposable Supabase stack:

```sh
cd packages/fit-engine-adapter
pnpm test:integration:local
FIT_INTEGRATION_DIRECT_FINANCIAL=1 pnpm test:integration:local
```

No remote deployment is implied by the checked-in function. Before deployment,
the target Supabase project must be explicitly authenticated and linked, its
migration history must be verified through `016`, and both integration modes
must be rerun against the release candidate.
