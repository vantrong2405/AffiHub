# Porting Note: Facebook Page publication workflow

## References and license

- `gitroomhq/postiz-app` is licensed under GNU AGPL v3 or later. Its backend demonstrates provider-specific integrations behind an application-level publishing workflow; no source code is copied. [Repository](https://github.com/gitroomhq/postiz-app)
- `thenavidm/facebook-mcp` documents official Facebook Page posting and the use of Page access tokens; it is MIT licensed. It is a secondary implementation reference only. [Repository](https://github.com/thenavidm/facebook-mcp)
- Meta official references: [Pages API](https://developers.facebook.com/docs/pages-api), [Graph API](https://developers.facebook.com/docs/graph-api). Meta's docs host returned HTTP 429 during this review, so verify permissions/version in the developer app before the live publish gate.

## Findings applied

- Publish a Page text post through the configured Graph API `/{page-id}/feed` endpoint using the destination's Page token.
- Fetch `permalink_url` only after the publish endpoint returns a post id. A permalink lookup failure must not erase provider-confirmed publish success.
- Keep provider transport in `MetaGraphClient`; resolve a publisher from the pair `(SocialConnection.provider, SocialDestination.destination_type)`.
- Use a background `PublishJob`, with an atomic `scheduled`→`publishing` claim, to avoid duplicate jobs from double-clicks.
- Persist Published only after a structured success response; distinguish structured Meta errors from network/parser exceptions. The latter are ambiguous and need duplicate-risk confirmation before retry.
- The local schema already contains `Publication` status, attempt count, provider result, error, schedule, and stale-attempt fields. No extra migration is needed.

The inspected Postiz source (`PostsService#startWorkflow`, `PostActivity#changeState`, and `postWorkflowV1.1.2`) terminates an existing workflow before starting a replacement and routes provider work through a durable Temporal workflow. The workflow separates provider execution from state persistence and has explicit handling for ambiguous publish timeouts. Affihub keeps the same boundaries at POC scale with Solid Queue + an atomic database claim; it does not port Temporal or Postiz code.

## Implementation mapping

- `Publications::CreateOperation` accepts only approved Content and a Page destination owned by the user.
- `PostNowOperation`, `ScheduleOperation`, and `RetryOperation` claim status changes inside user-scoped SQL updates before enqueueing.
- `MetaGraphPublisher` joins Content body and app-owned affiliate URL, parses the Meta post id, fetches the permalink, and returns a typed result.
- `PublishJob` atomically claims scheduled work and records one complete result update. Unexpected errors are logged without tokens and marked `internal_error`.

## Verification limits

Provider HTTP is stubbed at the network boundary in automated tests. A live post, Page permissions, app mode, and real `provider_post_id` remain manual requirements; this note does not claim live publication success.
