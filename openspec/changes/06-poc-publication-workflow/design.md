# Design

## Context

Model khung `Publication` đã có từ change `01`. Content Approved tồn tại từ change `04`. `SocialDestination` + `MetaGraphClient` (connect/discover) tồn tại từ change `05`. Xem `proposal.md` cho motivation. Reference: phần publishing/scheduling/retry/status của `gitroomhq/postiz-app`, đối chiếu Meta Graph API docs cho endpoint publish lên Page.

## Goals / Non-Goals

**Goals:**
- Publish thật qua `MetaGraphClient` đã có (change 05), chỉ thêm method publish post, không viết client Meta thứ hai.
- Published chỉ set sau khi parse response provider thành công thật (anti-fake-POC rule cứng).
- Post Now/Schedule đều qua Solid Queue, không block HTTP request.

**Non-Goals:**
- Không làm destination type khác ngoài Facebook Page.
- Không làm calendar/bulk scheduling UI phức tạp — chỉ 1 Publication tại 1 thời điểm.

## Decisions

### 1. PublisherResolver là PORO map đơn giản, contract tường minh
`app/publishers/publisher_resolver.rb`, interface công khai duy nhất: `PublisherResolver.resolve(destination) -> Publisher class` (classmethod, không phải instance). Implementation: `REGISTRY = { ["facebook", "page"] => MetaGraphPublisher }.freeze`, `resolve` tra `REGISTRY.fetch([destination.provider, destination.type])`. Không dùng STI/registry gem vì chỉ 1 entry thật trong scope — giữ extension point (thêm entry sau, chỉ cần thêm 1 dòng vào `REGISTRY`) nhưng không build framework thừa.

**Hành vi khi `(provider, type)` không có trong `REGISTRY`** (combo lạ — không nên xảy ra trong scope POC vì chỉ có Facebook Page, nhưng `SocialDestination` schema về lý thuyết cho phép giá trị khác): `resolve` SHALL raise lỗi rõ ràng (`KeyError` tự nhiên từ `Hash#fetch`, không nuốt/trả `nil` im lặng) — để `PublishJob` fail loudly và rõ ràng thay vì `NoMethodError` mơ hồ khi gọi `nil.new`. `PublishJob`'s `rescue StandardError` (Decision 7) đã bắt cả `KeyError` này, set Publication Failed với `error_code: "internal_error"` đúng theo chủ đích.

**Contract mà mọi Publisher class trả về từ `resolve` phải tuân theo** (đã nói ở Decision 2, nhắc lại ở đây cho rõ vì đây là nơi quyết định "cái gì được coi là 1 Publisher hợp lệ"): instance method `#publish(publication) -> Result` (`Result.success(provider_post_id:, published_url:, published_at:)` hoặc `Result.failure(error_code:, error_message:)`), không raise exception cho lỗi provider thông thường (chỉ raise cho bug/lỗi hạ tầng thật — những cái đó rơi vào `rescue StandardError` ở `PublishJob`).

### 2. MetaGraphPublisher nhận object kết quả rõ ràng, không tự suy luận trạng thái từ "job không raise"
**Ghép `message` gửi Facebook từ `content.body` + `content.affiliate_url`** (2 cột riêng trên `Content` — xem change 04 Decision 4): `message = "#{content.body}\n\n#{content.affiliate_url}"`. `content.body` không tự chứa affiliate_url (application attach riêng, AI không được tự chèn — change 04 Decision "AI không invent URL"), nên `MetaGraphPublisher` SHALL tự nối affiliate_url vào cuối `message` trước khi gọi `meta_graph_client.publish_post` — thiếu bước này bài đăng thật lên Facebook sẽ không có link affiliate.

`MetaGraphPublisher#publish(publication)` trả về object (`Result.success(provider_post_id:, published_url:, published_at:)` hoặc `Result.failure(error_code:, error_message:)`). `PublishJob` dùng object này để set Published/Failed — không bao giờ set Published chỉ vì job chạy hết không exception.

