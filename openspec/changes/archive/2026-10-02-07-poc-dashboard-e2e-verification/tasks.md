# Tasks

## 1. Xác nhận tiền đề

- [x] 1.1 Chạy `openspec list --all --json`, xác nhận change `01`–`06` đều có trạng thái archived; nếu còn change nào `in-progress` hoặc `complete` nhưng chưa archive thì dừng, chưa bắt đầu code Dashboard

## 2. Dashboard

- [x] 2.1 Viết `spec/operations/dashboard/build_status_operation_spec.rb` (trả đúng AIConnection/AffiliateConnection/SocialConnection + 10 Publication gần nhất **của `current_user`** — không dùng `Model.last`; seed thêm data của user khác trong spec để xác nhận không lẫn), chạy fail
- [x] 2.2 Implement `app/operations/dashboard/build_status_operation.rb` để spec 2.1 pass, verify: spec pass
- [x] 2.3 Viết `spec/requests/dashboard_spec.rb` (hiển thị status Codex/ACCESSTRADE/Facebook connected + recent publications), chạy fail
- [x] 2.4 Thêm route `root "dashboard#show"` vào `config/routes.rb`. Dùng skill `ui-ux` để quyết định layout/component/token màu cho trang Dashboard trước khi viết view; implement `app/controllers/dashboard_controller.rb#show` (chỉ gọi `BuildStatusOperation`, không tự query model; đây là read-only action nên render view trực tiếp khi thành công; nếu Operation lỗi thì dùng `render_operation` với failure action `:show`) + view để spec 2.3 pass, verify: request spec pass + `rtk bin/dev` Dashboard hiển thị đúng trạng thái thật sau khi connect ở các change trước

## 3. Verify toàn bộ test suite + lint

- [x] 3.1 Chạy `RAILS_ENV=test rtk bundle exec rspec spec/models spec/forms spec/operations spec/clients spec/publishers spec/jobs spec/serializers spec/requests`, verify: pass 100%, 0 pending/skip
- [x] 3.2 Chạy `rtk bin/rubocop`, `rtk bin/brakeman`, `rtk bin/bundler-audit`, verify: không lỗi mới phát sinh từ toàn bộ vertical slice

## 4. Verify thủ công toàn chuỗi 34-bước DoD

- [ ] 4.1 Verify thủ công theo đúng 34 bước liệt kê tại `docs/PROJECT_SPEC.md` §POC Definition of Done (login → connect Codex thật → test prompt thật → connect ACCESSTRADE thật → import Product thật → filter/score → chọn Product → generate Content thật → review/edit/regenerate → approve → connect Facebook thật → discover Page thật → chọn Page → tạo Publication → Post Now hoặc Schedule → background job chạy → PublisherResolver → MetaGraphPublisher → Facebook nhận post thật → provider_post_id/published_at/metadata thật lưu đúng → bước 33: demo chính PHẢI đạt status Published thật ít nhất 1 lần — Failed thật chỉ chấp nhận làm bằng chứng cho case lỗi provider ở lần thử phụ, KHÔNG thay thế được bước 33 của demo chính). Ghi kết quả verify (từng bước 1-34 Pass/Fail + ảnh chụp/link bài Facebook thật) vào `affihub/docs/verification/dod-evidence.md` (tạo file này) — DoD SHALL chỉ coi Done khi toàn bộ 34 bước đều Pass thật (không chấp nhận partial/skip, không chấp nhận hoàn tất mà chưa từng đăng Published thật), không coi Done nếu chỉ từng phần chạy riêng lẻ
