# NIP-55 batch and single-flight decision

Date: 2026-05-03

## Decision

Android Diogel deliberately uses **strict single-flight** handling for interactive NIP-55 requests.

Only one external NIP-55 request may be under review, waiting for unlock, or signing at a time. If another native intent arrives while one request is active, Diogel rejects the second request as busy through that second request's own bridge token.

This is the chosen WP10 behavior instead of true batch/queue support.

## Why not true batching yet

NIP-55 says signers must answer multiple permissions with an array of results when clients send multiple intents without awaiting / use ids. That is useful, but implementing it safely in Diogel needs more than a response-shape change:

- every bridge caller needs independent result ownership;
- every approval card needs deterministic mapping back to its caller token and external `id`;
- unlock/resume, timeout, reject, browser callback, and clipboard behavior must all preserve per-request ownership;
- queued sensitive decrypt requests need explicit user review and cancellation semantics;
- clients may not tolerate long queued waits.

A rushed queue would risk poisoning the active caller's result, signing the wrong request, or returning the wrong `id`. For signer software, those are worse than returning a deterministic busy error.

## Current contract

- Sequential requests are supported.
- Result extras preserve the external NIP-55 `id` when supplied.
- A second concurrent request is rejected with:

```text
Diogel is already reviewing another NIP-55 request
```

- Busy rejection must not complete, cancel, or otherwise poison the first request.
- ContentProvider/background calls fail closed while an interactive request is active.
- Browser flows follow the same single-flight rule and still cannot create remembered app grants.

## Future path

If full batch support is implemented later, prefer a bridge-owned queue with per-request ownership, not a shared global completion slot. The future response shape should include a `results` JSON array only when Diogel actually accepts and tracks multiple requests as one batch.

Until then, Diogel should not claim true NIP-55 batch support; it claims deterministic single-flight with safe busy rejection.
