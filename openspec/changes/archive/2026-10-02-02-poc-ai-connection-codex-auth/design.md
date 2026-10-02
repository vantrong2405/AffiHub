# Design

## Context

Change `01` cung cấp `AIConnection` với quan hệ một connection trên mỗi user. Change `02` hiện thực Codex OAuth/PKCE, token refresh và prompt API. Xem `proposal.md` về lý do, phạm vi POC và rủi ro endpoint không chính thức; xem `specs/ai-connection/spec.md` về contract hành vi.

## Goals / Non-Goals

**Goals:**
- Giữ POC chỉ dùng Codex, nhưng đặt provider contract giữa AI Operations và Codex adapter để thêm provider sau này mà không nhúng Codex behavior vào Operations.
- Làm rõ trạng thái connection, refresh đồng thời, xử lý callback một lần và kết quả lỗi an toàn.
- Đảm bảo cấu hình provider và callback có một nguồn duy nhất.

**Non-Goals:**
- Không triển khai provider khác, multi-provider registry/plugin framework hoặc nhiều connection trên mỗi user.
- Không thay endpoint ChatGPT backend-api không chính thức trong phạm vi change này.

## Decisions

### 1. AI Operations gọi provider qua contract; Codex details nằm trong adapter

Operations phụ thuộc một interface/provider contract nhỏ cho authorize, code exchange, refresh và prompt. Prompt call qua contract chịu trách nhiệm đảm bảo credential còn dùng được, thực hiện refresh khi cần và chỉ sau đó gửi prompt. Codex adapter là hiện thực duy nhất trong POC, sở hữu URL, headers, payload, OAuth details và parsing stream. Chưa tạo registry/plugin framework. Khi bổ sung provider, connection vẫn là một trên mỗi user; cách định danh provider và lưu credential-specific data sẽ được quyết định khi có provider thứ hai, không thêm `provider_metadata` dự phòng.

### 2. Connection usable và reconnect có semantics rõ

Connection chỉ được dùng khi status là connected và access token tồn tại. Nếu token cần refresh thì phải có refresh token; thiếu token cần thiết hoặc provider xác nhận credential bị revoke sẽ chuyển connection sang disconnected. Lỗi transport tạm thời không chứng minh credential bị revoke: trả lỗi thao tác, giữ credential/status hiện tại và không gửi prompt bằng access token đã hết hạn.

OAuth reconnect ghi token mới và cập nhật thời điểm kết nối trong một lần persist nguyên tử. Nếu exchange hoặc persist thất bại, credential/status/thời điểm kết nối cũ không đổi. Thêm `connected_at` để biểu diễn lần kết nối thành công gần nhất; `created_at` không đáp ứng nghĩa đó.

### 3. Refresh được tuần tự hóa theo connection

Refresh giữ row lock của `AIConnection` qua bước đọc trạng thái, quyết định cần refresh hay không, gọi provider và ghi token rotation. Request chờ lock phải reload record và bỏ qua refresh nếu request trước đã cập nhật token/thời hạn. Đây là điểm đánh đổi: lock được giữ trong lúc gọi mạng nhưng tránh dùng refresh token cũ đồng thời trong POC một process. Mọi lỗi transport/provider được phân loại: lỗi xác nhận refresh token invalid/revoked đánh dấu disconnected; lỗi tạm thời hoặc response không phân loại được giữ credential và trả lỗi Operation. Không tiếp tục prompt sau bất kỳ lỗi refresh nào.

### 4. Callback claim nguyên tử và cleanup sở hữu rõ ràng

Listener dùng mutex/one-shot guard để chỉ một request claim quyền xử lý; chỉ handler thắng được verify state, exchange và persist. Handler thua không exchange và không shutdown listener đang được handler thắng sử dụng. Callback error, thiếu code, state mismatch, exchange/transport/DB failure đều trả redirect kết quả tổng quát không chứa chi tiết nhạy cảm. Lỗi được log theo nhóm, không log query token/code hoặc credential. Timeout đóng listener; vì browser đang ở authorization site nên không thể gửi flash tức thời khi không có callback.

Socket được sở hữu bởi Connect Operation cho đến khi handoff thành công. `ensure` đóng socket nếu build URL hoặc spawn listener lỗi; sau handoff listener sở hữu và đóng socket khi xử lý xong hoặc timeout.

### 5. Callback endpoint và config dùng cùng nguồn

`config/codex.yml` là nguồn cho callback host/port/path, OAuth URLs, client ID, scope, refresh lead, timeout và endpoint/model/header versions. Callback listener bind theo cùng loopback host mà redirect URI dùng; không trộn bind `127.0.0.1` với redirect `localhost`. `CodexClient` và callback listener đọc config qua `Rails.application.config_for(:codex)`. Connect khởi chạy bằng POST để prefetch GET không mở listener; callback result vẫn là route relay về Rails app.

### 6. ID token claim dùng làm account context phải được xác minh

`chatgpt_account_id` được gửi trong request header nên là dữ liệu vận hành. Trước khi lưu/sử dụng claim, adapter xác minh JWT signature theo key set của issuer và kiểm tra issuer, audience/client ID, expiry cùng các claim bắt buộc. Token không hợp lệ hoặc thiếu account ID làm flow thất bại; không dùng payload decode-only làm nguồn tin cậy. `chatgpt_plan_type` có thể hiển thị sau khi cùng token đã xác minh.

### 7. Chỉ stream hoàn chỉnh có text là thành công

Codex adapter parser theo SSE event, thu thập output text, nhận diện completion event và provider error event. HTTP 2xx đơn lẻ không đủ: thiếu completion, output rỗng, error event, JSON lỗi hoặc transport interruption trả prompt failure. Operation ánh xạ nhóm lỗi provider/transport thành thông báo thân thiện, không để lỗi mạng thoát thành exception không xử lý.

### 8. Serializer chỉ phát contract UI

Serializer công khai status, plan type và `connected_at`; không phát raw token hoặc `chatgpt_account_id`. Việc bỏ account ID không ảnh hưởng request nội bộ: Operations đọc context từ record và chuyển cho adapter.

## Risks / Trade-offs

- [Row lock được giữ trong network refresh có thể làm request khác chờ] → Thời gian chờ bị giới hạn bởi timeout của Client; request chờ phải reload và bỏ qua refresh nếu token đã mới.
- [JWT verification cần issuer key discovery và claim contract ổn định] → Đóng gói việc xác minh trong adapter; thiếu key, claim hoặc token hợp lệ thì fail closed, không gửi account context.
- [Callback lỗi transport không nhất thiết cho biết token invalid] → Giữ credential cũ, phân biệt lỗi tạm thời với provider rejection rõ ràng.
- [Endpoint ChatGPT backend-api không chính thức có thể đổi hoặc bị chặn] → Giữ toàn bộ chi tiết trong Codex adapter như proposal đã nêu.

## Migration Plan

Thêm `connected_at` nullable cho `ai_connections`; set khi OAuth exchange và persist thành công, không đổi khi reconnect thất bại. Không thêm `provider` hoặc `provider_metadata` cho POC. Giữ unique constraint hiện tại theo `user_id`. Rollback bằng cách bỏ cột `connected_at` và revert adapter/Operation changes.
