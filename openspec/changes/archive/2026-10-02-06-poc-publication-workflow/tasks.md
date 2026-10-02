# Tasks

## 1. Porting Note

- [ ] 1.1 Đọc lại phần publishing/scheduling/retry/status của `gitroomhq/postiz-app` (đào sâu hơn phần đã đọc ở change 05), đối chiếu Meta Graph API docs cho endpoint publish lên Page hiện hành. Viết `affihub/docs/reference-analysis/publication-workflow.md` đủ mục template, verify: file tồn tại

## 2. Migration bổ sung (nếu cần)

- [x] 2.1 Viết `spec/models/publication_spec.rb` bổ sung field phát hiện thiếu (nếu có), chạy fail nếu cột chưa có
- [x] 2.2 Thêm migration tương ứng để spec pass, verify: spec pass (bỏ qua nếu change 01 đã đủ)

## 3. Tạo Publication

- [x] 3.1 Viết `spec/forms/publications/create_form_spec.rb` (Requirement "Tạo Publication từ Content Approved + SocialDestination" + "Publication luôn reference SocialDestination cụ thể": reject khi Content chưa Approved hoặc thiếu SocialDestination; scenario Content/SocialDestination không thuộc current_user → reject cả hai case), chạy fail
- [x] 3.2 Implement `app/forms/publications/create_form.rb` (validate `content.user_id == current_user.id` và `social_destination.social_connection.user_id == current_user.id`) để spec 3.1 pass, verify: spec pass
- [x] 3.3 Viết `spec/operations/publications/create_operation_spec.rb` (tạo Publication Draft hợp lệ), chạy fail
- [x] 3.4 Implement `app/operations/publications/create_operation.rb` để spec 3.3 pass, verify: spec pass

## 4. PublisherResolver

- [x] 4.1 Viết `spec/publishers/publisher_resolver_spec.rb` (Requirement "PublisherResolver chọn đúng publisher theo destination": `PublisherResolver.resolve(destination)` trả `MetaGraphPublisher` cho (facebook, page); scenario provider/type lạ → raise lỗi rõ ràng, không trả nil), chạy fail
- [x] 4.2 Implement `app/publishers/publisher_resolver.rb` (`REGISTRY` constant + classmethod `resolve`) để spec 4.1 pass, verify: spec pass

## 5. MetaGraphPublisher

- [x] 5.1 Viết `spec/clients/meta_graph_client_spec.rb` bổ sung method publish post lên Page (dùng Page token); assert request URL/version được lấy từ `config/facebook.yml` và body/header chính xác, chạy fail
- [x] 5.2 Implement `app/clients/meta_graph_client.rb#publish_post` bằng HTTP request method chung của change 05; không thêm transport riêng hoặc hard-code URL/version, verify: spec pass
- [x] 5.3 Viết `spec/clients/meta_graph_client_spec.rb` bổ sung method lấy `permalink_url` qua `GET /{id}?fields=permalink_url` sau khi publish; assert request URL/version được lấy từ config, chạy fail
- [x] 5.4 Implement `app/clients/meta_graph_client.rb#fetch_permalink_url` bằng cùng HTTP request method để spec 5.3 pass, verify: spec pass
- [x] 5.5 Viết `spec/publishers/meta_graph_publisher_spec.rb` (Requirement "MetaGraphPublisher publish thật và parse response thật": `message` gửi lên Meta Graph API = `"#{publication.content.body}\n\n#{publication.content.affiliate_url}"` (body và affiliate_url là 2 cột riêng trên Content — xem change 04 Decision 4 — publisher SHALL ghép lại thành 1 text khi gọi `publish_post`, affiliate_url KHÔNG được để sót khỏi bài đăng thật); thành công parse provider_post_id + published_url qua permalink_url + published_at; permalink_url lỗi vẫn Published với published_url=nil; publish thất bại parse error_code/error_message), chạy fail
- [x] 5.6 Implement `app/publishers/meta_graph_publisher.rb` (gọi `publish_post` rồi `fetch_permalink_url`, trả `Result` object) để spec 5.5 pass, verify: spec pass
- [x] 5.7 Viết `spec/clients/meta_graph_client_spec.rb` bổ sung assertion mọi request qua shared transport truyền `open_timeout`/`read_timeout` từ `config/facebook.yml` (defaults 10/30 giây, ngắn hơn `STALE_PUBLISHING_AFTER`), chạy fail
- [x] 5.8 Thêm timeout defaults vào `config/facebook.yml` và áp dụng trong shared transport của `MetaGraphClient` để spec 5.7 pass, verify: spec pass