**Contract cụ thể (chốt rõ để implementation không tự đoán):**
- `Result` là `Data.define(:success, :provider_post_id, :published_url, :published_at, :error_code, :error_message)` (Ruby 3.3 có sẵn `Data.define`, không cần gem), `Result.success(...)`/`Result.failure(...)` là 2 classmethod tiện lợi set field tương ứng, field còn lại `nil`.
- **Mapping lỗi Meta → `error_code`/`error_message`**: parse response lỗi JSON của Graph API theo format chuẩn `{"error": {"message":, "type":, "code":, "fbtrace_id":}}` — `error_code = body.dig("error", "code")&.to_s`, `error_message = body.dig("error", "message")`. Response không parse được (không đúng JSON, hoặc không có field `error`) → coi như exception tầng dưới (rơi vào `rescue StandardError` của `PublishJob`, `error_code: "internal_error"` theo Decision 7, KHÔNG cố gắng suy đoán field).
- **`provider_metadata`**: `Hash` lưu nguyên `fbtrace_id` (hỗ trợ debug với Meta support sau này) + `permalink_fetch_failed: true/false` (set bởi Decision 5 khi bước lấy permalink_url lỗi) — không lưu toàn bộ response thô (tránh phình DB không cần thiết), chỉ các field có giá trị debug thật.
- **1 UPDATE duy nhất, không cần transaction DB riêng**: `publication.update!(status:, provider_post_id:, published_url:, published_at:, error_code:, error_message:, provider_metadata:, attempt_count:)` set TẤT CẢ field liên quan trong 1 lời gọi `update!` — Postgres ghi 1 câu UPDATE là atomic, không có rủi ro "ghi `published` thành công nhưng crash giữa các field" (lo ngại này chỉ có thật nếu code tách thành nhiều `.save`/`update_column` riêng lẻ cho từng field — task implementation SHALL không làm vậy).

### 3. PublishJob dùng Solid Queue sẵn có, Schedule dùng `set(wait_until:)`
`PublishJob.perform_later(publication)` cho Post Now; `PublishJob.set(wait_until: publication.scheduled_at).perform_later(publication)` cho Schedule. Không cần thêm gem lập lịch khác — Solid Queue đã có sẵn trong Gemfile.

### 4. Validation Publication→SocialDestination + ownership đặt trong Form/model Publication (hoàn thiện phần chuẩn bị từ change 05)
`app/forms/publications/create_form.rb` validate `social_destination_id` present trước khi gọi Operation tạo Publication. Đồng thời validate ownership 2 chiều: `content.user_id == current_user.id` (Content có `belongs_to :user` từ change 01, set ở `generate_operation` change 04) và `social_destination.social_connection.user_id == current_user.id` (chain đã có từ change 05) — chặn trường hợp request gửi `content_id`/`social_destination_id` không thuộc `current_user` (vd `content_id` của user khác + `social_destination_id` của user hiện tại → tạo Publication cross-user). Dù POC hiện chỉ có 1 user thật, đây là defense-in-depth rẻ (tái dùng association đã có sẵn, không thêm bảng/cột mới ngoài `Content#user_id` đã thêm ở change 01), nhất quán với cách đã chặn ownership ở change 05 (Sync SocialDestination).

### 5. published_url lấy qua GET permalink_url, không tự dựng URL thủ công
`POST /{page-id}/feed` của Meta Graph API chỉ trả về `{"id": "<page_id>_<post_id>"}`, không có field URL. Tự dựng URL theo pattern `facebook.com/<id>` là suy đoán không đáng tin (pattern có thể đổi, không phải field chính thức). Quyết định: `MetaGraphPublisher` sau khi `POST /feed` thành công, gọi tiếp `GET /{id}?fields=permalink_url` (field chính thức của Graph API cho post object) để lấy `published_url`. Nếu bước GET này lỗi, vẫn coi Publication là Published (bài đã đăng thật — đây là sự thật không đổi dù lấy URL phụ trợ thất bại), lưu `published_url = nil` tạm, ghi lý do vào `provider_metadata`.

Alternative: coi Publication Failed nếu không lấy được permalink_url. Bị loại — vi phạm trực tiếp rule "Published chỉ set khi provider xác nhận thật": bài đã đăng thật là sự thật đã xảy ra ở Facebook, không nên downgrade thành Failed chỉ vì 1 API phụ trợ (lấy URL) lỗi.

### 6. State transition table tường minh + idempotency guard trong PublishJob
Bảng chuyển trạng thái chính xác (khớp đúng field `status` enum đã có từ change 01: draft/scheduled/publishing/published/failed):

