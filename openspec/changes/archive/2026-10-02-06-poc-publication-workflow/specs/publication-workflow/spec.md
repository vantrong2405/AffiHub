# Spec Delta

## Purpose

Điều phối việc đăng Content đã Approved lên đúng Facebook Page thật qua Meta Graph API thật, theo dõi trạng thái publish trung thực (chỉ Published khi provider xác nhận thật), hỗ trợ Post Now và Schedule qua background job.

## ADDED Requirements

### Requirement: Tạo Publication từ Content Approved + SocialDestination
Hệ thống SHALL cho phép tạo `Publication` chỉ khi Content ở trạng thái Approved và một `SocialDestination` đã được chọn, khởi tạo ở trạng thái Draft.

#### Scenario: Tạo Publication hợp lệ
- **WHEN** user chọn một Content Approved và một SocialDestination, bấm tạo Publication
- **THEN** hệ thống tạo `Publication` (content_id, social_destination_id) ở trạng thái Draft

#### Scenario: Content chưa Approved
- **WHEN** user cố tạo Publication từ Content chưa ở trạng thái Approved
- **THEN** hệ thống từ chối tạo Publication

#### Scenario: Content không thuộc current_user
- **WHEN** request tạo Publication gửi kèm `content_id` của 1 Content không thuộc `current_user` (dù Content đó đang Approved)
- **THEN** hệ thống từ chối tạo Publication

#### Scenario: SocialDestination không thuộc current_user
- **WHEN** request tạo Publication gửi kèm `social_destination_id` không thuộc `SocialConnection` của `current_user`
- **THEN** hệ thống từ chối tạo Publication

### Requirement: Post Now enqueue PublishJob ngay lập tức
Hệ thống SHALL, khi user chọn Post Now, chuyển Publication sang Scheduled rồi enqueue `PublishJob` ngay lập tức mà không giữ HTTP request chờ kết quả từ social provider.

#### Scenario: User bấm Post Now
- **WHEN** user bấm Post Now trên một Publication ở trạng thái Draft
- **THEN** hệ thống enqueue `PublishJob` ngay, trả response HTTP ngay mà không chờ Facebook xử lý xong

### Requirement: Schedule enqueue PublishJob tại scheduled_at
Hệ thống SHALL, khi user chọn Schedule với một `scheduled_at` trong tương lai, enqueue `PublishJob` để chạy đúng tại thời điểm `scheduled_at`.

#### Scenario: User đặt lịch đăng
- **WHEN** user chọn Schedule với `scheduled_at` = một thời điểm trong tương lai
- **THEN** hệ thống lưu `scheduled_at`, chuyển Publication sang Scheduled, và `PublishJob` chỉ thực thi khi tới đúng thời điểm đó

### Requirement: PublisherResolver chọn đúng publisher theo destination
Hệ thống SHALL dùng `PublisherResolver` để chọn publisher implementation dựa trên `destination.provider` và `destination.type` của Publication, hiện tại resolve về `MetaGraphPublisher` cho provider=facebook/type=page.

#### Scenario: Resolve publisher cho Facebook Page
- **WHEN** `PublishJob` xử lý một Publication có destination provider=facebook, type=page
- **THEN** `PublisherResolver` trả về `MetaGraphPublisher` để thực hiện publish

#### Scenario: Resolve publisher cho provider/type không được hỗ trợ
- **WHEN** `PublisherResolver` được gọi với destination có `(provider, type)` không nằm trong danh sách đã hỗ trợ
- **THEN** hệ thống raise lỗi rõ ràng ngay tại bước resolve (không trả `nil`/âm thầm bỏ qua), được `PublishJob` bắt và set Publication Failed với `error_code: "internal_error"`

### Requirement: MetaGraphPublisher publish thật và parse response thật
Hệ thống SHALL, qua `MetaGraphPublisher`, gọi Meta Graph API thật (`POST /{page-id}/feed`) để đăng bài lên đúng Page (dùng Page token của `SocialDestination`), parse response thật để lấy `provider_post_id` (field `id` trả về, dạng composite `<page_id>_<post_id>`). Vì response của `POST /feed` không chứa URL, hệ thống SHALL gọi tiếp `GET /{id}?fields=permalink_url` ngay sau khi publish thành công để lấy `published_url` từ field `permalink_url` chính thức của Graph API.

#### Scenario: Publish thành công, lấy được permalink_url
- **WHEN** Meta Graph API trả response thành công cho request publish, và request `GET .../permalink_url` tiếp theo cũng thành công
- **THEN** hệ thống lưu `provider_post_id`, `published_url` (từ `permalink_url`), `published_at` thật, chuyển Publication sang Published

#### Scenario: Publish thành công nhưng lấy permalink_url thất bại
- **WHEN** `POST /feed` thành công (có `provider_post_id` thật) nhưng request `GET .../permalink_url` sau đó lỗi/timeout
- **THEN** hệ thống vẫn chuyển Publication sang Published (bài đã đăng thật lên Facebook, không được coi là Failed chỉ vì bước lấy URL phụ trợ lỗi), lưu `published_url = nil` tạm thời, ghi `provider_metadata` ghi nhận việc lấy permalink thất bại để có thể bổ sung sau