## 6. PublishJob — Post Now / Schedule + claim atomic (chống duplicate publish)

- [x] 6.1 Viết `spec/jobs/publish_job_spec.rb` (Requirement "PublishJob chỉ publish khi tự claim được transition Scheduled→Publishing": publication `published`/`failed`/`draft` → `update_all(status: "scheduled" → "publishing")` trả 0 row, job no-op không gọi Publisher; 2 lần gọi `perform` liên tiếp cho cùng Publication đang `scheduled` → chỉ lần đầu claim được (1 row), lần sau 0 row), chạy fail
- [x] 6.2 Implement claim atomic đầu `app/jobs/publish_job.rb#perform` (`Publication.where(id:, status: "scheduled").update_all(status: "publishing")`, return nếu 0 row) để spec 6.1 pass, verify: spec pass
- [x] 6.3 Viết `spec/jobs/publish_job_spec.rb` bổ sung case claim thành công (Requirement "Post Now enqueue PublishJob ngay lập tức": sau khi claim thành công, gọi PublisherResolver + Publisher, set Published/Failed theo Result object; case Failed (Requirement "Post thành công hoặc ghi lỗi thật từ Meta Graph API" - scenario Publish thất bại): `attempt_count` tăng thêm 1 so với trước khi job chạy), chạy fail
- [x] 6.4 Implement phần còn lại của `app/jobs/publish_job.rb#perform` (chạy sau claim thành công; nhánh Failed set `error_code`/`error_message` + `attempt_count: publication.attempt_count + 1`) để spec 6.3 pass, verify: spec pass
- [x] 6.5 Viết `spec/requests/publications_spec.rb` bổ sung case Post Now (Requirement "Post Now/Retry chống double-click bằng claim atomic": action claim `draft`→`scheduled` bằng `update_all` có điều kiện, chỉ request đầu enqueue `PublishJob.perform_later`, request thứ 2 double-click không claim được nên không enqueue thêm; response không block), chạy fail
- [x] 6.6 Implement `app/operations/publications/post_now_operation.rb` (claim atomic — `Publication` KHÔNG có cột `user_id` riêng (quyền sở hữu đi qua `Publication belongs_to :content`, `content.user_id`) nên claim SHALL join qua association ngay trong câu `update_all`, không query riêng rồi check sau: `Publication.joins(:content).where(id:, status: "draft", contents: { user_id: current_user.id }).update_all(status: "scheduled")` — ownership nằm trong `WHERE` của claim để tránh TOCTOU + tránh user A claim được Publication của user B — + `PublishJob.perform_later` trong cùng 1 `ActiveRecord::Base.transaction` — xem design.md Decision 6) + action Post Now trong `app/controllers/publications_controller.rb` CHỈ gọi `operator = PostNowOperation.call(params:)` rồi `render_operation` (Controller KHÔNG tự `update_all`/mutate Model — vi phạm convention đã chốt ở change 01 nếu làm vậy) để spec 6.5 pass, verify: spec pass + request spec case user khác cố Post Now Publication không phải của mình → 0 row claim, không enqueue
- [x] 6.7 Viết `spec/requests/publications_spec.rb` bổ sung case Schedule (Requirement "Schedule enqueue PublishJob tại scheduled_at": action claim `draft`→`scheduled` kèm `scheduled_at`, validate `scheduled_at` phải ở tương lai (reject nếu quá khứ), `PublishJob.set(wait_until: scheduled_at).perform_later`), chạy fail
- [x] 6.8 Implement `app/operations/publications/schedule_operation.rb` (validate `scheduled_at > Time.current`, claim atomic `Publication.joins(:content).where(id:, status: "draft", contents: { user_id: current_user.id })` — cùng convention ownership-in-WHERE qua `content.user_id` như `post_now_operation` task 6.6 (Publication không có cột `user_id` riêng) + `PublishJob.set(wait_until:).perform_later` cùng 1 `ActiveRecord::Base.transaction` — xem design.md Decision 6) + action Schedule trong Controller CHỈ gọi `operator = ScheduleOperation.call(params:)` rồi `render_operation` để spec 6.7 pass, verify: spec pass

