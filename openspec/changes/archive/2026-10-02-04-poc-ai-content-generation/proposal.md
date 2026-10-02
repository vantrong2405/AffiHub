# Proposal

## Precondition

**Code gate (đủ để BẮT ĐẦU viết task code/test của change này):**
- Change `03` đã hoàn tất mọi task implementation TRỪ nhóm "Verify thủ công end-to-end" — CSV import + `AccesstradeClient` tạo affiliate link đã code và RSpec pass (HTTP stub ở test). Change `04` dùng Product Factory thuộc `current_user` trong RSpec, KHÔNG phụ thuộc CSV thật hay ACCESSTRADE availability để code/test.
- Gate này áp dụng trước mọi task implementation của change `04`, không chỉ task generate: xác nhận Product đã có `user_id`, association `belongs_to :user`, và scope theo `current_user` như change `03` yêu cầu. Không bắt đầu code change `04` trong khi các prerequisite implementation của change `03` còn pending.

**Archive gate (chỉ archive change `03`, hoặc coi change `03` "xong hẳn", khi đủ)** — và cũng là điều kiện bắt buộc trước khi chạy task "Verify thủ công" của chính change `04` (dùng Product thật, không phải factory):
- Change `03` đã ở trạng thái `archived`.
- Task "Verify thủ công" cuối của change `03` đã xác nhận có ít nhất 1 Product thật trong DB (facts từ CSV Dataminer thật, affiliate link do ACCESSTRADE thật tạo).

## Why

Sau khi có Product thật theo luồng CSV + ACCESSTRADE (change `03`) và kết nối Codex thật (change `02`), vertical slice cần bước sinh nội dung Facebook (hook/caption/CTA/hashtags) từ facts thật, với human review bắt buộc trước khi publish. Change này implement capability `ai-content-generation` trên model khung `Content` đã tạo ở change `01`.

## What Changes

- Implement Generate/Regenerate Content qua provider contract của change `02` (POC nối tới Codex adapter); application giữ nguyên Product facts và tự attach `affiliate_url`.
- Implement lifecycle Content Generated → Review → Approved/Reject với Preview/Edit/Regenerate.
- Implement Regenerate giữ nguyên Product facts/affiliate_url.
- Không coi việc lọc URL là cơ chế xác minh mọi claim: Codex output là draft chưa xác minh, human review bắt buộc trước khi approve/publish.
- Cho phép một Product có nhiều Content độc lập; mỗi Content có lifecycle review riêng. Content Approved không thể regenerate, nhưng không chặn user tạo Content mới từ cùng Product.
- Implement UI Generate Content + Content Review.
- **BREAKING**: không áp dụng.

## Capabilities

### New Capabilities

- `ai-content-generation`: Sinh nhiều Content độc lập (hook/caption/CTA/hashtags) từ cùng Product thật qua provider contract (POC dùng Codex), mỗi Content có lifecycle Generated → Review → Approved/Rejected với Preview/Edit/Regenerate/Approve/Reject; application giữ Product facts và tự attach `affiliate_url`; claim do AI sinh cần human review, không tự động xác minh mọi dữ kiện. Approved là terminal cho từng Content, không khóa Product.

### Modified Capabilities

(không có)

## Impact

- **Code**: `affihub/app/operations/contents/*`, `affihub/app/controllers/contents_controller.rb`, `affihub/app/views/contents/*`.
- **Phụ thuộc**: change `01` (model `Content` khung), change `02` (provider contract/Codex adapter/`AIConnection` hoạt động), change `03` (Product thật có trong DB để test generate).
