# Proposal

## Why

`affihub` hiện là scaffold Rails 8.1.3 trống — chưa có migration, model, hay auth nào. Toàn bộ vertical slice POC (`docs/PROJECT_SPEC.md`) build trên 7 domain object cốt lõi (`User`, `AIConnection`, affiliate Provider/Connection + `Product`, `SocialConnection`/`SocialDestination`, `Content`, `Publication`) và cần 1 cơ chế login tối thiểu để phân biệt session trước khi connect provider thật. Đây là change đầu tiên trong chuỗi 7 change tuần tự (01→07, mỗi change archive xong mới sang change sau) — không có change nào sau có thể bắt đầu nếu bảng/model nền tảng chưa tồn tại.

## What Changes

- Thêm migration + model `User` (password_digest qua `has_secure_password`), login/logout session-based tối thiểu.
- Bật Active Record Encryption (`bin/rails db:encryption:init`) làm cơ chế mã hoá credential dùng chung cho mọi model có token nhạy cảm ở các change sau.
- Thêm migration + model `AIConnection` (khung rỗng: user association + cột token mã hoá + trạng thái connected/disconnected) — nội dung OAuth/PKCE thật nằm ở change `02-poc-ai-connection-codex-auth`, change này chỉ tạo bảng/model structure.
- Thêm migration + model cho affiliate Provider/Connection + `Product` (đủ field conceptual theo `docs/PROJECT_SPEC.md`, field thiếu nullable) — logic import/filter/score nằm ở change `03`.
- Thêm migration + model `SocialConnection`/`SocialDestination` (khung rỗng) — logic connect/discover nằm ở change `05`.
- Thêm migration + model `Content` (khung lifecycle) — logic generate/review nằm ở change `04`.
- Thêm migration + model `Publication` (khung lifecycle) — logic publish nằm ở change `06`.
- **BREAKING**: không áp dụng (dự án scaffold trống).

## Capabilities

### New Capabilities

(không có — change này thuần migration/model/login, không có spec-level behavior mới ngoài login tối thiểu; `skip_specs: true` đã khai báo trong `.openspec.yaml` vì login chỉ là access-control tối thiểu, không phải capability nghiệp vụ của POC)

### Modified Capabilities

(không có)

## Impact

- **Code**: `affihub/db/migrate/*`, `affihub/app/models/*`, `affihub/app/controllers/sessions_controller.rb` (+ Form/Operation theo HMVC), `affihub/config/credentials.yml.enc` (encryption key), `affihub/Gemfile` (bỏ comment `bcrypt`).
- **Dependencies**: `bcrypt` (đã có sẵn trong Gemfile, chỉ cần bỏ comment).
- **Phụ thuộc change sau**: change `02`–`07` đều cần bảng/model của change này tồn tại trước; thứ tự archive phải đúng 01 trước.
- **Quy tắc thứ tự**: mặc định archive change N xong mới code change N+1. Một số change (`02`–`06`) định nghĩa thêm Precondition riêng (code gate/archive gate) cho phép BẮT ĐẦU CODE sớm hơn (khi dependency chỉ cần model/code tồn tại, chưa cần phần "Verify thủ công" cuối đã archive) — các Precondition đó CHỈ nới cho việc code/test bằng stub, KHÔNG nới cho việc archive: archive 1 change vẫn luôn yêu cầu change ngay trước nó đã archived thật (xem Precondition cụ thể từng change, vd change `03`/`04`).
