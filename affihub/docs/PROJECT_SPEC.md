# POC AI Affiliate & Facebook Automation Platform — Project Spec

Nguồn: master prompt user cung cấp (xem `.claude` instructions). File này lưu lại tóm tắt để tham chiếu khi làm việc trong repo, không thay thế master prompt gốc.

## Mục tiêu

Vertical slice chạy thật end-to-end, Rails backend:

```
Product facts CSV (Dataminer)
→ pipeline tự filter/rank; ACCESSTRADE tạo affiliate link thật cho mọi dòng đủ điều kiện
→ Product Library
→ Filter / Score
→ User chọn Product trong Product Library
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
| Affiliate provider | ACCESSTRADE (API token, tạo tracking link từ URL sản phẩm có sẵn) |
| Product facts input | CSV do user upload theo schema Dataminer của `tunguyendg/aff-pipeline`; không có automated catalog discovery trong POC |
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
| Affiliate pipeline | `tunguyendg/aff-pipeline` | Primary: Dataminer CSV ingestion, normalize, dedupe, filter, scoring, ranking, ACCESSTRADE affiliate-link batches |
| Affiliate secondary | `Duke0503/shopee-aff` | Chỉ dùng khi aff-pipeline thiếu kiến trúc (workers, batch, tracking) |
| Shopee-specific | `bcat95/shopee-aff` | Search/offers/short links/conversions — phải phân loại Official/Unofficial/Reverse-engineered/Deprecated |

Thứ tự ưu tiên khi cần: Social core → Postiz first. Facebook Page → Postiz + facebook-mcp + Meta docs. Codex auth → 9Router + verify behavior hiện tại. Affiliate → aff-pipeline first, fallback Duke0503, rồi bcat95.

## Domain model (chỉ tạo khi có use case trong vertical slice)

- `User`
- `AIConnection` (Codex) — credentials encrypted, không log raw token, không expose ra frontend
- Affiliate Provider/Connection + `Product` (Product Library)
- `SocialConnection` (Facebook, != SocialDestination)
- `SocialDestination` (Facebook Page cụ thể — publication phải reference destination, không reference generic Facebook provider)
- `Content` (Product has_many Contents; mỗi bản có lifecycle độc lập Generated → Review → Approved/Rejected; actions: Preview/Edit/Regenerate/Approve/Reject; Approved terminal theo từng bản, không khóa Product)
- `Publication` (1 Content + 1 Destination; lifecycle: Draft → Scheduled → Publishing → Published, hoặc → Failed → retry → Publishing)

### Product fields (conceptual)
`user_id, affiliate_provider, source_product_id, merchant, title, description, images, price, original_price, discount, category, rating, sold, is_mall, commission, original_product_url, affiliate_url, raw_source_data, last_synced_at`. CSV không có field nào thì để nullable. `original_product_url` lấy từ CSV; `affiliate_url` lấy từ ACCESSTRADE, AI không được generate. Product Library chỉ truy cập Product thuộc user hiện tại.

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

Human review bắt buộc cho từng Content: Generated → Review → Approved → Publication (hoặc Rejected). Một Product có thể có nhiều Content; Regenerate chỉ đổi bản đang thao tác, không đổi Product ID/facts/affiliate URL. Approved là terminal của bản đó nhưng không ngăn tạo Content mới từ cùng Product.

## Source of truth

- Uploaded Dataminer CSV = product facts supplied to the POC
- ACCESSTRADE = generated affiliate URL; it is not treated as a searchable product catalog
- Rails DB = application state
- AI = content generation engine (không phải source of truth cho product/price/status)
- User = approval
- Social provider = publication result

## Implementation order (phase, không skip)

1. Reference analysis → `docs/reference-analysis/` + Porting Notes
2. Rails foundation (domain tối thiểu ở trên)
3. Codex auth (9Router ref) — DoD: Rails gửi prompt thật, nhận response thật qua Test Connection UI
4. Affiliate pipeline (`aff-pipeline` ref) — DoD: Product facts thật từ CSV trong DB + `original_product_url` từ CSV + `affiliate_url` thật do ACCESSTRADE tạo
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

Danh sách đầy đủ, tự chứa (không còn tham chiếu "master prompt gốc" ngoài repo). Task `07-poc-dashboard-e2e-verification` tasks.md 4.1 ghi Pass/Fail từng bước đúng thứ tự này vào `affihub/docs/verification/dod-evidence.md`.

1. Seed user tồn tại trong DB (`db:seed` đã chạy, credential đọc từ ENV hoặc dev default)
2. Login thành công bằng seed user
3. Dashboard hiển thị đúng trạng thái "chưa connect" trước khi thao tác gì
4. Bấm Connect Codex, hoàn tất OAuth/PKCE thật với `auth.openai.com`
5. `AIConnection` được tạo, trạng thái connected
6. Test Connection gửi prompt thật, nhận response thật qua `chatgpt.com/backend-api/codex/responses`
7. Nhập credential ACCESSTRADE thật, tạo `AffiliateConnection`
8. Upload/import Product facts thật từ Dataminer CSV; pipeline tự filter/rank và ACCESSTRADE tạo affiliate link thật cho mọi dòng đủ điều kiện trong lúc import (POC không có bước user chọn Product trước khi tạo link)
9. Mỗi Product import có `original_product_url` thật
10. Mỗi Product import có `affiliate_url` thật
11. Filter Product theo category/price/rating/discount hoạt động đúng trên data thật
12. Score Product tính đúng theo weighted sum từ `aff-pipeline` đã chốt trong design.md change 03, không lỗi với `sold`/`rating`/`discount` thiếu hoặc bằng 0
13. Sau khi import và tạo affiliate link xong, chọn 1 Product từ Product Library đã filter/score
14. Bấm Generate Content cho Product đó
15. Codex sinh content thật (hook/caption/CTA/hashtags) từ facts thật của Product
16. `affiliate_url` được application tự attach vào Content, không phải AI trả về
17. Content ở trạng thái Review ngay sau khi generate
18. Review nội dung, Edit `body` nếu cần (vẫn giữ nguyên `affiliate_url`/`product_id`)
19. Regenerate nếu cần — `body` ghi đè trên cùng Content, `generation_count` tăng, không tạo Content mới
20. Approve Content, chuyển sang Approved
21. Bấm Connect Facebook, hoàn tất OAuth thật với `facebook.com`
22. `SocialConnection` được tạo, token (long-lived) lưu mã hoá
23. Discover Page thật qua Facebook Graph API
24. Chọn 1 Page, tạo/sync `SocialDestination`
25. Tạo Publication từ Content Approved + SocialDestination đã chọn
26. Bấm Post Now (hoặc Schedule với thời điểm tương lai)
27. Request claim atomic `draft`→`scheduled` thành công, `PublishJob` được enqueue
28. `PublishJob` claim atomic `scheduled`→`publishing` thành công (chỉ 1 job chạy cho 1 Publication)
29. `PublisherResolver` chọn đúng `MetaGraphPublisher` cho provider Facebook
30. `MetaGraphPublisher` gọi Meta Graph API thật, `POST /feed` với `message` = `content.body` + `content.affiliate_url` ghép lại (xem design.md change 06)
31. Bài đăng xuất hiện thật trên Facebook Page (xác nhận bằng mắt/link bài đăng thật)
32. `provider_post_id`/`published_url` (qua `permalink_url`)/`published_at` thật được lưu vào Publication
33. Publication chuyển `status: Published` thật ít nhất 1 lần trong demo chính (Failed thật kèm `error_code`/`error_message` được chấp nhận cho các lần thử phụ/case lỗi provider, nhưng DoD KHÔNG coi là Done nếu demo chính không có ít nhất 1 Publication Published thật)
34. Dashboard hiển thị đúng recent publication vừa tạo (status/thời gian khớp DB)

DoD SHALL chỉ coi Done khi cả 34 bước trên đều Pass thật (không chấp nhận partial/skip).
