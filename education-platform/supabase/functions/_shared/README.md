# Shared Edge HTTP boundary

`http-boundary.js` owns the non-semantic HTTP boundary shared by the four Fit
Edge Functions. It generates request IDs, applies exact origin policy, enforces
JSON/body limits, emits allowlisted operational events, and reduces
all failures to the closed public error catalog. It also supplies an
abort-aware dependency `fetch` to the entrypoints, without owning any Fit,
Eligibility, or Financial state-machine semantics.

Deployment requires these environment values:

- `FIT_EDGE_ALLOWED_ORIGINS`: exact comma-separated `http`/`https` origins, or
  `none` while there is no deployed browser client;
- `FIT_EDGE_SEMANTIC_RELEASE`: reviewed Fit semantic release identifier;
- `FIT_EDGE_DEPLOYED_BUILD`: immutable deployed source build identifier.

The boundary version is code-owned as `fit-edge-http-v1`; it is not a release
or deployment setting. Keeping all three values distinct makes an operational
event unambiguous.

`FIT_EDGE_MAX_BODY_BYTES`, `FIT_EDGE_REQUEST_DEADLINE_MS`, and
`FIT_EDGE_DEPENDENCY_DEADLINE_MS` are optional bounded overrides. Defaults are
65,536 bytes, 50 seconds, and 10 seconds respectively. Wildcard origins,
origin paths, credentials, query strings, and fragments fail configuration
closed.

Deadlines are cooperative and are propagated into the actual gateway `fetch`.
The boundary does not race the whole application handler and return while
uncancelled database work continues. A dependency timeout aborts its network
request; callers must still treat network-level commit ambiguity according to
the existing database idempotency and finalization contracts.

Run the pure boundary suite with the repository's Node runtime:

```sh
node --test supabase/functions/_shared/http-boundary.test.mjs
```

This module must not import or modify the generated `fit-runtime.js` artifact.