```
Tạo Publication                  -> draft
Post Now (user bấm)              -> draft -> scheduled   (ngay lập tức, trước khi enqueue)
                                     enqueue PublishJob ngay
Schedule (user chọn scheduled_at)-> draft -> scheduled   (set scheduled_at)
                                     enqueue PublishJob với wait_until: scheduled_at
PublishJob bắt đầu chạy           -> scheduled -> publishing (CHỈ claim path này, xem guard dưới)
PublishJob publish thành công     -> publishing -> published
PublishJob publish thất bại       -> publishing -> failed
Retry (user bấm trên Failed)      -> failed -> scheduled (ngay lúc bấm, TRƯỚC khi enqueue — UI phản ánh ngay)
                                     enqueue PublishJob mới
PublishJob (sau retry) bắt đầu    -> scheduled -> publishing (CÙNG claim path, không phải path riêng)
PublishJob (sau retry) thành công -> publishing -> published
PublishJob (sau retry) thất bại   -> publishing -> failed (attempt_count += 1)
```

**Sửa so với bản thiết kế trước (bug đã bị phát hiện qua review):** Retry trước đây chuyển `failed -> publishing` trực tiếp ở Controller, trong khi `PublishJob` chỉ claim được từ `scheduled`. Hệ quả: sau Retry, Publication có status `publishing` (không phải `scheduled`), nên khi job chạy, `update_all(status: "publishing") WHERE status = "scheduled"` khớp 0 row → job return ngay, KHÔNG BAO GIỜ publish lại — Retry bị gãy chắc chắn, không phải tình huống hiếm. Fix: Retry chuyển `failed -> scheduled` (giống hệt Post Now/Schedule), để **chỉ có đúng 1 claim path duy nhất trong toàn hệ thống** (`scheduled -> publishing`, trong `PublishJob`) — không có path thứ hai (`failed -> publishing`) chạy song song logic claim khác nhau.

**Guard bắt buộc đầu `PublishJob#perform` — chỉ CLAIM được từ đúng 1 trạng thái nguồn, không bao giờ coi `publishing` là trạng thái "được phép tiếp tục publish":**

```ruby
claimed = Publication.where(id: publication.id, status: "scheduled")
                     .update_all(status: "publishing", updated_at: Time.current)
return if claimed.zero? # job khác đã claim trước (status không còn "scheduled" nữa), hoặc publication
                         # đang ở "published"/"failed"/"publishing"/"draft" vì lý do khác — KHÔNG publish
```

Đây là điểm mấu chốt sửa so với bản thiết kế trước: **guard KHÔNG được coi `status == "publishing"` là điều kiện đủ để job tiếp tục publish** — nếu coi vậy, 2 job cùng đọc thấy `publishing` (vd job A vừa set xong, job B đọc ngay sau) sẽ cùng gọi Meta Graph API, tạo duplicate post thật trên Facebook (đúng lỗ hổng đã bị chỉ ra). Thay vào đó:
- Chỉ job nào **tự thực hiện thành công** phép `update_all(status: "publishing")` với điều kiện `WHERE status = "scheduled"` (tức chính job đó là job chuyển `scheduled → publishing`, xác nhận qua số row bị ảnh hưởng > 0) mới được phép gọi `MetaGraphPublisher`.
- Bất kỳ lời gọi `PublishJob#perform` nào khác (duplicate enqueue, Solid Queue retry hạ tầng, hay publication đã `published`/`failed`/đang `publishing` do job khác giữ) đều nhận `claimed.zero?` → return ngay, không gọi Meta Graph API, log skip.
- Vì `update_all` ở Postgres chạy atomic trong 1 câu UPDATE (row-level lock ngầm), 2 job chạy đồng thời trên cùng 1 Publication chỉ có đúng 1 job claim được, job còn lại chắc chắn nhận `claimed.zero? == true`.

**Double-click Post Now / Retry cũng dùng cùng kỹ thuật claim atomic — cả hai đều claim về `scheduled`, không phải `publishing`:**
- Post Now: `Publication.where(id:, status: "draft").update_all(status: "scheduled")` — trả 0 row thì lời gọi thứ hai (double-click) biết Publication đã được chuyển rồi, không enqueue thêm `PublishJob` thứ hai.
- Retry: `Publication.where(id:, status: "failed").update_all(status: "scheduled")` — trả 0 row thì không enqueue thêm job, tránh double-click Retry enqueue 2 job cho cùng 1 Publication. (Không chuyển thẳng sang `publishing` — xem sửa bug claim path ở trên.)

