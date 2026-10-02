# Spec Delta

## Purpose

Quản lý kết nối giữa user và Codex trong POC, lưu credential an toàn, kiểm tra khả năng gọi AI thật và tạo ranh giới provider để có thể thay adapter trong tương lai.

## ADDED Requirements

### Requirement: Mỗi user có tối đa một AI connection
Hệ thống SHALL duy trì tối đa một AI connection cho mỗi user trong POC; kết nối lại cập nhật connection hiện có.

#### Scenario: User kết nối lại Codex
- **WHEN** user đã có một AI connection và hoàn tất kết nối Codex thành công
- **THEN** hệ thống cập nhật connection hiện có thay vì tạo connection thứ hai

### Requirement: Kết nối Codex qua OAuth/PKCE
Hệ thống SHALL hỗ trợ OAuth authorization_code với PKCE S256 qua `auth.openai.com` và lưu token được mã hóa tại rest.

#### Scenario: Kết nối Codex thành công
- **WHEN** user hoàn tất consent và callback trả code cùng state hợp lệ
- **THEN** hệ thống đổi code lấy token và lưu connection ở trạng thái connected

#### Scenario: Kết nối mới bị từ chối
- **WHEN** token exchange của user chưa có connection thất bại
- **THEN** hệ thống không tạo connection và hiển thị lỗi an toàn, không chứa credential

#### Scenario: Kết nối lại thất bại
- **WHEN** token exchange thất bại trong lúc user đã có connection
- **THEN** hệ thống giữ nguyên credential, status và thời điểm kết nối thành công trước đó

### Requirement: Callback OAuth chỉ được xử lý một lần
Hệ thống SHALL xác thực `state` trước token exchange và chỉ cho phép một callback cạnh tranh nhận quyền xử lý flow đó.

#### Scenario: Callback có state không khớp
- **WHEN** callback nhận state khác với state của flow
- **THEN** hệ thống không exchange code, không thay đổi connection và chuyển browser tới kết quả lỗi an toàn

#### Scenario: Hai callback đến đồng thời
- **WHEN** hai request callback cùng đến trước khi flow hoàn tất
- **THEN** chỉ một request được xử lý và thực hiện tối đa một token exchange

#### Scenario: Callback thiếu code hoặc trả OAuth error
- **WHEN** callback không có code hợp lệ hoặc chứa tham số `error`
- **THEN** hệ thống không exchange token, giữ nguyên connection hiện có và chuyển browser tới kết quả lỗi an toàn

#### Scenario: Callback exchange hoặc lưu trữ gặp lỗi
- **WHEN** token endpoint lỗi, transport timeout hoặc lưu connection thất bại
- **THEN** hệ thống không lưu credential dở dang, ghi log không nhạy cảm và chuyển browser tới kết quả lỗi tổng quát

#### Scenario: Callback timeout hoặc user hủy consent
- **WHEN** không có callback hoàn tất trước timeout
- **THEN** hệ thống đóng listener, ghi log timeout không nhạy cảm và giữ nguyên connection hiện có

#### Scenario: Callback port đang bận
- **WHEN** hệ thống không thể bind callback listener
- **THEN** connect flow thất bại trước redirect và hiển thị lỗi rõ ràng

#### Scenario: Listener khởi tạo lỗi sau khi bind
- **WHEN** tạo authorize URL hoặc bàn giao listener thất bại sau khi bind socket
- **THEN** hệ thống đóng socket và không để lại listener mồ côi

### Requirement: Callback OAuth dùng cùng loopback endpoint
Hệ thống SHALL dùng một địa chỉ loopback và callback path nhất quán cho bind listener và OAuth redirect URI.

#### Scenario: OAuth redirect tới listener
- **WHEN** authorize URL được tạo
- **THEN** redirect URI trỏ đúng host, port và path mà listener đang lắng nghe

### Requirement: Khởi tạo kết nối dùng request có chủ đích
Hệ thống SHALL khởi tạo OAuth connect bằng HTTP method không an toàn để browser prefetch không tự mở listener.

#### Scenario: Browser prefetch trang kết nối
- **WHEN** browser prefetches trang hiển thị AI connection
- **THEN** hệ thống không mở callback listener hoặc bắt đầu OAuth flow

### Requirement: AI connection chỉ được dùng khi usable
Hệ thống SHALL chỉ gọi provider khi connection có status connected và access token hiện hữu; khi cần refresh, phải có refresh token hợp lệ.

#### Scenario: Connection disconnected hoặc thiếu access token
- **WHEN** Test Connection được gọi cho connection disconnected hoặc thiếu access token
- **THEN** hệ thống không gọi provider và báo cần kết nối lại

