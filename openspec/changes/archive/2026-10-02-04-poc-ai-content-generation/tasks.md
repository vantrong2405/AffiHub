# Tasks

## 1. Migration bổ sung (body đã chốt 1 cột — xem design.md Decision 4)

- [x] 1.1 Viết `spec/models/content_spec.rb` assertion `body` là cột `text` duy nhất cho copy (không có cột riêng `hook`/`caption`/`cta`/`hashtags`), `generation_count` là integer mặc định 0, `Product has_many :contents`, và index `product_id` không unique (có thể lưu nhiều Content cho cùng Product); chạy fail nếu schema chưa đúng. Việc counter tăng mỗi lần Regenerate được kiểm tra ở task 4.1.
- [x] 1.2 Sau khi qua code gate change `03`, thêm migration chỉ bổ sung `generation_count` (`integer`, `default: 0`, `null: false`). Giữ index `contents.product_id` thường ngay từ migration tạo bảng; không tạo unique index rồi thêm migration sửa lại. Cập nhật `Product` thành `has_many :contents` và bỏ validation/constraint một-một nếu có. Verify: spec 1.1 pass.

## 2. Generate Content

- [x] 2.1 Viết `spec/operations/contents/build_prompt_spec.rb` (build prompt đúng từ Product facts + tone, không chèn affiliate_url vào prompt gửi AI), chạy fail
- [x] 2.2 Implement `app/operations/contents/build_prompt.rb` để spec 2.1 pass, verify: spec pass
- [x] 2.3 Viết `spec/operations/contents/generate_operation_spec.rb` (Requirement "Generate Content từ Product facts thật" và "Một Product có thể có nhiều Content độc lập": chỉ chấp nhận Product thuộc `current_user`; Product user khác bị reject trước provider call; tạo Content row mới ngay cả khi Product đã có Content ở bất kỳ status nào; row mới gắn `product_id`, affiliate_url và `user = current_user`; provider failure không tạo row; gọi provider contract, không truy cập token trực tiếp), chạy fail
- [x] 2.4 Implement `app/operations/contents/generate_operation.rb` gọi provider contract của change 02 (không gọi `CodexClient` trực tiếp, không quản lý token), set `user: current_user`; verify: spec 2.3 pass
- [x] 2.5 Viết `spec/operations/contents/generate_operation_spec.rb` cho credential invalid/disconnected và lỗi timeout/transport tạm thời; xác nhận Content không được tạo và thông báo hướng dẫn reconnect hoặc retry tương ứng; chạy fail
- [x] 2.6 Ánh xạ lỗi provider thành thông báo hành động phù hợp để spec 2.5 pass; không để lỗi transport leak ra controller, verify: spec pass
- [x] 2.7 Viết `spec/models/content_spec.rb` cho transition `start_review!` (generated/rejected→review hợp lệ; gọi từ trạng thái khác → raise/false) (Requirement "Lifecycle Content Generated → Review → Approved" - scenario tự động chuyển và Regenerate từ Rejected), chạy fail
- [x] 2.8 Implement `start_review!` trong `app/models/content.rb` để spec 2.7 pass, verify: spec pass
- [x] 2.9 Viết `spec/operations/contents/generate_operation_spec.rb` bổ sung assertion: sau khi `generate_operation` chạy xong, `content.status` là `review` (không dừng ở `generated`), chạy fail
- [x] 2.10 Implement `generate_operation.rb` bọc `Content.create! + start_review!` trong 1 `ActiveRecord::Base.transaction` (Requirement "Lifecycle Content Generated → Review → Approved": `Generated` là transient, không để Content kẹt ở `generated` nếu `start_review!` lỗi — transaction rollback toàn bộ, operation trả thất bại) để spec 2.9 pass, verify: spec pass

## 3. Lifecycle Review → Approved/Reject + Edit (Approve/Reject/Edit chỉ hợp lệ ở Review)

