# NIP-55 Bridge Activity Design

## Current limitation

Diogel currently receives `nostrsigner:` intents in `MainActivity` with `singleTop`. That means the visible Flutter activity is also the owner of the Android activity result for the active external caller.

When a second NIP-55 intent arrives while the first one is being reviewed, `MainActivity` must not call `setResult(...)` and `finish()` to reject it. Doing so would finish the activity that owns the first caller's result and can poison/cancel the active request.

The current implementation therefore protects the active request and drops/defer-rejects the second native intent. This is safe for the first caller but not a complete independent settlement model for concurrent callers.

## Option A — dedicated `Nip55BridgeActivity`

A lightweight `Nip55BridgeActivity` receives every external `nostrsigner:` intent and owns that caller's result. It parses transport fields, assigns a request token, forwards the request to Flutter, then waits for an approval/rejection result for its token.

Questions and answers:

- Multiple instances: yes, Android can create separate bridge activity instances, each with its own caller result. Strict single-flight can still be enforced by Flutter/native coordination.
- Cold Flutter engine: bridge can start/bring forward `MainActivity` and submit payload through a process-level coordinator or method channel once the engine is ready.
- Waiting for approval: bridge needs a native pending-result registry keyed by request token, or a shared plugin/manager that Flutter can call to settle the correct bridge instance.
- Process death: pending calls should fail closed. On restart, bridge should return `RESULT_CANCELED` rather than silently sign or orphan secret state.
- UI style: bridge can be transparent/noDisplay, but visible failure UI may be easier to debug. MVP can be transparent once lifecycle is proven.

Pros:

- Each caller has an independent result owner.
- Busy rejection can be safely returned by the second bridge instance without touching the active request.
- Fits strict single-flight and later queueing.

Cons:

- Requires native lifecycle/state plumbing beyond a simple `FlutterActivity`.
- Needs careful cold-start and process-death handling.

## Option B — native request queue

`MainActivity` or a native manager queues later requests until the active one settles.

Questions and answers:

- Caller wait time: many NIP-55 clients may not tolerate long waits, especially for batch signing.
- Retaining results: each queued caller still needs a distinct activity result owner. Without a bridge activity per caller, the queue cannot safely settle each caller.
- Activity instances: yes, practical queueing still implies bridge activities or another component that can own each result.
- Batch clients: queueing could support batches later, but it adds timeout and cancellation complexity.

Pros:

- Good future UX if clients can wait.
- Could serialize requests through the current approval UI.

Cons:

- Does not avoid the need for independent result owners.
- More complex timeout/cancel semantics.

## Option C — strict single-flight with immediate safe rejection

Only one external NIP-55 request may be reviewed at a time. Later requests receive `RESULT_CANCELED`/busy from their own result owner.

Questions and answers:

- Safe owner: a dedicated bridge activity instance must own and reject the second caller.
- Is bridge still required: yes, if the second caller must be settled without touching the active result.
- Least risky MVP: implement `Nip55BridgeActivity` as result owner, keep Flutter single-flight, and have the bridge return busy when Flutter reports an active request.

Pros:

- Smallest robust concurrency model.
- Avoids queue starvation and stale caller waits.
- Preserves manual approval and private-key boundary.

Cons:

- Later clients must retry when busy.
- Still needs bridge infrastructure.

## Recommendation

Implement a lightweight `Nip55BridgeActivity` as the result owner for each external call. Keep Flutter as the approval/signing coordinator. Start with strict single-flight: if Flutter is busy, the bridge activity returns `RESULT_CANCELED` for its own caller without touching the active request.

Do not route signing or private key access through Kotlin. Native code should only handle transport metadata, request tokens, result ownership, and safe cancellation.

## Lifecycle risks

- Flutter engine cold start delays the bridge result.
- App process death can orphan pending requests unless bridges fail closed.
- Activity recreation must retain request token/result ownership.
- Background auto-lock may happen while a bridge is waiting.
- Some clients may impose their own timeout before Diogel settles.

## Test strategy

- Unit-test native parser/result helpers where possible.
- Instrument emulator flows for two concurrent caller activities.
- Verify the active caller still receives the correct result when a second caller is rejected as busy.
- Verify process kill/background cancellation returns non-OK where possible.
- Keep Dart tests for parser, mapping, signing success/failure, cancel, timeout, and source-hint wording.
