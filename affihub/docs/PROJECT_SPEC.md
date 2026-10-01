# POC AI Affiliate & Facebook Automation Platform — Project Spec

Nguồn: master prompt user cung cấp (xem `.claude` instructions). File này lưu lại tóm tắt để tham chiếu khi làm việc trong repo, không thay thế master prompt gốc.

## Mục tiêu

Vertical slice chạy thật end-to-end, Rails backend:

```
Affiliate Source (ACCESSTRADE)
→ Import Product thật
→ Product Library
→ Filter / Score
→ Select Product
→ AI Generate Content (Codex)
→ Human Review → Approve
→ Facebook Page
→ Post Now / Schedule
→ Background Job
→ Publish thật (Meta Graph API)
→ Track Publication Status
```

Không xây full Postiz / full affiliate platform / full AI gateway / full social automation. Chỉ 1 affiliate provider + 1 AI provider + 1 social provider + 1 destination type + 1 workflow.

## Nguyên tắc development

```
REFERENCE FIRST → UNDERSTAND → EXPLAIN → MAP → PORT TO RAILS → VERIFY
```

Không tự thiết kế subsystem lớn khi đã có reference repo tương ứng. Phải đọc source thật, hiểu behavior/lifecycle/error handling/edge case trước khi port. Port **behavior**, không dịch syntax. Tên class/table/module Rails không cần giống reference.

Trước khi code subsystem lớn: viết Porting Note vào `docs/reference-analysis/[subsystem].md` theo template chuẩn (Reference, Implementation, Behavior cần giữ, Không port, Rails mapping, Data flow, State lifecycle, Error handling, Security, License, Implementation plan, Verification).

## Scope POC V1

| Thành phần | Chọn |
|---|---|
| Affiliate | ACCESSTRADE (Shopee products qua source ACCESSTRADE cung cấp) |
| AI | OpenAI Codex (authenticated connection) |
| Social | Facebook |
| Destination | Facebook Page |

KHÔNG làm trong V1: Facebook Group/Profile, TikTok/Instagram/YouTube/LinkedIn/Reddit/Pinterest/Threads, Claude/Gemini/Antigravity, TikTok Shop, Shopee direct integration, multi-provider, full analytics/calendar/inbox, full Postiz feature set, autonomous AI Agent. Có thể chừa extension point, không implement.

## Reference map (bắt buộc dùng đúng theo subsystem)

| Subsystem | Repo | Vai trò |
|---|---|---|
| Social core | `gitroomhq/postiz-app` | Primary reference: SocialConnection, SocialDestination, Content, Media, Publication, scheduling, publishing, provider adapter, status/retry |
| Facebook Page detail | `thenavidm/facebook-mcp` | Meta auth, Page discovery, Page token, publishing, Graph API |
| Meta official docs | developers.facebook.com | Source of truth cho API capability hiện tại, verify trước khi implement — không dùng deprecated API, không browser automation cho FB Page |
| AI auth | `decolua/9router` | OAuth/PKCE/callback/token exchange/refresh, provider abstraction (chỉ implement Codex, nhưng học cách abstract) |
| Affiliate pipeline | `tunguyendg/aff-pipeline` | Primary: ACCESSTRADE ingestion, normalize, filter, scoring, ranking, affiliate links |
| Affiliate secondary | `Duke0503/shopee-aff` | Chỉ dùng khi aff-pipeline thiếu kiến trúc (workers, batch, tracking) |
| Shopee-specific | `bcat95/shopee-aff` | Search/offers/short links/conversions — phải phân loại Official/Unofficial/Reverse-engineered/Deprecated |

Thứ tự ưu tiên khi cần: Social core → Postiz first. Facebook Page → Postiz + facebook-mcp + Meta docs. Codex auth → 9Router + verify behavior hiện tại. Affiliate → aff-pipeline first, fallback Duke0503, rồi bcat95.

## Domain model (chỉ tạo khi có use case trong vertical slice)

- `User`
- `AIConnection` (Codex) — credentials encrypted, không log raw token, không expose ra frontend
- Affiliate Provider/Connection + `Product` (Product Library)
- `SocialConnection` (Facebook, != SocialDestination)
- `SocialDestination` (Facebook Page cụ thể — publication phải reference destination, không reference generic Facebook provider)
- `Content` (lifecycle: Generated → Review → Approved; actions: Preview/Edit/Regenerate/Approve/Reject)
- `Publication` (1 Content + 1 Destination; lifecycle: Draft → Scheduled → Publishing → Published, hoặc → Failed → retry → Publishing)

