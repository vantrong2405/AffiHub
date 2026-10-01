# Design

## Context

Model khung `Content` đã có từ change `01`. `CodexClient`/`AIConnection` hoạt động thật từ change `02`. Product thật có trong DB từ change `03`. Xem `proposal.md` cho motivation.

## Goals / Non-Goals

**Goals:**
- Generate Content dùng lại `CodexClient#send_prompt` của change `02`, không viết client Codex thứ hai.
- Đảm bảo affiliate_url/Product facts không bao giờ bị AI ghi đè — tách rõ "nội dung do AI sinh" và "facts do application attach".

**Non-Goals:**
- Không cho phép multi-platform content (chỉ Facebook, theo scope POC).
- Không tự động approve — human review luôn bắt buộc.

## Decisions

### 1. Prompt builder tách riêng khỏi CodexClient
`app/operations/contents/build_prompt.rb` (hoặc method riêng) build prompt text từ Product facts + tone, không đặt logic này trong `CodexClient` (Client chỉ lo I/O, prompt content là business rule của capability này).

### 2. Lifecycle bằng Rails enum, không thêm gem state machine
`Content` dùng `enum status: { generated: 0, review: 1, approved: 2, rejected: 3 }` (đã có khung ở change 01, change này thêm transition method `approve!`/`reject!`/`regenerate!` trong model hoặc Operation riêng). Đủ đơn giản cho 4 trạng thái tuyến tính, không cần gem `aasm`/`state_machines`.

### 3. Lọc URL lạ bằng regex đơn giản trên response text
Sau khi nhận response từ Codex, Operation quét text tìm pattern URL (`URI.extract` hoặc regex `https?://\S+`), loại bỏ bất kỳ URL nào khác `product.affiliate_url`, trước khi lưu vào `Content#body`.

### 4. Content lưu 1 cột `body` duy nhất (hook+caption+CTA+hashtags gộp thành 1 text), không tách cột riêng
Quyết định (chốt dứt điểm, không để "tuỳ chọn" nữa): `Content#body` là 1 cột text chứa phần copy do AI sinh (hook+caption+CTA+hashtags viết liền thành 1 đoạn) — KHÔNG chứa `affiliate_url` (field đó nằm ở cột riêng `Content#affiliate_url`, app tự attach, xem Requirement "Generate Content từ Product facts thật"). Lý do gộp hook/caption/cta/hashtags vào 1 cột: tách cột riêng chỉ hữu ích nếu UI cần render/style riêng từng phần, nhưng PROJECT_SPEC UI tối thiểu không yêu cầu điều đó — tách là over-engineering cho nhu cầu thật của POC. Khi publish, `MetaGraphPublisher` (change 06) SHALL tự ghép `content.body` + `content.affiliate_url` thành `message` gửi Facebook (xem change 06 design.md) — Publisher KHÔNG gửi nguyên `content.body` một mình, nếu không bài đăng thật sẽ thiếu link affiliate.

Alternative: 4 cột riêng (`hook`, `caption`, `cta`, `hashtags`) rồi ghép lại lúc publish. Bị loại — thêm độ phức tạp parse/ghép không cần thiết, và buộc prompt Codex phải trả JSON có cấu trúc đáng tin cậy (rủi ro parse lỗi) thay vì nhận text thường.

### 5. Regenerate ghi đè `body` trên cùng 1 row Content, không tạo row mới; Reject là terminal, muốn nội dung mới phải Regenerate
- **Regenerate** luôn thao tác trên row `Content` đã có (cùng `id`), ghi đè `body` bằng nội dung mới, tăng `generation_count` (cột đếm, phục vụ audit/hiển thị "đã generate lại N lần") — không tạo thêm row `Content` mới cho cùng 1 Product. Lý do: giữ 1 Content = 1 "bản nháp đang làm việc" cho 1 Product tại 1 thời điểm, khớp với UI Content Review (1 màn hình, không phải danh sách version). Tạo nhiều row sẽ phức tạp hoá việc Publication reference "Content nào" và việc hiển thị UI không cần thiết cho quy mô POC.
- **Reject** là hành động terminal cho vòng review hiện tại: Content chuyển sang `rejected`, không tự động quay lại `review`. Muốn có nội dung mới sau khi Reject, user phải bấm **Regenerate** — hành động này SHALL được cho phép ngay cả khi Content đang `rejected` (ngoại lệ duy nhất so với rule "Regenerate chỉ hợp lệ ở Review" đã nêu ở Requirement) và sẽ chuyển Content từ `rejected` → `review` (qua `start_review!` lại) kèm `body` mới. Đây là lối duy nhất để "generate lại" sau Reject — không có action "Reopen" riêng, tránh thêm trạng thái/nút thừa.
- **Edit** chỉ hợp lệ ở `review` (không áp dụng ở `rejected` — muốn sửa sau khi Reject phải Regenerate trước để quay lại Review).
- **Generate (hành động tạo Content lần đầu) khi Product đã có Content**: `Product has_one :content` (1 Product chỉ có tối đa 1 Content tại 1 thời điểm — khớp "1 Content = 1 bản nháp đang làm việc" ở trên). Nếu Content đã tồn tại cho Product (bất kỳ status nào: `generated`/`review`/`approved`/`rejected`), action Generate SHALL từ chối tạo Content thứ hai — trả lỗi rõ ràng ("Product này đã có Content, dùng Regenerate để tạo nội dung mới") thay vì tạo duplicate. Muốn nội dung mới cho Product đã có Content ở `review`/`rejected`, user dùng **Regenerate** (như đã nêu ở trên). **Content ở `approved` là terminal cho cả Generate lẫn Regenerate** (nhất quán với rule Regenerate chỉ hợp lệ ở `review`/`rejected` đã chốt — không mở thêm nhánh regenerate-từ-approved): 1 Product đã có Content Approved thì không tạo/sinh lại nội dung mới cho Product đó nữa trong phạm vi POC này (chấp nhận giới hạn, không phải bug).

## Risks / Trade-offs

- [Codex có thể sinh nội dung chứa claim sai lệch về sản phẩm dù chỉ nhận facts thật — model vẫn có thể "sáng tạo" thêm chi tiết không có trong facts] → Mitigation: đây là giới hạn vốn có của LLM, human review (bắt buộc) là lớp chặn chính; task cuối verify thủ công đọc kỹ content trước approve.
- [Regex lọc URL có thể bỏ sót URL viết tắt/encode lạ] → Mitigation: đủ cho POC (Codex được prompt rõ không chèn URL), không cần parser phức tạp hơn.

## Migration Plan

Không cần migration mới trừ khi model `Content` khung ở change 01 thiếu cột (vd `body`, `hook`, `cta`, `hashtags` nếu tách riêng thay vì gộp 1 cột `body`).
