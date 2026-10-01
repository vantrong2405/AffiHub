# Spec Delta

## Purpose

Quản lý kết nối giữa user và Codex (qua cơ chế ChatGPT backend-api, không phải API chính thức OpenAI) — lưu credential thật an toàn và xác nhận kết nối hoạt động bằng một lệnh gọi AI thật, làm nền tảng cho capability `ai-content-generation`.

## ADDED Requirements

### Requirement: User kết nối Codex qua OAuth/PKCE thật với auth.openai.com
Hệ thống SHALL cho phép user khởi tạo flow OAuth/PKCE (authorization_code + PKCE S256) với `auth.openai.com`, dùng client_id public của Codex CLI (không đăng ký app riêng), nhận và lưu `access_token`/`refresh_token`/`id_token` mã hoá tại rest trong `AIConnection`.

#### Scenario: Kết nối Codex thành công
- **WHEN** user hoàn tất consent tại `auth.openai.com` và callback trả về authorization code hợp lệ tại `http://localhost:1455/auth/callback`
- **THEN** hệ thống exchange code lấy token tại `auth.openai.com/oauth/token`, tạo `AIConnection` với token mã hoá, trạng thái connected, trích `chatgptAccountId`/`chatgptPlanType` từ `id_token` lưu kèm

#### Scenario: Token exchange thất bại
- **WHEN** `auth.openai.com` trả lỗi trong bước token exchange (code không hợp lệ/hết hạn)
- **THEN** hệ thống không tạo `AIConnection`, hiển thị lỗi rõ ràng cho user, không lưu token rác

### Requirement: Callback OAuth an toàn trước khi exchange token
Hệ thống SHALL xác thực `state` nhận được tại callback khớp với `state` đã sinh lúc tạo authorize URL trước khi exchange token, và SHALL xử lý đúng các tình huống callback bất thường (timeout, gọi lại nhiều lần, port bận, user huỷ) mà không exchange token sai/sót hoặc treo request.

#### Scenario: State không khớp
- **WHEN** callback tại `:1455/auth/callback` nhận được `state` khác với `state` đã lưu lúc bắt đầu flow
- **THEN** hệ thống từ chối, không gọi token exchange, không tạo `AIConnection`, hiển thị lỗi cho user

#### Scenario: Callback timeout (user không hoàn tất consent)
- **WHEN** listener đã mở quá thời gian chờ tối đa (vd 120 giây) mà chưa nhận được callback nào
- **THEN** hệ thống tự đóng listener, ghi log timeout, không treo request/connection flow vô thời hạn. Lưu ý: ở flow redirect toàn trang này, browser đã rời khỏi Rails app sang `auth.openai.com` nên KHÔNG có trang/JS nào của ta để hiển thị thông báo timeout trực tiếp cho user tại thời điểm xảy ra — user chỉ biết gián tiếp khi quay lại trang AI Connection và thấy vẫn ở trạng thái chưa connected (không có toast/flash timeout real-time)

#### Scenario: Callback bị gọi hai lần
- **WHEN** listener đã xử lý xong 1 callback hợp lệ (đã exchange token hoặc đang exchange) và nhận thêm 1 request callback thứ hai (vd user back/refresh trình duyệt)
- **THEN** hệ thống bỏ qua request callback thứ hai, không exchange token lần nữa, không tạo thêm `AIConnection` trùng

#### Scenario: Port 1455 đã bị chiếm
- **WHEN** user bấm Connect Codex nhưng port 1455 đang bị process khác chiếm, listener không bind được
- **THEN** hệ thống báo lỗi rõ ràng cho user (vd "port 1455 đang bận, đóng ứng dụng khác đang dùng port này") thay vì treo hoặc lỗi mơ hồ

#### Scenario: User huỷ OAuth giữa chừng
- **WHEN** user đóng tab/huỷ consent tại `auth.openai.com` mà không hoàn tất (không có callback nào tới)
- **THEN** hệ thống xử lý giống trường hợp timeout — tự đóng listener sau thời gian chờ, không treo, không tạo `AIConnection`

### Requirement: Refresh token tự động, không tái dùng refresh_token cũ
Hệ thống SHALL tự động refresh access token bằng refresh token đã lưu khi access token sắp hết hạn (access token sống ~1h), và SHALL luôn lưu đè bằng refresh_token MỚI nhận được sau mỗi lần refresh — không bao giờ tái dùng refresh_token đã dùng qua một lần.

#### Scenario: Access token sắp hết hạn
- **WHEN** access token còn hiệu lực dưới ngưỡng an toàn trước khi gọi Codex API
- **THEN** hệ thống dùng refresh token hiện tại để lấy access_token + refresh_token mới, lưu đè refresh_token mới, retry request gốc

#### Scenario: Refresh token đã bị dùng/revoke
- **WHEN** hệ thống cố refresh bằng một refresh_token đã bị thay thế bởi lần refresh trước đó (lỗi từ `auth.openai.com`)
- **THEN** hệ thống đánh dấu `AIConnection` ở trạng thái disconnected và yêu cầu user kết nối lại (toàn bộ session ChatGPT của tài khoản đó đã bị logout ở phía OpenAI)

### Requirement: Test Connection gửi/nhận prompt thật qua ChatGPT backend-api
Hệ thống SHALL cung cấp hành động "Test Connection" gửi một prompt thật tới `https://chatgpt.com/backend-api/codex/responses` (header `originator: codex_cli_rs`, `User-Agent` theo đúng định danh Codex CLI) qua `AIConnection` đã lưu, và hiển thị response thật nhận về cho user.

#### Scenario: Test Connection thành công
- **WHEN** user bấm Test Connection với một `AIConnection` đang connected
- **THEN** hệ thống gửi prompt thật, nhận response thật, hiển thị response đó cho user (không phải response giả lập/hard-code)

### Requirement: Không lộ credential
Hệ thống SHALL không log raw token (access/refresh/id_token) ở bất kỳ log level nào, và SHALL không expose raw token ra bất kỳ response API/frontend nào.

#### Scenario: Xem chi tiết AIConnection trên UI
- **WHEN** user xem trang chi tiết một `AIConnection`
- **THEN** UI chỉ hiển thị trạng thái kết nối, `chatgptPlanType`, thời điểm connect — không hiển thị raw token

#### Scenario: Log request tới Codex
- **WHEN** hệ thống ghi log cho một request gọi `chatgpt.com/backend-api/codex/responses`
- **THEN** log không chứa raw token, chỉ có thể chứa connection id/metadata không nhạy cảm
