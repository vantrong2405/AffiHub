# Proposal

## Precondition

**Code gate (đủ để BẮT ĐẦU viết task code/test của change này):**
- Change `04` đã hoàn tất mọi task TRỪ nhóm "Verify thủ công end-to-end" cuối cùng của nó — `Content` (model từ change 01) đã code + RSpec pass. Change `05` dùng `FactoryBot.create(:content, :approved)` trong RSpec của chính nó, KHÔNG phụ thuộc Content thật đã generate từ Codex để code/test. Facebook Developer App/Meta App Review chưa sẵn sàng kịp lúc cũng KHÔNG chặn việc bắt đầu code change `05` (Client/Operation/RSpec stub) — chỉ nên bắt đầu task 3.x "Facebook App credential config" sớm song song nếu đăng ký app mất thời gian.

**Archive gate (chỉ archive change `04`, hoặc coi change `04` "xong hẳn", khi đủ):**
- Change `04` đã ở trạng thái `archived`.
- Task "Verify thủ công" cuối của change `04` đã xác nhận generate Content thật thành công cho ít nhất 1 Product.

## Why

Vertical slice cần đích đăng bài thật: Facebook Page thật mà user quản lý. Change này implement capability `facebook-social-connection` trên model khung `SocialConnection`/`SocialDestination` đã tạo ở change `01`.

## What Changes

- Đọc source thật `gitroomhq/postiz-app` (SocialConnection/SocialDestination pattern) + `thenavidm/facebook-mcp` (Meta auth/Page discovery/Page token) + Meta Graph API docs hiện hành, viết Porting Note trước khi code.
- Implement Connect Facebook qua Meta OAuth thật (không browser automation).
- Implement Discover Page thật qua Meta Graph API.
- Implement Sync SocialDestination khi user chọn Page, lưu Page token riêng.
- Chuẩn bị association `SocialDestination` ↔ `Publication` (validation Publication phải có SocialDestination là của change `06-poc-publication-workflow`, nơi model `Publication` thật sự được implement — xem Decision 3 trong `design.md`).
- Implement UI Social Connections + Facebook Pages.
- **BREAKING**: không áp dụng.

## Capabilities

### New Capabilities

- `facebook-social-connection`: Connect tài khoản Facebook thật, discover Page thật, quản lý `SocialConnection`/`SocialDestination`, phân biệt destination cụ thể (Facebook Page) với provider chung.

### Modified Capabilities

(không có)

## Impact

- **Code**: `affihub/app/operations/social_connections/*`, `affihub/app/clients/meta_graph_client.rb`, `affihub/config/facebook.yml`, `affihub/app/controllers/social_connections_controller.rb`, `affihub/app/controllers/facebook_pages_controller.rb`, `affihub/app/views/*`.
- **Phụ thuộc**: change `01` (model khung `SocialConnection`/`SocialDestination`).
- **Hệ thống ngoài**: Meta Graph API thật, cần Facebook Developer App (app id/secret) — đã xác nhận với user: cần đăng ký trước khi bắt đầu change này.