#### Scenario: Publish thất bại
- **WHEN** Meta Graph API trả lỗi ở bước `POST /feed` (token hết hạn, permission thiếu, rate limit, v.v.)
- **THEN** hệ thống không set Published, lưu `error_code`/`error_message` thật từ response, tăng `attempt_count`, chuyển Publication sang Failed

### Requirement: PublishJob chỉ publish khi tự claim được transition Scheduled→Publishing
Hệ thống SHALL chỉ cho phép `PublishJob` gọi Meta Graph API khi chính job đó claim thành công việc chuyển Publication từ Scheduled sang Publishing (qua update có điều kiện trên trạng thái nguồn, không dựa vào việc đọc thấy trạng thái hiện tại). Hệ thống SHALL KHÔNG coi việc đọc thấy `status == Publishing` là điều kiện đủ để tiếp tục publish — vì 2 job đồng thời đều có thể đọc thấy `Publishing`.

#### Scenario: Job claim thành công (là job duy nhất xử lý)
- **WHEN** `PublishJob` xử lý một Publication đang ở Scheduled, và job này là job đầu tiên/duy nhất claim được transition Scheduled→Publishing
- **THEN** hệ thống cho phép job gọi `MetaGraphPublisher`, publish thật

#### Scenario: Job thứ hai (duplicate) không claim được
- **WHEN** `PublishJob` chạy nhiều lần cho cùng 1 Publication gần như đồng thời (duplicate enqueue, Solid Queue retry hạ tầng), và 1 job khác đã claim transition Scheduled→Publishing trước đó
- **THEN** job còn lại KHÔNG gọi Meta Graph API dù đọc thấy `status == Publishing`, bỏ qua ngay, ghi log skip, không tạo thêm post trùng trên Facebook

#### Scenario: Job được xử lý trên Publication đã Published hoặc không ở Scheduled
- **WHEN** `PublishJob` bắt đầu xử lý một Publication có `status` là Published, Failed, hoặc Draft (không phải Scheduled)
- **THEN** hệ thống không claim được transition (0 row ảnh hưởng), không gọi Meta Graph API, ghi log cảnh báo, giữ nguyên trạng thái hiện tại của Publication

### Requirement: Post Now/Retry chống double-click bằng claim atomic
Hệ thống SHALL dùng update có điều kiện trên trạng thái nguồn (Draft cho Post Now, Failed hoặc Publishing-stale cho Retry) khi chuyển trạng thái **sang Scheduled** và enqueue `PublishJob`, để double-click không enqueue 2 job cho cùng 1 Publication. Hệ thống SHALL KHÔNG có path nào khác chuyển thẳng sang Publishing ngoài claim atomic trong chính `PublishJob` (Requirement "PublishJob chỉ publish khi tự claim được transition Scheduled→Publishing") — Post Now/Schedule/Retry đều chỉ đưa Publication về Scheduled, không bao giờ tự set Publishing ở Controller.

#### Scenario: Double-click Post Now
- **WHEN** user bấm Post Now 2 lần liên tiếp rất nhanh trên cùng 1 Publication
- **THEN** chỉ request đầu tiên claim được transition Draft→Scheduled và enqueue `PublishJob`; request thứ hai không claim được (0 row), không enqueue thêm job

#### Scenario: Double-click Retry
- **WHEN** user bấm Retry 2 lần liên tiếp rất nhanh trên cùng 1 Publication Failed
- **THEN** chỉ request đầu tiên claim được transition Failed→Scheduled và enqueue `PublishJob`; request thứ hai không claim được (0 row), không enqueue thêm job

### Requirement: Retry Publication Failed (hoặc Publishing bị kẹt)
Hệ thống SHALL cho phép Retry một Publication ở trạng thái Failed — chuyển về Scheduled (KHÔNG phải Publishing — claim atomic trong `PublishJob` là nơi DUY NHẤT chuyển sang Publishing), enqueue lại `PublishJob`. Hệ thống SHALL cũng cho phép Retry một Publication đang Publishing nếu `last_attempt_at` cũ hơn ngưỡng stale (vd 10 phút) — coi như job trước đó đã chết giữa chừng (process crash) — cùng claim về Scheduled.

#### Scenario: User retry Publication Failed
- **WHEN** user bấm Retry trên một Publication Failed
- **THEN** hệ thống claim Failed→Scheduled, enqueue `PublishJob` mới, giữ nguyên `attempt_count` đã tích luỹ trước đó rồi tăng tiếp nếu thất bại tiếp

#### Scenario: User retry Publication Publishing bị kẹt (stale)
- **WHEN** user bấm Retry trên một Publication đang Publishing với `last_attempt_at` cũ hơn ngưỡng stale (process xử lý trước đó đã chết giữa chừng, không có job nào tự phục hồi)
- **THEN** hệ thống claim Publishing(stale)→Scheduled, enqueue `PublishJob` mới — chấp nhận rủi ro tạo post trùng thật trên Facebook nếu job trước đó thực ra đã publish thành công nhưng chết trước khi ghi DB (rủi ro đã biết, xem design.md Decision 7, không có cơ chế idempotency key phía Meta Graph API để loại trừ hoàn toàn)

