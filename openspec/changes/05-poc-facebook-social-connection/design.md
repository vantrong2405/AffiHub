# Design

## Context

Model khung `SocialConnection`/`SocialDestination` đã có từ change `01`. Xem `proposal.md` cho motivation. Reference: `gitroomhq/postiz-app` (pattern SocialConnection/SocialDestination tổng quát) + `thenavidm/facebook-mcp` (chi tiết Meta auth/Page discovery/Page token) + Meta Graph API docs hiện hành (tránh deprecated API — khác với Codex, đây là API chính thức của Meta, không phải reverse-engineered).

## Goals / Non-Goals

**Goals:**
- Connect Facebook + discover Page dùng đúng Meta Graph API chính thức (standard OAuth, không browser automation, không header giả).
- Page token lưu riêng biệt với user token, đúng model Postiz's SocialConnection (user-level) vs SocialDestination (page-level).

**Non-Goals:**
- Không làm Facebook Group/Profile, chỉ Page.
- Không xin permission ngoài phạm vi cần cho discover + publish Page (xem change `06` cho publish permission cụ thể).

## Decisions

### 1. Operation + Client pattern (nhất quán)
`app/clients/meta_graph_client.rb` (PORO: OAuth exchange, `/me/accounts` hoặc endpoint hiện hành để discover Page) + Operation riêng cho connect/discover/sync.

### 1b. Callback architecture — redirect_uri bình thường trên Puma :3000, state lưu trong Rails session (KHÔNG cần listener/thread riêng như Codex)
Khác hẳn Codex: Meta Graph API cho phép `redirect_uri` tự chọn (khai báo trong Facebook Developer App, không bị khoá cứng port như client_id public của Codex CLI) — nên dùng 1 route/controller action BÌNH THƯỜNG trên chính Puma app (`:3000`), round-trip qua session cookie chuẩn của user, không cần thread/port riêng/WEBrick.

**Flow cụ thể:**
```
1. GET /social_connections/connect (action "connect", có current_user)
   -> state = SecureRandom.hex(16)
   -> session[:facebook_oauth_state] = state   (session cookie bình thường của user)
   -> redirect_to meta_graph_client.build_authorize_url(state:, redirect_uri: social_connections_callback_url)

2. Browser consent tại facebook.com -> redirect về
   GET /social_connections/callback?code=...&state=...
   (route/controller THẬT trên Puma, cùng session cookie — KHÔNG phải listener riêng)

3. SocialConnectionsController#callback:
   - so `params[:state]` với `session[:facebook_oauth_state]`; KHÔNG khớp -> reject, không exchange
   - khớp -> xoá `session[:facebook_oauth_state]` NGAY (one-time-use, chống replay callback cũ)
   - gọi `ConnectOperation.call(params: { code:, current_user: })` (mọi Operation kế thừa `MainOperation#initialize(params:)` — xem `affihub/CLAUDE.md` convention task 01/2.6, KHÔNG nhận keyword args riêng) -> `render_operation` set flash + redirect
```
Vì toàn bộ chạy trong 1 request/response cycle bình thường của Rails (không có Thread/port riêng như Codex), không có vấn đề DB connection pool (request Puma tự có connection từ pool như mọi request khác), không cần `callback_result` relay action riêng (action `callback` CHÍNH nó đã có session/flash sẵn, set thẳng được).

Alternative: bắt chước y hệt cơ chế listener/port riêng của Codex. Bị loại — Codex phải làm vậy CHỈ VÌ client_id public của Codex CLI khoá cứng `redirect_uri=http://localhost:1455/...`; Facebook Developer App do chính mình đăng ký, tự chọn redirect_uri bất kỳ (kể cả `http://localhost:3000/social_connections/callback` bình thường) — không có ràng buộc đó, nên dùng cách đơn giản nhất phù hợp (route Rails chuẩn), không bê nguyên pattern phức tạp hơn mức cần thiết.

### 1c. Exchange sang long-lived user token ngay sau OAuth — tránh lặp lại vấn đề "token hết hạn" như Codex
`auth.openai.com`/Codex không phải case riêng — token OAuth thường của Meta (`code` → `access_token` qua `exchange_token`) mặc định là **short-lived** (~1-2 giờ), và nếu dùng trực tiếp token này cho `SocialConnection#access_token` thì sẽ hết hạn rất nhanh, lặp lại đúng lỗ hổng "chưa có expiry/refresh" đã bị phát hiện ở Codex (change 02) — nhưng ở đây còn chưa bị phát hiện cho tới review này.

Quyết định: `ConnectOperation` SHALL gọi thêm 1 bước exchange chuẩn của Meta Graph API NGAY sau khi nhận `access_token` ngắn hạn từ bước exchange code — `GET /oauth/access_token?grant_type=fb_exchange_token&client_id=&client_secret=&fb_exchange_token=<short_lived_token>` — trả về **long-lived user token** (hiệu lực ~60 ngày, theo tài liệu chính thức Meta Graph API, không phải con số tự bịa). Chỉ long-lived token này mới được lưu vào `SocialConnection#access_token`. Page token lấy qua `GET /{page_id}?fields=access_token` (Decision 2) khi dùng long-lived user token làm nguồn sẽ TỰ ĐỘNG thành Page token không hết hạn (hành vi chuẩn của Meta Graph API: Page token dẫn xuất từ long-lived user token không có `expires_in`) — vì vậy KHÔNG cần build thêm cơ chế refresh riêng cho Page token, chỉ cần đảm bảo bước exchange long-lived này luôn chạy.

