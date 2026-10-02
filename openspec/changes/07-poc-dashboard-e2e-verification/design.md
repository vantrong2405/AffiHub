# Design

## Context

Toàn bộ 6 capability (01–06) đã archive, chạy thật riêng lẻ. Xem `proposal.md` cho motivation. Đây là change cuối, thuần tổng hợp + verify, không thêm domain behavior mới.

## Goals / Non-Goals

**Goals:**
- Dashboard đọc dữ liệu thật đã có (AIConnection/AffiliateConnection/SocialConnection status, Publication gần đây) — không tạo dữ liệu mới.
- Verify thủ công đúng 34 bước DoD, ghi lại kết quả thật.

**Non-Goals:**
- Không thêm analytics/calendar/inbox — chỉ status tổng hợp tối thiểu theo UI tối thiểu đã định trong `PROJECT_SPEC.md`.

## Decisions

### 1. Dashboard tuân thủ HMVC: Controller mỏng, query gom trong 1 Operation
`affihub/CLAUDE.md` yêu cầu Controller chỉ nhận request/trả response, business logic/I/O nằm ở Operation layer (`rails_hmvc`). Dù Dashboard chỉ đọc dữ liệu (không có business rule phức tạp), vẫn đặt việc gom query vào `app/operations/dashboard/build_status_operation.rb` (trả về 1 PORO/Struct `{ai_connection:, affiliate_connection:, social_connection:, recent_publications:}`), `DashboardController#show` chỉ gọi Operation này và render — không tự query model trực tiếp trong controller.

Alternative: query model thẳng trong controller (bỏ qua Operation layer vì "chỉ là read-only, không business logic"). Bị loại — vi phạm trực tiếp rule HMVC của `affihub/CLAUDE.md` ("Controllers stay thin... business logic goes through generated layers"), và tạo tiền lệ xấu cho các Controller khác trong dự án.

Route mặc định của ứng dụng dùng `root "dashboard#show"`. Khi Operation thành công, action render view với dữ liệu Operation cung cấp; nếu thất bại, dùng `render_operation` với failure action `:show` để giữ response lỗi theo quy ước HTML controller hiện có.

### 2. Query scope theo `current_user`, không dùng `Model.last`
Từ change `01` đã có login + `belongs_to :user` trên `AIConnection`/`AffiliateConnection`/`SocialConnection` (sau fix ownership). `BuildStatusOperation` SHALL query qua `current_user.ai_connection`, `current_user.affiliate_connections`, `current_user.social_connections` — không dùng `Model.last` (lấy nhầm row của user khác nếu sau này có >1 user, và kể cả với 1 user vẫn là query sai ý nghĩa — "status của user đang đăng nhập", không phải "row mới nhất trong toàn bảng"). `Publication` không có `user_id` trực tiếp (xem change 01) nên lọc qua chain `Publication.joins(social_destination: :social_connection).where(social_connections: { user: current_user })`.

## Risks / Trade-offs

- [Nếu 1 trong 6 change trước chưa thật sự archive/verify xong, Dashboard sẽ hiển thị trạng thái sai lệch] → Mitigation: task đầu tiên của change này xác nhận `openspec status` của change 01–06 đều đã archived trước khi bắt đầu code Dashboard.

## Migration Plan

Không cần migration — chỉ đọc dữ liệu đã có.
