# Proposal

## Precondition

**Code gate (đủ để BẮT ĐẦU viết task code/test của change này):**
- Change `05` đã hoàn tất mọi task TRỪ nhóm "Verify thủ công end-to-end" cuối cùng của nó — `SocialDestination` (model từ change 01) + `MetaGraphClient` đã code + RSpec pass (stub HTTP). Change `06` dùng `FactoryBot.create(:social_destination)` trong RSpec của chính nó, KHÔNG phụ thuộc Page thật đã sync để code/test (PublisherResolver, MetaGraphPublisher, PublishJob).

**Archive gate (chỉ archive change `05`, hoặc coi change `05` "xong hẳn", khi đủ)** — và cũng là điều kiện bắt buộc trước khi chạy task "Verify thủ công end-to-end" của chính change `06` (Post Now thật lên Facebook):
- Change `05` đã ở trạng thái `archived`.
- Task "Verify thủ công" cuối của change `05` đã xác nhận có ít nhất 1 `SocialDestination` thật (Page thật đã sync).

## Why

Đây là bước cuối của chuỗi nghiệp vụ: đăng Content đã Approved (change `04`) lên đúng Facebook Page thật đã chọn (change `05`) qua Meta Graph API thật, theo dõi trạng thái trung thực. Change này implement capability `publication-workflow` trên model khung `Publication` đã tạo ở change `01`.

## What Changes

- Implement tạo Publication từ Content Approved + SocialDestination.
- Implement Post Now (enqueue ngay) và Schedule (enqueue tại `scheduled_at`) qua `PublishJob` (Solid Queue), không block HTTP request.
- Implement `PublisherResolver` chọn publisher theo `destination.provider`+`type`.
- Implement `MetaGraphPublisher` publish thật, parse response thật, set Published/Failed đúng theo kết quả provider.
- Implement Retry cho Publication Failed.
- Implement validation Publication phải có SocialDestination (hoàn thiện phần đã chuẩn bị ở change `05`).
- Implement UI Publication + Publication Status.
- **BREAKING**: không áp dụng.

## Capabilities

### New Capabilities

- `publication-workflow`: Lifecycle Publication (Draft→Scheduled→Publishing→Published/Failed→retry), `PublisherResolver` chọn publisher theo `destination.provider`+`type`, `MetaGraphPublisher` publish thật qua Meta Graph API trong `PublishJob` nền (Post Now/Schedule), lưu `provider_post_id`/`published_url`/`published_at`/`error_code`/`error_message`/`attempt_count`/`provider_metadata` thật, không fake status.

### Modified Capabilities

(không có)

## Impact

- **Code**: `affihub/app/operations/publications/*`, `affihub/app/jobs/publish_job.rb`, `affihub/app/publishers/publisher_resolver.rb`, `affihub/app/publishers/meta_graph_publisher.rb`, `affihub/app/controllers/publications_controller.rb`, `affihub/app/views/publications/*`.
- **Phụ thuộc**: change `01` (model khung `Publication`), change `04` (Content Approved tồn tại), change `05` (SocialDestination + `MetaGraphClient` tồn tại — tái dùng client này để publish, không viết client Meta thứ hai).