**Claim + enqueue SHALL nằm trong Operation (`PostNowOperation`/`ScheduleOperation`/`RetryOperation`), KHÔNG được đặt thẳng trong Controller action** (sửa so với bản thiết kế trước — bị phát hiện qua review là vi phạm trực tiếp convention HMVC đã chốt ở change 01 Decision 4/5 và `affihub/CLAUDE.md`: "Controller stays thin... never inspects or mutates a model directly"; `update_all` là mutate Model, không được gọi thẳng trong Controller). Controller action chỉ `operator = XxxOperation.call(params:)` rồi `render_operation` — giống mọi command action khác trong vertical slice, không phải ngoại lệ.

**Claim (`update_all`) và `perform_later`/`set(wait_until:).perform_later` SHALL nằm trong cùng 1 `ActiveRecord::Base.transaction`**, bên trong `#call` của Operation tương ứng (cả 3: `PostNowOperation`/`ScheduleOperation`/`RetryOperation`): Solid Queue tự lưu job vào bảng Postgres riêng (cùng DB với `Publication`), nên bọc chung transaction đảm bảo claim và enqueue cùng thành công hoặc cùng rollback — tránh trường hợp claim đổi `status` thành công nhưng `perform_later` lỗi (vd exception hạ tầng hiếm) khiến Publication kẹt ở `scheduled` mãi mãi mà không có job nào chạy (không rơi vào được guard stale-`publishing` ở Decision 7 vì chưa từng vào `publishing`).

**Giới hạn đã biết (POC-scale, không sửa thêm)**: transaction trên chỉ đảm bảo atomicity khi Solid Queue dùng CHUNG database với `Publication` (đúng với cấu hình `development`/`test` hiện tại, `config/database.yml` chỉ có 1 database mỗi env). Cấu hình `production` mẫu trong `config/database.yml` tách `queue:` thành database riêng (`affihub_production_queue`) — nếu deploy thật với cấu hình tách DB đó, transaction này KHÔNG còn bao trọn 2 bước (claim và enqueue ghi vào 2 DB khác nhau, Postgres không hỗ trợ transaction xuyên DB). POC không deploy production nên chấp nhận giới hạn này; nếu sau này cần production thật, phải đổi sang saga/outbox pattern cho 2 bước này — ngoài scope POC.

### 7. Publication stuck ở `publishing` vĩnh viễn (process chết giữa chừng) — recovery qua `last_attempt_at` stale timeout
Chỉ claim atomic (Decision 6) không đủ: nếu process chạy `PublishJob` chết SAU khi claim `scheduled -> publishing` nhưng TRƯỚC khi publish xong (hoặc trước khi lưu kết quả), Publication kẹt vĩnh viễn ở `publishing` — không job nào claim lại được (claim chỉ nhận từ `scheduled`), và Retry chỉ cho phép từ `failed`.

Xử lý theo 2 lớp:
1. **Lớp thường (exception trong Ruby, job vẫn chạy được tới `rescue`)**: `PublishJob#perform` bọc TOÀN BỘ lời gọi `MetaGraphPublisher#publish` trong `begin/rescue StandardError` — bất kỳ exception nào (không chỉ lỗi mạng) đều set Publication `publishing -> failed`, lưu `error_message` từ exception, tăng `attempt_count`. **Chốt dứt điểm: `rescue` NUỐT lỗi (không re-raise)** — job kết thúc "thành công" theo góc nhìn của Solid Queue/ActiveJob sau khi đã ghi `failed` vào Publication. Đây mở rộng Requirement "Published chỉ set khi provider xác nhận thật" (trước chỉ nói lỗi mạng) sang MỌI exception trong quá trình publish.

Lý do không re-raise: hệ thống đã có đúng 1 cơ chế retry tường minh, do user chủ động bấm (Decision 6+7, qua claim atomic `failed`/`publishing-stale` → `scheduled`). Nếu để exception re-raise, Solid Queue sẽ tự kích hoạt retry hạ tầng của riêng nó (theo `retry_on`/default backoff) chạy song song với cơ chế Retry của ứng dụng — 2 cơ chế retry độc lập dễ dẫn tới publish nhiều lần ngoài kiểm soát, hoặc Publication hiển thị `failed` (theo app) trong khi Solid Queue âm thầm tự retry job đã failed đó ở background (user không thấy, không chủ động được). Alternative (re-raise để Solid Queue retry tự động): bị loại — mất kiểm soát UI/attempt_count, vi phạm chủ đích "user chủ động quyết định khi nào retry" đã chốt ở Risk "rate-limit khi retry liên tục".