#### Scenario: Retry khi Publishing chưa đủ stale
- **WHEN** user bấm Retry trên một Publication đang Publishing với `last_attempt_at` MỚI hơn ngưỡng stale (job có thể vẫn đang chạy thật)
- **THEN** hệ thống từ chối Retry, không claim, không enqueue thêm job

### Requirement: Cảnh báo rủi ro duplicate trước khi Retry — dựa trên kết quả có AMBIGUOUS hay không, không dựa trên status
Hệ thống SHALL hiển thị cảnh báo duplicate trước khi Retry bất kỳ khi nào kết quả lần publish trước KHÔNG CHẮC CHẮN — tức là Publication không nhận được response thật có cấu trúc từ Meta Graph API xác nhận thất bại (ký hiệu: `error_code == "internal_error"`, bao gồm cả Publishing-stale lẫn Failed-do-exception/network). Hệ thống SHALL KHÔNG hiển thị cảnh báo khi Meta Graph API đã trả về 1 response lỗi thật có cấu trúc xác nhận thất bại (`error_code` là mã lỗi thật từ Meta, không phải `"internal_error"`) — trường hợp đó chắc chắn chưa publish, Retry an toàn.

Lý do tách theo `error_code` thay vì theo `status`: "Failed" không đồng nghĩa với "chắc chắn chưa publish" — một Publication có thể Failed vì (a) Meta trả lỗi thật (token hết hạn, permission thiếu...) → chắc chắn chưa publish, an toàn; hoặc (b) exception/network timeout xảy ra trước khi nhận được response, có thể Facebook đã nhận bài thành công trước khi app kịp biết → không chắc chắn, cùng loại rủi ro với Publishing-stale. `error_code == "internal_error"` (sentinel đã chốt ở Requirement "Published chỉ set khi provider xác nhận thật") chính là tín hiệu để phân biệt 2 case này.

#### Scenario: User bấm Retry trên Publishing-stale
- **WHEN** user bấm Retry trên 1 Publication đang Publishing (stale)
- **THEN** hệ thống hiển thị cảnh báo rủi ro duplicate trước, yêu cầu xác nhận thêm 1 bước trước khi thực sự claim/enqueue

#### Scenario: User bấm Retry trên Failed với error_code thật từ Meta (an toàn)
- **WHEN** user bấm Retry trên 1 Publication Failed có `error_code` là mã lỗi thật từ Meta Graph API (vd token hết hạn, permission thiếu)
- **THEN** hệ thống KHÔNG hiển thị cảnh báo duplicate (chắc chắn chưa publish), claim/enqueue ngay

#### Scenario: User bấm Retry trên Failed với error_code = internal_error (không chắc chắn)
- **WHEN** user bấm Retry trên 1 Publication Failed có `error_code == "internal_error"` (do exception/network timeout trước khi nhận response)
- **THEN** hệ thống hiển thị CÙNG cảnh báo duplicate như Publishing-stale trước khi cho claim/enqueue — vì không chắc chắn Facebook đã nhận bài hay chưa

### Requirement: Published chỉ set khi provider xác nhận thật
Hệ thống SHALL không bao giờ set Publication = Published chỉ vì job chạy xong; trạng thái Published chỉ được set sau khi response thành công thật từ Meta Graph API được parse. Hệ thống SHALL bọc toàn bộ lời gọi publish trong xử lý lỗi áp dụng cho MỌI exception (không chỉ lỗi mạng) — bất kỳ exception nào trong lúc publish đều chuyển Publication sang Failed, không bao giờ để Publication "treo" ở Publishing do 1 exception Ruby không được bắt.

#### Scenario: Job chạy xong nhưng chưa nhận response provider
- **WHEN** `PublishJob` gặp lỗi mạng trước khi nhận được response từ Meta Graph API
- **THEN** Publication không được set Published, được xử lý như publish thất bại (Failed, có thể retry)

#### Scenario: Exception bất kỳ trong lúc publish (không chỉ lỗi mạng)
- **WHEN** `MetaGraphPublisher#publish` raise 1 exception bất kỳ (không riêng lỗi mạng — ví dụ lỗi parse response không mong đợi)
- **THEN** `PublishJob` bắt exception đó, chuyển Publication sang Failed, lưu `error_message` từ exception, set `error_code = "internal_error"` (sentinel cố định — phân biệt với error_code thật lấy từ response lỗi của Meta Graph API khi provider trả lỗi có cấu trúc), tăng `attempt_count` — không để Publication treo ở Publishing

### Requirement: Publication luôn reference SocialDestination cụ thể
Hệ thống SHALL yêu cầu mọi Publication reference một `SocialDestination` cụ thể, không được reference provider Facebook chung chung.

#### Scenario: Tạo Publication không chọn Page
- **WHEN** user cố tạo Publication mà chưa chọn `SocialDestination`
- **THEN** hệ thống từ chối tạo Publication và yêu cầu chọn Page trước