## 7. Published chỉ set khi provider xác nhận thật (mọi exception, không chỉ lỗi mạng)

- [x] 7.1 Viết `spec/jobs/publish_job_spec.rb` bổ sung case lỗi mạng trước khi nhận response (Requirement "Published chỉ set khi provider xác nhận thật"), chạy fail
- [x] 7.2 Viết `spec/jobs/publish_job_spec.rb` bổ sung case exception bất kỳ (không riêng network, vd lỗi parse response) khi đang `publishing` (Requirement "Published chỉ set khi provider xác nhận thật" - scenario exception bất kỳ): job bắt exception, chuyển `publishing`→`failed`, set `error_code = "internal_error"` (sentinel, phân biệt với error_code thật từ Meta API), không để treo ở `publishing`, chạy fail
- [x] 7.3 Implement `app/jobs/publish_job.rb#perform` bọc toàn bộ lời gọi `MetaGraphPublisher#publish` trong `begin/rescue StandardError` (không riêng network error, set `error_code: "internal_error"` khi rơi vào nhánh rescue này, **KHÔNG re-raise** — job kết thúc bình thường theo ActiveJob sau khi ghi Failed, để Solid Queue không tự retry song song với cơ chế Retry của app) để spec 7.1 + 7.2 pass, verify: spec pass
- [x] 7.4 Viết test (RSpec `allow(Rails.logger).to receive(:error)` hoặc tương đương) xác nhận nhánh rescue ở 7.3 log đủ `publication.id`, exception class, exception message, backtrace, `page_id` của SocialDestination (nếu có) TRƯỚC khi set Failed, chạy fail
- [x] 7.5 Implement `Rails.logger.error` đủ field trên trong nhánh rescue để spec 7.4 pass, verify: spec pass

## 8. Retry (từ Failed, hoặc từ Publishing bị kẹt/stale) — luôn claim về Scheduled, không bao giờ claim thẳng sang Publishing