### Product fields (conceptual)
`affiliate_provider, source_product_id, merchant, title, description, images, price, original_price, discount, category, rating, sold, commission, original_product_url, affiliate_url, raw_source_data, last_synced_at`. Field thiếu → nullable. `original_product_url` != `affiliate_url`, cả hai đều lấy từ provider thật, AI không được generate.

### Publication fields (conceptual)
`content_id, social_destination_id, status, scheduled_at, provider_post_id, published_url, published_at, error_code, error_message, attempt_count, last_attempt_at, provider_metadata`

Published chỉ set sau khi provider xác nhận thành công thật (không phải "job finished = published"). Failure lưu error_code/error_message, tăng attempt_count.

## Kiến trúc publishing

```
Publication → PublisherResolver → MetaGraphPublisher → Meta Graph API
```

`PublisherResolver` chọn publisher theo `destination.provider` + `destination.type`. `MetaGraphPublisher` xử lý: build request, credential, call Graph API, parse response, map provider error, extract provider_post_id.

Publish luôn qua background job (`PublishJob`), không giữ HTTP request chờ social provider. Post Now = enqueue ngay. Schedule = enqueue tại `scheduled_at`.

## AI content generation boundaries

AI nhận product facts thật (title, description, price, original_price, discount, rating, sold, affiliate context, platform=Facebook, tone) → trả hook/caption/CTA/hashtags. Application tự attach `affiliate_url`. AI KHÔNG được: invent product/ID/facts/affiliate URL, đổi affiliate URL, invent price/discount/rating/sold/feature/promotion/commission, execute SQL, đọc raw credentials, log credentials, bypass approval, tự set Publication=Published, fake provider response/success, publish tới destination chưa chọn.

Human review bắt buộc: Generated → Review → Approved → Publication. Regenerate chỉ đổi content, không đổi Product ID/facts/affiliate URL.

## Source of truth

- Affiliate provider = product data + affiliate URL
- Rails DB = application state
- AI = content generation engine (không phải source of truth cho product/price/status)
- User = approval
- Social provider = publication result

## Implementation order (phase, không skip)

1. Reference analysis → `docs/reference-analysis/` + Porting Notes
2. Rails foundation (domain tối thiểu ở trên)
3. Codex auth (9Router ref) — DoD: Rails gửi prompt thật, nhận response thật qua Test Connection UI
4. Affiliate pipeline (aff-pipeline ref) — DoD: product thật trong DB + original_product_url thật + affiliate_url thật
5. AI content (Product → Codex → Content) — DoD: content chỉ dựa facts thật + affiliate URL app attach
6. Facebook Page (Postiz + facebook-mcp + Meta docs) — DoD: connect FB thật, lấy Page thật, sync SocialDestination
7. Publication (Postiz ref) — Post Now rồi Schedule — DoD: post thật xuất hiện trên FB Page, provider result lưu thật, status=Published
8. End-to-end verification toàn chuỗi, không coi xong nếu chỉ từng phần chạy riêng lẻ

Mỗi phase theo quy trình: inspect reference → Porting Note → explain findings → xác định scope → implement → test → verify → mới sang phase tiếp. Reference khác assumption ban đầu → STOP, update Porting Note/plan, không ép code khớp giả định.

## UI tối thiểu

Login, Dashboard (status Codex/ACCESSTRADE/Facebook connected + recent publications), AI Connections, Affiliate Products, Product Detail, Generate Content, Content Review, Social Connections, Facebook Pages, Publication, Publication Status. Không build full Postiz UI.

## Cấm (anti-fake-POC)

Không coi các thứ sau là Done: mock/hard-coded product, fake affiliate URL, mock AI response, hard-coded Page, fake provider_post_id, fake Published status, console.log thay provider request, TODO implementation, stub publisher. Test được dùng mock; Demo DoD phải dùng integration thật. Trước khi copy code từ reference repo: kiểm tra LICENSE, không rõ/không phù hợp → clean-room reimplement.

## POC Definition of Done (34 bước)

Xem đầy đủ trong master prompt gốc §39. Tóm tắt: login → connect Codex → test prompt thật → connect ACCESSTRADE → import/normalize product thật (có original_url + affiliate_url thật) → filter/score → chọn product → Codex generate content → review/edit/regenerate → approve → connect Facebook → discover Pages thật → chọn Page → tạo Publication → Post Now/Schedule → background job → PublisherResolver → MetaGraphPublisher → Facebook thật nhận post → lưu provider_post_id/published_at/metadata thật → status Published (hoặc Failed thật nếu provider fail).