- [x] 3.1 Viết `spec/models/content_spec.rb` bổ sung transition `approve!`/`reject!` chỉ hợp lệ từ `review` (gọi từ `generated`/`approved`/`rejected` → reject, không đổi trạng thái) (Requirement "Lifecycle Content Generated → Review → Approved" - scenario Approve/Reject/Edit khi chưa ở Review), chạy fail
- [x] 3.2 Implement transition method trong `app/models/content.rb` để spec 3.1 pass, verify: spec pass
- [x] 3.3 Viết `spec/operations/contents/update_operation_spec.rb` (Requirement "Edit Content chỉ sửa nội dung, không sửa Product/affiliate_url": chỉ hợp lệ ở review, cập nhật `body`, bỏ qua `affiliate_url`/`product_id` nếu client gửi kèm, reject khi không ở review), chạy fail
- [x] 3.4 Implement `app/forms/contents/update_form.rb` (chỉ permit `body`) + `app/operations/contents/update_operation.rb` để spec 3.3 pass, verify: spec pass

## 4. Regenerate (hợp lệ ở Review và Rejected)

- [x] 4.1 Viết `spec/operations/contents/regenerate_operation_spec.rb` (Regenerate giữ nguyên `product_id`/affiliate_url, ghi đè `body` trên cùng row và tăng `generation_count`; Regenerate từ Rejected chuyển rejected→review; Regenerate khi Generated/Approved bị từ chối; provider failure giữ nguyên Content; thay đổi row này không ảnh hưởng Content khác cùng Product hoặc Publication đã tạo), chạy fail
- [x] 4.2 Implement `app/operations/contents/regenerate_operation.rb` gọi provider contract của change 02; cho phép khi `review` hoặc `rejected`, gọi `start_review!` nếu đang `rejected`, không gọi Codex adapter hoặc token refresh trực tiếp; verify: spec 4.1 pass

## 5. Bảo vệ affiliate URL khỏi URL do AI sinh

- [x] 5.1 Viết `spec/operations/contents/generate_operation_spec.rb` bổ sung case response chứa URL khác affiliate_url (xác nhận app chỉ giữ URL gốc do Product cung cấp; đây không phải kiểm tra độ đúng của claim văn bản), chạy fail
- [x] 5.2 Implement filter URL trong `generate_operation.rb`/`regenerate_operation.rb` (helper dùng chung) để spec 5.1 pass, verify: spec pass

## 6. UI Generate Content + Content Review

- [x] 6.1 Viết `spec/requests/contents_spec.rb` (generate nhiều Content cho cùng Product, index/list Content theo Product, show review, update/edit, approve, reject, regenerate kể cả từ rejected; kiểm tra thao tác một Content không đổi Content khác), chạy fail
- [x] 6.2 Dùng skill `ui-ux` để quyết định layout/component/token màu cho Generate Content form và Content Review trước khi viết view; implement `app/controllers/contents_controller.rb` + `resources :contents` route + views (Generate Content form; danh sách Content theo Product; Content Review với Preview/Edit/Regenerate/Approve/Reject). Các action create/update/regenerate/approve/reject dùng `render_operation`; action show/index gọi Operation rồi render view trực tiếp, không query Model trong Controller; verify: request specs pass, `rtk bin/dev` boot và thao tác browser qua Product Detail → Generate form → Content list → Review; Codex generation thật thuộc task 7.1
- [x] 6.3 Thêm nút CTA "Generate Content" vào `app/views/products/show.html.erb` trỏ `new_content_path(product_id:)`; verify route helper resolve được và `rtk bin/dev` chạy

## 7. Verify thủ công end-to-end phase này

- [ ] 7.1 Generate content thật bằng Codex credential thật cho 1 Product thật đã import ở change 03, verify: affiliate_url trong Content đúng bằng affiliate_url của Product
- [x] 7.2 Chạy `RAILS_ENV=test rtk bundle exec rspec spec/operations/contents spec/models/content_spec.rb spec/requests/contents_spec.rb`, verify: pass 100%; đây chỉ xác nhận change 04, không thay thế demo end-to-end 34 bước ở change 07