- [x] 8.1 Viết `spec/requests/publications_spec.rb` bổ sung case Retry từ Failed (Requirement "Retry Publication Failed (hoặc Publishing bị kẹt)" + "Post Now/Retry chống double-click bằng claim atomic": action claim `failed`→`scheduled` (KHÔNG phải `publishing`) bằng `update_all` có điều kiện NGAY trong request trước khi enqueue, rồi enqueue `PublishJob` mới, giữ nguyên `attempt_count` tích luỹ; double-click Retry chỉ request đầu enqueue), chạy fail
- [x] 8.2 Implement `app/operations/publications/retry_operation.rb` (claim atomic `Publication.joins(:content).where(id:, status: "failed", contents: { user_id: current_user.id })` — cùng convention ownership-in-WHERE qua `content.user_id` như task 6.6 + enqueue `PublishJob` mới trong cùng 1 `ActiveRecord::Base.transaction` — xem design.md Decision 6) + action Retry trong Controller CHỈ gọi `operator = RetryOperation.call(params:)` rồi `render_operation` để spec 8.1 pass, verify: spec pass
- [x] 8.3 Viết `spec/models/publication_spec.rb` xác nhận hằng số `Publication::STALE_PUBLISHING_AFTER` tồn tại (giá trị `10.minutes`) và `last_attempt_at` được set ngay lúc `PublishJob` claim `scheduled`→`publishing` thành công (field đã có từ change 01, chỉ cần đảm bảo được set đúng lúc trong `PublishJob`, không phải lúc tạo Publication), chạy fail nếu chưa có
- [x] 8.4 Implement `Publication::STALE_PUBLISHING_AFTER = 10.minutes` (constant trên model, single source — mọi nơi khác tham chiếu hằng số này, không hard-code lại `10.minutes`) + set `last_attempt_at` trong claim atomic của `PublishJob` (`update_all(status: "publishing", last_attempt_at: Time.current)`) để spec 8.3 pass, verify: spec pass
- [x] 8.5 Viết `spec/requests/publications_spec.rb` bổ sung case Retry từ Publishing-stale (Requirement "Retry Publication Failed (hoặc Publishing bị kẹt)" - scenario Publishing bị kẹt/stale: `last_attempt_at` cũ hơn `Publication::STALE_PUBLISHING_AFTER` → claim `publishing`→`scheduled` thành công, enqueue job mới; mới hơn → từ chối, không claim, không enqueue), chạy fail
- [x] 8.6 Mở rộng `app/operations/publications/retry_operation.rb` nhận thêm case Publishing-stale (claim atomic `publishing`→`scheduled` kèm điều kiện `last_attempt_at < Publication::STALE_PUBLISHING_AFTER.ago`, dùng CHUNG `joins(:content).where(..., contents: { user_id: current_user.id })` như case `failed`→`scheduled` ở task 8.2 — không bỏ sót ownership scope cho nhánh stale này, cùng 1 `ActiveRecord::Base.transaction` với enqueue — xem design.md Decision 6) để spec 8.5 pass, verify: spec pass
- [x] 8.7 Viết `spec/models/publication_spec.rb` cho method `ambiguous_outcome?` trên `Publication` (true khi `status == "publishing"` (stale, đang kẹt) HOẶC (`status == "failed"` VÀ `error_code == "internal_error"`); false khi `status == "failed"` với `error_code` là mã lỗi thật từ Meta) (Requirement "Cảnh báo rủi ro duplicate trước khi Retry — dựa trên kết quả có AMBIGUOUS hay không, không dựa trên status"), chạy fail
- [x] 8.8 Implement `Publication#ambiguous_outcome?` trong `app/models/publication.rb` để spec 8.7 pass, verify: spec pass
- [x] 8.9 Viết `spec/requests/publications_spec.rb` bổ sung case cảnh báo (action Retry khi `publication.ambiguous_outcome?` true yêu cầu param xác nhận riêng (vd `confirm_duplicate_risk: true`) — thiếu param này thì KHÔNG claim/enqueue, chỉ trả về nội dung cảnh báo; khi `ambiguous_outcome?` false thì claim/enqueue ngay không cần param này), chạy fail
- [x] 8.10 Implement 2-bước xác nhận cho Retry khi `ambiguous_outcome?` true (action yêu cầu `confirm_duplicate_risk` param trước khi claim/enqueue) để spec 8.9 pass, verify: spec pass
- [x] 8.11 Implement UI nút Retry hiển thị cho status Failed (mọi error_code) VÀ status Publishing khi `last_attempt_at` đã stale (ẩn nếu Publishing còn mới); nút Retry mở modal cảnh báo duplicate khi `publication.ambiguous_outcome?` true trước khi gửi request kèm `confirm_duplicate_risk: true` — gửi thẳng không qua modal khi `ambiguous_outcome?` false

## 9. UI Publication + Publication Status

- [x] 9.1 Viết `spec/requests/publications_spec.rb` bổ sung case `new`/`show` (form tạo Publication, trang Publication Status hiển thị đúng status/provider_post_id/published_url/error), chạy fail
- [x] 9.2 Thêm `resources :publications, only: [:new, :create, :show] do member { post :post_now; post :schedule; post :retry } end` (hoặc tương đương) vào `config/routes.rb`. Dùng skill `ui-ux` để quyết định layout/component/token màu cho form tạo Publication và trang Publication Status trước khi viết view; implement `app/controllers/publications_controller.rb` + views Publication (tạo Publication, chọn Post Now/Schedule, xem Publication Status, nút Retry theo đúng rule task 8.11 — hiển thị khi Failed (mọi error_code) HOẶC khi Publishing stale, modal cảnh báo duplicate khi `ambiguous_outcome?` true). Các action create/post_now/schedule/retry dùng `render_operation`; action new/show là read-only, gọi Operation rồi render view trực tiếp, không query Model trong Controller; để spec 9.1 pass, verify: spec pass + `rtk bin/dev` luồng thao tác được trên UI

## 10. Verify thủ công end-to-end toàn chuỗi publish

- [ ] 10.1 Post Now thật lên Facebook Page thật đã connect ở change 05, verify: bài viết xuất hiện thật trên Facebook, `provider_post_id`/`published_url`/`published_at` lưu đúng với dữ liệu Meta trả về
- [x] 10.2 Chạy `RAILS_ENV=test rtk bundle exec rspec spec/forms/publications spec/operations/publications spec/publishers/publisher_resolver_spec.rb spec/publishers/meta_graph_publisher_spec.rb spec/jobs/publish_job_spec.rb spec/requests/publications_spec.rb`, verify: pass 100%
