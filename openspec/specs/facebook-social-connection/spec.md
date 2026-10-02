# facebook-social-connection Specification

## Purpose
Kết nối tài khoản Facebook thật của user, discover Facebook Page thật mà user quản lý, và quản lý các Page đó như `SocialDestination` cụ thể để publication có thể reference đúng đích đăng bài.

## Requirements

### Requirement: Connect Facebook thật qua Meta OAuth
Hệ thống SHALL cho phép user connect tài khoản Facebook qua Meta OAuth thật (không browser automation), lưu `SocialConnection` với user access token mã hoá tại rest. Hệ thống SHALL exchange sang long-lived user token (`grant_type=fb_exchange_token`) ngay sau khi nhận short-lived token từ bước exchange code — chỉ long-lived token mới được lưu, không lưu short-lived token.

#### Scenario: Connect Facebook thành công
- **WHEN** user hoàn tất Meta OAuth consent flow thành công
- **THEN** hệ thống exchange sang long-lived user token, tạo `SocialConnection` (provider=facebook) với long-lived token mã hoá, trạng thái connected

#### Scenario: Exchange long-lived token thất bại
- **WHEN** bước exchange code → short-lived token thành công nhưng bước exchange long-lived token sau đó thất bại
- **THEN** hệ thống không tạo `SocialConnection`, hiển thị lỗi cho user (không lưu short-lived token làm phương án dự phòng)

#### Scenario: User từ chối cấp quyền
- **WHEN** user từ chối cấp quyền trong Meta OAuth consent screen
- **THEN** hệ thống không tạo `SocialConnection`, hiển thị thông báo huỷ kết nối cho user

#### Scenario: State không khớp ở callback
- **WHEN** Meta OAuth callback trả về `state` khác với `state` đã sinh lúc bắt đầu flow
- **THEN** hệ thống từ chối, không exchange token, không tạo `SocialConnection`, hiển thị lỗi cho user

### Requirement: Discover Facebook Page thật
Hệ thống SHALL gọi Meta Graph API thật để lấy danh sách Page mà user quản lý sau khi `SocialConnection` connected, và hiển thị danh sách Page thật đó cho user chọn.

#### Scenario: Discover Page thành công
- **WHEN** `SocialConnection` facebook ở trạng thái connected và user vào màn Facebook Pages
- **THEN** hệ thống gọi Meta Graph API thật, trả danh sách Page thật (tên, id, ảnh đại diện) mà user có quyền quản lý

#### Scenario: User không quản lý Page nào
- **WHEN** Meta Graph API trả danh sách Page rỗng cho user
- **THEN** hệ thống hiển thị trạng thái "không có Page" thay vì tạo SocialDestination giả

### Requirement: Sync SocialDestination cho Page được chọn
Hệ thống SHALL tạo/đồng bộ `SocialDestination` (provider=facebook, type=page) khi user chọn một Page thật từ danh sách discover, lưu Page access token riêng cho destination đó (khác token của SocialConnection cấp user). Hệ thống SHALL KHÔNG tin trực tiếp `page_id` do client gửi lên — chỉ chấp nhận `page_id` khớp với 1 Page nằm trong kết quả discover gần nhất của đúng `SocialConnection` thuộc user hiện tại.

#### Scenario: User chọn Page để làm destination
- **WHEN** user chọn một Page thật trong danh sách discover
- **THEN** hệ thống tạo `SocialDestination` tham chiếu đúng Page id thật, lưu Page token thật dùng riêng để publish sau này

#### Scenario: Client gửi page_id không thuộc danh sách discover của user
- **WHEN** request sync gửi kèm 1 `page_id` không nằm trong kết quả discover gần nhất của `SocialConnection` thuộc user hiện tại (vd user tự sửa param, hoặc page_id thuộc Page của tài khoản Facebook khác)
- **THEN** hệ thống từ chối tạo `SocialDestination`, không gọi Meta Graph API publish permission cho page_id đó