**Nuốt lỗi KHÔNG đồng nghĩa với mất thông tin debug — log bắt buộc trước khi nuốt**: `rescue StandardError` ở đây bắt MỌI exception, kể cả bug code thật (không chỉ lỗi mạng/provider), nên trước khi set Publication Failed, `PublishJob#perform` SHALL `Rails.logger.error` đủ thông tin để debug sau này mà không cần tái hiện lỗi:
- `publication.id`
- exception class (`error.class.name`)
- exception message (`error.message`)
- full backtrace (`error.backtrace.join("\n")`)
- `publication.social_destination.page_id` nếu đã có (biết đang publish lên Page nào lúc lỗi)

Không log đủ các field này thì production chỉ thấy `error_code: "internal_error"` + `error_message` ngắn trong DB, không đủ để debug bug code thật (khác với lỗi provider rõ ràng đã có `error_code`/`error_message` thật từ Meta).

**Convention `error_code` khi lỗi không có response Meta để parse**: `error_code` chỉ có ý nghĩa thật khi Meta Graph API trả về 1 response lỗi có cấu trúc (`error.type`/`error.code` trong JSON) — `MetaGraphPublisher` parse field đó khi `POST /feed` trả lỗi HTTP có body. Khi lỗi KHÔNG đến từ response Meta (exception Ruby bất kỳ bắt ở lớp `rescue` trên — network timeout, lỗi parse, bug) thì không có error code thật để lưu; set `error_code = "internal_error"` (sentinel string cố định) để field này luôn có giá trị nhất quán (UI/log không cần xử lý nil riêng), và để phân biệt rõ với error_code thật từ Meta khi cần debug sau này.
2. **Lớp hiếm (process bị kill cứng — SIGKILL/crash máy — không kịp chạy `rescue` nào)**: không có `rescue` Ruby nào chạy được, nên lớp 1 không cứu được. Giải pháp: `last_attempt_at` (field đã có sẵn trong `Publication` từ domain model gốc) được set NGAY lúc claim thành công (`scheduled -> publishing`). UI nút Retry hiển thị không chỉ cho status `failed`, mà còn cho status `publishing` khi `last_attempt_at` cũ hơn ngưỡng stale. Retry trên Publication `publishing` stale dùng CÙNG claim atomic: `Publication.where(id:, status: "publishing").where("last_attempt_at < ?", Publication::STALE_PUBLISHING_AFTER.ago).update_all(status: "scheduled")` — vẫn qua đúng 1 claim path (`scheduled -> publishing` ở job), không thêm path riêng.

**Ngưỡng stale là 1 hằng số duy nhất, không rải rác giá trị `10.minutes` ở nhiều chỗ**: `Publication::STALE_PUBLISHING_AFTER = 10.minutes` (constant trên model `Publication`, không phải ENV/config — ngưỡng này là business rule cố định của ứng dụng cho POC, không cần đổi theo environment). Mọi chỗ cần ngưỡng này (Operation Retry, view hiển thị nút Retry, RSpec spec) đều tham chiếu `Publication::STALE_PUBLISHING_AFTER`, không hard-code lại `10.minutes`/`600` ở nơi khác.

**`MetaGraphClient` SHALL set HTTP request timeout tường minh, ngắn hơn hẳn `STALE_PUBLISHING_AFTER`** (đã bị phát hiện qua review là thiếu chốt — nếu request `POST /feed` không có timeout, hoặc timeout dài hơn 10 phút, 1 request treo thật sự có thể vẫn đang chạy khi Retry coi Publication là stale và cho claim lại, dẫn tới 2 request `POST /feed` chạy song song cho cùng 1 Publication dù mục đích `STALE_PUBLISHING_AFTER` là đợi đủ lâu để coi job cũ chắc chắn đã chết): dùng `open_timeout: 10, read_timeout: 30` (giây) cho client HTTP gọi Meta Graph API — đủ lâu cho 1 request mạng bình thường, nhưng đảm bảo request luôn tự kết thúc (thành công hoặc raise timeout exception, rơi vào `rescue StandardError` ở Decision 7 lớp 1) trong vòng dưới 1 phút, cách xa ngưỡng 10 phút của `STALE_PUBLISHING_AFTER` — không loại bỏ hoàn toàn rủi ro (process bị kill cứng vẫn là rủi ro đã chấp nhận ở lớp 2), nhưng loại bỏ nguyên nhân phổ biến hơn (request treo vô thời hạn do thiếu timeout).