#### Scenario: Token cần refresh nhưng thiếu refresh token
- **WHEN** access token cần refresh nhưng refresh token không tồn tại
- **THEN** hệ thống đánh dấu connection disconnected, không gửi prompt bằng token cũ và yêu cầu kết nối lại

### Requirement: Refresh token được tuần tự hóa
Hệ thống SHALL tuần tự hóa refresh cho cùng một connection và SHALL lưu token rotation thành công nguyên tử.

#### Scenario: Hai request cùng cần refresh
- **WHEN** nhiều request đồng thời thấy cùng access token cần refresh
- **THEN** một request refresh; request tiếp theo đọc lại connection mới nhất và không tái sử dụng refresh token cũ

#### Scenario: Refresh bị provider từ chối
- **WHEN** provider xác nhận refresh token không hợp lệ hoặc đã bị revoke
- **THEN** hệ thống đánh dấu connection disconnected và yêu cầu kết nối lại

#### Scenario: Refresh lỗi transport tạm thời
- **WHEN** refresh thất bại do timeout hoặc lỗi kết nối không xác nhận credential bị revoke
- **THEN** hệ thống trả lỗi thao tác thân thiện, giữ nguyên credential và status hiện có, không gửi prompt bằng token đã hết hạn

#### Scenario: Refresh thành công
- **WHEN** provider trả access token và refresh token mới
- **THEN** hệ thống lưu cả hai token mới cùng thời hạn mới trước khi gửi request gốc đúng một lần

### Requirement: Account context dùng trong request phải đáng tin cậy
Hệ thống SHALL chỉ dùng `chatgpt_account_id` cho request provider sau khi xác minh nguồn token và các claim định danh cần thiết.

#### Scenario: ID token hợp lệ
- **WHEN** callback nhận ID token có chữ ký hợp lệ, claim hợp lệ và audience khớp client
- **THEN** hệ thống lưu account context đã xác minh và hoàn tất kết nối

#### Scenario: ID token không hợp lệ hoặc thiếu account ID
- **WHEN** token không xác minh được hoặc không có account ID cần thiết
- **THEN** hệ thống không lưu account context không đáng tin cậy và báo kết nối không hoàn tất

### Requirement: Test Connection xác nhận response hoàn chỉnh
Hệ thống SHALL coi Test Connection thành công khi nhận response stream hoàn chỉnh có output text không rỗng.

#### Scenario: Codex trả response hoàn chỉnh có text
- **WHEN** provider stream kết thúc thành công và có output text
- **THEN** hệ thống hiển thị nội dung thật và báo Test Connection thành công

#### Scenario: Stream rỗng, lỗi hoặc không hoàn tất
- **WHEN** response không có text, chứa lỗi hoặc kết thúc trước completion event
- **THEN** hệ thống báo Test Connection thất bại và không hiển thị thành công với response rỗng

#### Scenario: Prompt request gặp lỗi transport
- **WHEN** request prompt gặp timeout hoặc lỗi kết nối
- **THEN** hệ thống trả lỗi thân thiện, không để exception transport thoát khỏi Operation

### Requirement: Thông tin kết nối phản ánh lần kết nối thành công gần nhất
Hệ thống SHALL chỉ phát các trường connection cần cho UI và SHALL cập nhật thời điểm kết nối thành công gần nhất khi OAuth hoàn tất.

#### Scenario: Xem thông tin AI connection
- **WHEN** user xem thông tin connection
- **THEN** response chỉ có status, plan và thời điểm kết nối gần nhất, không có token hoặc account ID

#### Scenario: Kết nối lại thành công
- **WHEN** OAuth reconnect hoàn tất thành công
- **THEN** thời điểm kết nối gần nhất được cập nhật

#### Scenario: Kết nối lại thất bại
- **WHEN** OAuth reconnect thất bại
- **THEN** thời điểm kết nối thành công gần nhất không đổi

### Requirement: Provider-specific behavior được cô lập
Hệ thống SHALL cho AI Operations sử dụng một provider contract chung; POC hiện thực Codex adapter và mỗi user chỉ có một connection hoạt động tại một thời điểm.

#### Scenario: Test Connection qua Codex adapter
- **WHEN** POC thực hiện Test Connection
- **THEN** Operation gọi contract provider chung và Codex adapter xử lý giao tiếp Codex-specific

#### Scenario: Thêm provider trong tương lai
- **WHEN** một provider khác được thêm ngoài scope POC
- **THEN** provider-specific OAuth, refresh và prompt behavior được thêm sau contract mà không đưa logic provider vào AI Operations

### Requirement: Credential không bị lộ
Hệ thống SHALL không ghi raw token vào log và không trả token hoặc account ID qua serializer/UI.

#### Scenario: Ghi log hoạt động provider
- **WHEN** hệ thống log OAuth, refresh hoặc prompt request
- **THEN** log không chứa access token, refresh token hoặc ID token