Alternative: dùng thẳng short-lived token, thêm refresh mechanism riêng sau (giống Codex). Bị loại — Meta Graph API đã có sẵn cơ chế long-lived + Page token non-expiring chính thức, dùng nó rẻ hơn tự xây refresh logic riêng cho use case này (ponytail: dùng native feature trước khi tự viết cơ chế riêng).

### 2. SocialConnection = user-level token, SocialDestination = page-level token (giữ đúng Postiz pattern)
Theo Porting Note từ `gitroomhq/postiz-app`: KHÔNG dùng user token để publish trực tiếp — mỗi Page có access token riêng (về mặt khái niệm, Meta Graph API cho phép lấy token này ngay trong response `/me/accounts` lúc discover). **Nguồn lấy token thật sự dùng trong implementation là `GET /{page_id}?fields=access_token` gọi lại tại thời điểm Sync (Decision 4), KHÔNG phải đọc trực tiếp từ response `/me/accounts` lúc discover** — vì response `/me/accounts` chỉ tồn tại trong bộ nhớ của request discover đó, còn Sync xảy ra ở 1 request SAU (sau khi user chọn Page trên UI), request discover đã kết thúc từ lâu. `/me/accounts` ở bước discover CHỈ dùng để lấy `page_id`+`name` hiển thị danh sách (không giữ token của response đó lại, kể cả tạm trong memory) — `SocialDestination#access_token` luôn lưu giá trị mới nhất lấy fresh lúc Sync, không phải giá trị cũ từ lúc discover.

### 3. Validation Publication→SocialDestination đặt ở model/form layer của Publication (change 06), chỉ chuẩn bị association ở đây
Change này chỉ đảm bảo `SocialDestination` tồn tại đúng, validation thật trên `Publication` sẽ implement ở change `06` (tránh phụ thuộc ngược — change 05 không nên chứa logic của model thuộc change 06).

### 4. Sync SocialDestination không tin `page_id` từ client — bắt buộc đối chiếu với kết quả discover vừa gọi, KHÔNG cache Page token
`DiscoverPagesOperation` lưu kết quả discover gần nhất vào `Rails.cache` theo key gắn với `social_connection.id`, TTL ngắn (vd 10 phút) — nhưng **CHỈ lưu `page_id` + `name` (metadata không nhạy cảm)**, KHÔNG lưu Page access token vào cache. `SyncDestinationOperation` SHALL đọc lại danh sách đã cache đó để verify `page_id` nằm trong danh sách (ownership check), sau đó **gọi lại Meta Graph API** (`GET /{page_id}?fields=access_token`, dùng `SocialConnection#access_token` của user) để lấy Page token thật tại thời điểm sync, rồi mã hoá lưu thẳng vào `SocialDestination#access_token` — token không bao giờ đi qua cache dưới dạng plaintext.

**Sửa so với bản thiết kế trước (lỗ hổng bảo mật đã bị phát hiện qua review):** bản trước cache nguyên cả Page token vào `Rails.cache`. Ở `production.rb`, `cache_store = :solid_cache_store` — **Solid Cache lưu DB thật** (bảng `solid_cache_entries`), nghĩa là Page token sẽ nằm plaintext trong 1 bảng DB không được Active Record Encryption bảo vệ, phá vỡ rule "credential mã hoá tại rest" ngay cả khi `SocialDestination#access_token` ở bảng chính vẫn mã hoá đúng. Fix: không bao giờ cache raw token, chỉ cache định danh không nhạy cảm (`page_id`/`name`) dùng cho ownership check, token luôn lấy fresh từ Meta API ngay lúc cần rồi mã hoá lưu đích danh.

Alternative: mã hoá payload cache bằng 1 encryption service riêng trước khi lưu. Bị loại — thêm 1 cơ chế mã hoá/giải mã riêng ngoài `ActiveRecord::Encryption` đã có, chỉ để tránh 1 API call, không đáng so với rủi ro vận hành sai (quên mã hoá ở 1 chỗ cache mới sau này).

## Risks / Trade-offs

- [App chưa qua Meta App Review có thể giới hạn permission thật (vd `pages_manage_posts`) chỉ hoạt động với test user/test Page] → Mitigation: dùng Facebook Developer test app + test Page thuộc chính user phát triển cho giai đoạn POC, ghi rõ giới hạn trong Porting Note.
- [Meta Graph API version có thể bị deprecate theo chu kỳ] → Mitigation: verify version API hiện hành tại thời điểm viết Porting Note, không hard-code version cũ từ tài liệu Postiz có thể đã lỗi thời.

## Migration Plan

Không cần migration mới trừ khi Porting Note phát hiện field thiếu (vd Page category, page access token expiry).
