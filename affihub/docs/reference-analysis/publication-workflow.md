# Porting Note: Facebook Page publication workflow

## Reference

- `gitroomhq/postiz-app` source was inspected at the current repository default branch, including `apps/orchestrator/src/activities/post.activity.ts`, `apps/orchestrator/src/workflows/post-workflows/post.workflow.v1.1.2.ts`, and `libraries/nestjs-libraries/src/database/prisma/posts/posts.service.ts`: [repository](https://github.com/gitroomhq/postiz-app).
- The repository is licensed under GNU AGPL v3. This note records behavior and architectural findings only; no Postiz source is copied into Affihub.
- Meta references: [Pages API](https://developers.facebook.com/docs/pages-api/), [Page Feed reference](https://developers.facebook.com/docs/graph-api/reference/page/feed/), and [permissions](https://developers.facebook.com/docs/permissions/). Meta returned HTTP 429 while these pages were being checked on 2026-10-03, so endpoint permissions and current API-version details still require confirmation in the Meta app/docs before live publication.

## Implementation (what Postiz does)

- `PostsService#startWorkflow` starts a durable Temporal workflow named from the post id. It uses `workflowIdConflictPolicy: 'TERMINATE_EXISTING'`, so a replacement workflow does not race an earlier workflow for the same post.
- `postWorkflowV1.1.2` separates provider publishing from state persistence and user notification. Provider work runs in activities; state transitions go through the posts service/activity layer.
- Provider calls that can create an external post use a single attempt (`maximumAttempts: 1`) with a 30-minute start-to-close timeout and 3-minute heartbeat. A timeout after the publish may have started is treated as ambiguous rather than blindly publishing again. Read-only status checks can retry up to three times.
- Providers with an intermediate/pending result are polled and finalized through later workflow steps. For confirmed success, the workflow saves the provider post id and release URL before notification. If notification or state persistence fails after a confirmed publish, it does not issue another publish call.
- `PostActivity#handleDisconnect` handles disconnected provider integrations as a distinct workflow outcome.

## Rails mapping

- `Publications::CreateOperation` accepts only approved Content and a Page destination owned by the current user.
- `PostNowOperation`, `ScheduleOperation`, and `RetryOperation` claim status transitions with conditional database updates before enqueueing work.
- `PublishJob` claims `scheduled` → `publishing` atomically. A duplicate job that cannot claim the row exits without calling a provider.
- `PublisherResolver` selects the publisher by `(SocialConnection.provider, SocialDestination.destination_type)`.
- `MetaGraphPublisher` sends the Content body and app-owned affiliate URL as one Page message, parses the provider post id, and fetches `permalink_url` after the publish response. A permalink lookup failure does not erase a provider-confirmed publish.
- Affihub persists publication status, attempt count, provider result, error, schedule, and stale-attempt fields on its existing `Publication` model. No additional schema change is required for the Postiz-inspired workflow.

## Not ported

- Temporal workflows, Postiz's provider registry, and its distributed worker setup are not needed for this local POC. Solid Queue plus a database claim implements the same basic separation at current scale.
- Postiz source is AGPL-licensed; Affihub reimplements the workflow behavior and does not copy source code.
- Retry and timeout handling is intentionally conservative: a publish timeout can mean Meta accepted the post while the response was lost. Affihub marks this outcome ambiguous and asks for explicit duplicate-risk confirmation before retrying.

## Data flow / state lifecycle

`draft` → (Post Now or Schedule claims the row) → `scheduled` → (background job claims it) → `publishing` → `published` or `failed`.

An expired `publishing` attempt is ambiguous: the provider may have accepted the post. The UI offers a retry path with duplicate-risk confirmation. A confirmed provider success is persisted with `provider_post_id`, `published_at`, and any available `published_url`; a URL lookup failure leaves the confirmed Published state intact with no URL.

## Error handling

- Structured Meta errors become a failed publication with provider error details and an incremented attempt count.
- Network, parsing, or timeout errors may occur after Meta has accepted the post. They are not treated as proof of failure; stale attempts become ambiguous and require explicit confirmation before another external publish call.
- A failure to retrieve `permalink_url` after Meta returns a post id does not cause another publish attempt.
- Provider resolution errors are explicit; unknown provider/destination pairs do not silently return no publisher.

## Security

- Page access tokens stay in encrypted credential fields and are not rendered or logged.
- The publish destination is a user-owned `SocialDestination`; client-supplied Page IDs are not trusted as authorization.
- Provider errors and logs must not serialize access tokens. Publication views expose status and result metadata, not credentials.

## License

Postiz is GNU AGPL v3. Only workflow behavior and design ideas are summarized here. No Postiz code was copied. Meta documentation links are authoritative references, but returned HTTP 429 during this check; no unverified permissions claim is made here.

## Implementation plan

1. Create a Publication only from approved Content and an owned Facebook Page destination.
2. Use atomic conditional updates for Post Now, Schedule, and Retry claims before enqueueing.
3. Resolve the publisher from the destination provider/type pair and call Meta through the shared configured client.
4. Persist confirmed provider outcomes and keep ambiguous outcomes distinct from confirmed failure.
5. Verify the real Facebook Page publish manually before claiming the end-to-end DoD is complete.

## Verification

- Automated publication workflow specs use WebMock at the HTTP boundary and verify ownership, atomic claims, provider selection, result persistence, and ambiguity handling.
- A live Page post is not yet verified. The full 34-step evidence is tracked in [`docs/verification/dod-evidence.md`](../verification/dod-evidence.md); a real approved affiliate product/content is currently unavailable because the account's Shopee Smartlink campaign is Pending.
- Before release, verify current Meta app mode, granted Page permissions, configured Graph API version, and a real provider-confirmed post. Meta docs returned HTTP 429 on 2026-10-03, so this note does not claim those current settings were independently validated from the docs.
