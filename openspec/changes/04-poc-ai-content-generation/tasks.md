# Tasks

## 1. Migration bổ sung (body đã chốt 1 cột — xem design.md Decision 4)

- [ ] 1.1 Viết `spec/models/content_spec.rb` bổ sung assertion cho cột `body` (text, 1 cột duy nhất — không tách hook/caption/cta/hashtags) và `generation_count` (integer, default 0, tăng mỗi lần Regenerate), chạy fail nếu cột chưa có
- [ ] 1.2 Thêm migration tương ứng (`add_column :contents, :generation_count, :integer, default: 0, null: false` nếu `body` đã có từ change 01; `add_index :contents, :product_id, unique: true` — 1 Product tối đa 1 Content, xem design.md Decision 5 — nếu index chưa có từ change 01) để spec 1.1 pass, verify: spec pass

## 2. Generate Content

- [ ] 2.1 Viết `spec/operations/contents/build_prompt_spec.rb` (build prompt đúng từ Product facts + tone, không chèn affiliate_url vào prompt gửi AI), chạy fail
- [ ] 2.2 Implement `app/operations/contents/build_prompt.rb` để spec 2.1 pass, verify: spec pass
- [ ] 2.3 Viết `spec/operations/contents/generate_operation_spec.rb` (Requirement "Generate Content từ Product facts thật": tạo Content Generated, attach affiliate_url do app gắn, gán `content.user = current_user` — dùng cho ownership check khi tạo Publication ở change 06; gọi `ai_connection.ensure_fresh_token!` TRƯỚC `send_prompt` — xem change 02 Decision 3b; case Product đã có Content (bất kỳ status): Generate SHALL reject, KHÔNG tạo Content thứ hai, trả lỗi rõ ràng — xem design.md Decision 5), chạy fail
- [ ] 2.4 Implement `app/operations/contents/generate_operation.rb` (dùng `CodexClient#send_prompt` từ change 02, set `user: current_user`, gọi `ensure_fresh_token!` trước khi gọi `send_prompt`) để spec 2.3 pass, verify: spec pass
- [ ] 2.5 Viết `spec/operations/contents/generate_operation_spec.rb` bổ sung case lỗi/timeout Codex (Requirement "Generate Content từ Product facts thật" - scenario lỗi), chạy fail
- [ ] 2.6 Implement error handling để spec 2.5 pass, verify: spec pass
- [ ] 2.6b Viết `spec/operations/contents/generate_operation_spec.rb` bổ sung case `ensure_fresh_token!` raise `AIConnectionDisconnectedError` (AIConnection từ change 02) → Operation KHÔNG tạo Content, KHÔNG gọi `send_prompt`, trả lỗi "Codex đã mất kết nối", chạy fail
- [ ] 2.6c Implement bắt `AIConnectionDisconnectedError` trong `generate_operation.rb` (convert thành `errors`, không để leak, không tiếp tục gọi `send_prompt`) để spec 2.6b pass, verify: spec pass
- [ ] 2.7 Viết `spec/models/content_spec.rb` cho transition `start_review!` (generated→review hợp lệ; gọi lại khi không ở generated → raise/false) (Requirement "Lifecycle Content Generated → Review → Approved" - scenario tự động chuyển), chạy fail
- [ ] 2.8 Implement `start_review!` trong `app/models/content.rb` để spec 2.7 pass, verify: spec pass
- [ ] 2.9 Viết `spec/operations/contents/generate_operation_spec.rb` bổ sung assertion: sau khi `generate_operation` chạy xong, `content.status` là `review` (không dừng ở `generated`), chạy fail
- [ ] 2.10 Implement `generate_operation.rb` bọc `Content.create! + start_review!` trong 1 `ActiveRecord::Base.transaction` (Requirement "Lifecycle Content Generated → Review → Approved": `Generated` là transient, không để Content kẹt ở `generated` nếu `start_review!` lỗi — transaction rollback toàn bộ, operation trả thất bại) để spec 2.9 pass, verify: spec pass

## 3. Lifecycle Review → Approved/Reject + Edit (Approve/Reject/Edit chỉ hợp lệ ở Review)

