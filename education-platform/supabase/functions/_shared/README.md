# Shared Edge HTTP boundary

`http-boundary.js` owns the non-semantic HTTP boundary shared by the four Fit
Edge Functions. It generates request IDs, applies exact origin policy, enforces
JSON/body/deadline limits, emits allowlisted operational events, and reduces
all failures to the closed public error catalog.

Deployment requires these environment values:

- `FIT_EDGE_ALLOWED_ORIGINS`: exact comma-separated `http`/`https` origins, or
  `none` while there is no deployed browser client;
- `FIT_EDGE_RELEASE_ID`: reviewed release identifier;
- `FIT_EDGE_BUILD_HASH`: immutable source build identifier.

`FIT_EDGE_MAX_BODY_BYTES` and `FIT_EDGE_DEADLINE_MS` are optional bounded
overrides. Wildcard origins, origin paths, credentials, query strings, and
fragments fail configuration closed.

Run the pure boundary suite with the repository's Node runtime:

```sh
node --test supabase/functions/_shared/http-boundary.test.mjs
```

This module must not import or modify the generated `fit-runtime.js` artifact.
