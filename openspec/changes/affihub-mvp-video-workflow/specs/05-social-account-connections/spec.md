# Spec Delta

## Purpose

Cho phép người dùng quản lý độc lập nhiều profile và đích xuất bản trên bốn nền tảng, đồng thời biết connector nào đủ quyền và sẵn sàng hoạt động.

## ADDED Requirements

### Requirement: Kết nối nhiều profile độc lập
AffiHub MUST cho phép kết nối nhiều profile/tài khoản Facebook, TikTok, Instagram và YouTube mà không bắt buộc cấu hình đủ mọi nền tảng.

#### Scenario: Kết nối thêm profile
- **WHEN** người dùng thêm profile thứ hai trên cùng nền tảng
- **THEN** AffiHub tạo kết nối riêng và giữ nguyên trạng thái của profile đã có

#### Scenario: Một nền tảng chưa cấu hình
- **WHEN** người dùng chưa kết nối một nền tảng
- **THEN** các nền tảng đã kết nối cùng import, edit, render và local export vẫn hoạt động

### Requirement: Bảo vệ OAuth và credential
AffiHub MUST dùng state ngẫu nhiên, khó đoán, hết hạn, dùng một lần và gắn với phiên bắt đầu OAuth; dùng PKCE khi provider hỗ trợ, callback allowlist, quyền tối thiểu, mã hóa token/API key khi lưu và không để lộ secret trong log/giao diện.

#### Scenario: Hoàn tất OAuth callback
- **WHEN** callback có state hợp lệ và trả về credential
- **THEN** AffiHub lưu credential cho đúng profile và hiển thị trạng thái kết nối không tiết lộ secret

#### Scenario: Callback không hợp lệ
- **WHEN** callback state hoặc địa chỉ callback không hợp lệ
- **THEN** AffiHub từ chối callback, không tạo connection và không ghi credential vào log

#### Scenario: Callback replay hoặc đổi phiên
- **WHEN** state đã dùng, hết hạn hoặc callback đến từ phiên khác với phiên bắt đầu OAuth
- **THEN** AffiHub từ chối callback và yêu cầu khởi động lại kết nối

### Requirement: Chọn đích được profile cấp quyền
AffiHub MUST liệt kê và cho chọn riêng các Page, kênh hoặc tài khoản mà profile đã kết nối có quyền sử dụng.

#### Scenario: Facebook profile quản lý nhiều Page
- **WHEN** OAuth trả về nhiều Page có thể đăng
- **THEN** người dùng xem tên và ID từng Page, kiểm tra quyền rồi chọn một hoặc nhiều Page

#### Scenario: Chọn YouTube channel
- **WHEN** Google OAuth profile có một hoặc nhiều channel khả dụng
- **THEN** người dùng chọn channel đích cụ thể trước khi publish

### Requirement: Kết nối Instagram qua Facebook Login
AffiHub MUST dùng Instagram API with Facebook Login, thông qua Facebook Login for Business OAuth cho MVP; lấy các Page được profile quản lý qua `/me/accounts`, rồi lưu Page Access Token cùng `instagram_business_account` ID của Page được chọn. Theo Meta-published Instagram API collection được đối chiếu ngày 2026-10-08, flow này dùng `pages_show_list`, `pages_read_engagement`, `instagram_basic`, `instagram_content_publish`; các scope `instagram_business_*` thuộc Instagram Login và MUST NOT được dùng trong Facebook Login flow này. Trước implementation MUST xác minh lại permission dependency/access tier với Meta docs/App Dashboard.

#### Scenario: Chọn Page có Instagram Business account
- **WHEN** OAuth profile trả về Page có Instagram Business account liên kết
- **THEN** AffiHub cho chọn Page và lưu mapping Page ID, Page Access Token cùng Instagram Business account ID cho đúng connection

#### Scenario: Page không có Instagram Business account phù hợp
- **WHEN** Page không có Instagram Business account liên kết đủ điều kiện
- **THEN** AffiHub không tạo Instagram destination cho Page đó và hiển thị điều kiện cần bổ sung

### Requirement: Kiểm tra điều kiện loại tài khoản nền tảng
AffiHub MUST phát hiện điều kiện account/platform access cần thiết và nêu rõ giới hạn trước khi cho dùng đích.

#### Scenario: Instagram không phải Business
- **WHEN** tài khoản Instagram được chọn không phải Business account có Page liên kết phù hợp
- **THEN** AffiHub chặn publish Instagram và hướng dẫn điều kiện cần bổ sung

#### Scenario: TikTok chưa qua audit publish
- **WHEN** TikTok app chưa qua audit Content Posting API
- **THEN** AffiHub hiển thị trạng thái audit và giới hạn `SELF_ONLY` cùng điều kiện tài khoản private

### Requirement: Hiển thị sức khỏe và lỗi theo connector
AffiHub MUST hiển thị quyền, hạn chế, lỗi API và hành động khắc phục cho đúng connection hoặc destination bị ảnh hưởng.

#### Scenario: Token hết hạn hoặc quyền bị thu hồi
- **WHEN** kiểm tra connector phát hiện token hết hạn hoặc thiếu quyền
- **THEN** AffiHub chỉ đánh dấu connection/destination tương ứng và hướng dẫn kết nối lại hoặc bổ sung quyền

### Requirement: Tách kỹ thuật hoàn tất khỏi quyền đăng công khai
AffiHub MUST hiển thị riêng trạng thái tích hợp kỹ thuật và trạng thái review/audit của nền tảng.

#### Scenario: Connector bị giới hạn bởi review
- **WHEN** API cho phép test nhưng chưa cấp quyền đăng công khai
- **THEN** AffiHub cho biết khả năng test hiện có và không hiển thị connector như đã sẵn sàng public