- [ ] 3.1 Viết `spec/models/content_spec.rb` bổ sung transition `approve!`/`reject!` chỉ hợp lệ từ `review` (gọi từ `generated`/`approved`/`rejected` → reject, không đổi trạng thái) (Requirement "Lifecycle Content Generated → Review → Approved" - scenario Approve/Reject/Edit khi chưa ở Review), chạy fail
- [ ] 3.2 Implement transition method trong `app/models/content.rb` để spec 3.1 pass, verify: spec pass
- [ ] 3.3 Viết `spec/operations/contents/update_operation_spec.rb` (Requirement "Edit Content chỉ sửa nội dung, không sửa Product/affiliate_url": chỉ hợp lệ ở review, cập nhật `body`, bỏ qua `affiliate_url`/`product_id` nếu client gửi kèm, reject khi không ở review), chạy fail
- [ ] 3.4 Implement `app/forms/contents/update_form.rb` (chỉ permit `body`) + `app/operations/contents/update_operation.rb` để spec 3.3 pass, verify: spec pass

## 4. Regenerate (hợp lệ ở Review và Rejected)

- [ ] 4.1 Viết `spec/operations/contents/regenerate_operation_spec.rb` (Requirement "Regenerate không đổi Product facts hoặc affiliate URL": giữ nguyên product_id/affiliate_url, ghi đè `body` trên cùng row — không tạo Content mới, tăng `generation_count`; Requirement "Lifecycle..." scenario Regenerate từ Rejected: chuyển rejected→review; scenario Regenerate khi Generated/Approved: reject thao tác), chạy fail
- [ ] 4.2 Implement `app/operations/contents/regenerate_operation.rb` (cho phép khi `review` hoặc `rejected`, gọi `start_review!` nếu đang `rejected`, gọi `ai_connection.ensure_fresh_token!` trước khi gọi `send_prompt` — giống `generate_operation`, bắt `AIConnectionDisconnectedError` giống task 2.6c, không ghi đè `body` nếu refresh thất bại) để spec 4.1 pass, verify: spec pass

## 5. Lọc URL lạ từ AI

- [ ] 5.1 Viết `spec/operations/contents/generate_operation_spec.rb` bổ sung case response chứa URL khác affiliate_url (Requirement "AI không được invent facts hoặc tự publish"), chạy fail
- [ ] 5.2 Implement filter URL trong `generate_operation.rb`/`regenerate_operation.rb` (helper dùng chung) để spec 5.1 pass, verify: spec pass

## 6. UI Generate Content + Content Review

- [ ] 6.1 Viết `spec/requests/contents_spec.rb` (generate, show review, update/edit, approve, reject, regenerate kể cả từ rejected), chạy fail
- [ ] 6.2 Dùng skill `ui-ux` để quyết định layout/component/token màu cho Generate Content form và Content Review trước khi viết view; implement `app/controllers/contents_controller.rb` + `resources :contents` route + views (Generate Content form; Content Review với Preview/Edit/Regenerate/Approve/Reject). Các action create/update/regenerate/approve/reject dùng `render_operation`; action show read-only gọi Operation rồi render view trực tiếp, không query Model trong Controller; để spec 6.1 pass, verify: spec pass + `rtk bin/dev` thao tác được trên UI
- [ ] 6.3 Thêm nút CTA "Generate Content" vào `app/views/products/show.html.erb` (đã tạo ở change 03 task 5.2, không có CTA) trỏ `new_content_path(product_id:)` — route này giờ đã tồn tại (task 6.2), verify: `rtk bin/dev` bấm CTA từ Product Detail sang Generate Content form hoạt động đúng, không lỗi `undefined method` route helper

## 7. Verify thủ công end-to-end phase này

- [ ] 7.1 Generate content thật bằng Codex credential thật cho 1 Product thật đã import ở change 03, verify: affiliate_url trong Content đúng bằng affiliate_url của Product
- [ ] 7.2 Chạy `RAILS_ENV=test rtk bundle exec rspec spec/operations/contents spec/models/content_spec.rb spec/requests/contents_spec.rb`, verify: pass 100%