**UI phải cảnh báo rõ rủi ro duplicate trước khi Retry, dựa trên `error_code` chứ không phải `status`** — xem sửa mâu thuẫn bên dưới. Hiển thị message kiểu "Publication này có thể đã đăng thành công trên Facebook trước khi bị gián đoạn — Retry có thể tạo bài đăng trùng. Chỉ bấm Retry nếu đã xác nhận trên Facebook rằng bài chưa xuất hiện." trước khi cho bấm Retry (modal/confirm) khi kết quả không chắc chắn; Retry 1-click thẳng khi chắc chắn an toàn.

**Sửa mâu thuẫn đã bị phát hiện qua review**: bản thiết kế trước nói "Retry từ `failed` không cần cảnh báo vì chắc chắn chưa publish thành công" — SAI, mâu thuẫn với chính Risk bullet "lỗi mạng giữa lúc gửi request và nhận response" ở dưới (Publication có thể Failed trong khi Facebook đã nhận bài thật). `status == "failed"` không đủ thông tin để biết có chắc chắn an toàn hay không. Thông tin đúng để quyết định là `error_code`:
- `error_code` = mã lỗi THẬT từ Meta Graph API (response lỗi có cấu trúc, parse được `error.type`/`error.code`) → Meta đã từ chối request rõ ràng, chắc chắn chưa publish, Retry an toàn, không cần cảnh báo.
- `error_code == "internal_error"` (sentinel khi rescue bắt exception bất kỳ — network timeout, parse lỗi, bug — KHÔNG có response Meta để parse) → không biết Facebook đã nhận bài hay chưa, CÙNG mức rủi ro với Publishing-stale, PHẢI cảnh báo giống hệt.

Quyết định: dùng `error_code == "internal_error"` làm điều kiện hiển thị cảnh báo cho Retry-từ-Failed (thay vì không bao giờ cảnh báo), hợp nhất với điều kiện cảnh báo của Publishing-stale thành 1 rule duy nhất: "cảnh báo khi kết quả publish trước đó không chắc chắn" — không phải "cảnh báo khi status là X".

**Rủi ro chấp nhận có chủ đích, không che giấu**: nếu process chết đúng khoảnh khắc SAU KHI Facebook đã nhận post thật (gọi `POST /feed` thành công) nhưng TRƯỚC KHI kịp ghi `published`/`provider_post_id` vào DB, lớp 2 ở trên sẽ cho phép Retry sau khi stale — Retry đó sẽ gọi `POST /feed` lần nữa, tạo **post trùng thật trên Facebook** (không có cách nào Meta Graph API cho mình idempotency key để chặn tại nguồn). Đây là rủi ro đã biết, cùng loại với rủi ro "double-click Retry sau network timeout" đã ghi ở Risks — chấp nhận cho quy mô POC 1-user, không build idempotency-key/2-phase-commit (over-engineering so với rủi ro thực tế: process bị kill cứng đúng lúc đang gọi 1 API hiếm khi xảy ra trên máy dev cục bộ).

## Risks / Trade-offs

- [Meta Graph API có thể rate-limit khi retry liên tục] → Mitigation: `attempt_count` lưu lại, UI hiển thị rõ để user tự quyết định retry tiếp hay không (không tự động retry vô hạn trong POC).
- [Lỗi mạng giữa lúc gửi request và nhận response (không rõ đã post thành công hay chưa ở phía Facebook)] → Mitigation: xử lý như Failed (Requirement "Published chỉ set khi provider xác nhận thật"), chấp nhận rủi ro duplicate post nếu user bấm Retry thủ công — ghi rõ giới hạn này, không tự động dedupe trong POC (over-engineering cho 1-user POC).

## Migration Plan

Không cần migration mới trừ khi model `Publication` khung ở change 01 thiếu field so với response Meta Graph API thật.
