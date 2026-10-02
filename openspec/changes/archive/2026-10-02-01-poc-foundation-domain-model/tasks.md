# Tasks

## 1. Concern response chung cho mọi HTML Controller (`OperationRenderable`)

- [x] 1.1 Viết `spec/controllers/concerns/operation_renderable_spec.rb` (dùng 1 dummy controller test): `render_operation(operator, success:, notice:)` khi `operator.success?` true → redirect tới `success` kèm `flash[:notice]`; khi false → `flash.now[:alert]` = `operator.errors.full_messages.to_sentence` (hoặc `alert:` override), render action mặc định theo `action_name` (`:new` cho create, `:edit` cho update, `action_name.to_sym` còn lại) hoặc `failure:` override, status `:unprocessable_entity`, chạy fail
- [x] 1.2 Implement `app/controllers/concerns/operation_renderable.rb` (`render_operation(operator, success:, failure: nil, notice: nil, alert: nil)`), include vào `MainController` để mọi Controller HTML (và API nếu cần) đều có sẵn, để spec 1.1 pass, verify: spec pass

## 2. Login tối thiểu

- [x] 2.1 Bỏ comment gem `bcrypt` trong `Gemfile`, chạy `rtk bundle install`, verify: `bundle check` pass
- [x] 2.2 Viết `spec/models/user_spec.rb` (password set/authenticate qua `has_secure_password`, email presence/uniqueness), chạy `RAILS_ENV=test rtk bundle exec rspec spec/models/user_spec.rb` fail (red)
- [x] 2.3 Tạo `db/migrate/..._create_users.rb` + `app/models/user.rb` để spec 2.2 pass, verify: spec xanh (green)
- [x] 2.4 Viết `spec/requests/sessions_spec.rb` (POST /login thành công tạo session, sai password trả lỗi, DELETE /logout xoá session), chạy fail
- [x] 2.5 Thêm route `get "login"`, `post "login"`, `delete "logout"` vào `config/routes.rb`; dùng skill `ui-ux` để quyết định layout/token màu cho form login trước khi viết `app/views/sessions/new.html.erb`; implement `app/controllers/sessions_controller.rb` + `app/forms/session_form.rb` + `app/operations/sessions/authenticate_operation.rb` (theo HMVC layer, dùng `render_operation` từ concern 1.2 thay vì tự viết if/else) để spec 2.4 pass, verify: spec pass + `rtk bin/dev` login/logout thủ công qua browser thành công
- [x] 2.6 Viết `spec/controllers/application_controller_spec.rb` (`current_user` đọc `User.find_by(id: session[:user_id])`, memoize; `require_login` before_action redirect `login_path` khi `current_user` nil), chạy fail. Implement `current_user`/`require_login` trong `app/controllers/application_controller.rb`, `AuthenticateOperation` (task 2.5) set `session[:user_id]` lúc login thành công và xoá lúc logout; mọi Controller gọi Operation từ đây trở đi PHẢI merge `current_user:` vào params truyền cho Operation (vd `operator = SomeOperation.call(params: params.to_unsafe_h.merge(current_user:))`) — ghi convention này vào `affihub/CLAUDE.md` để các change 02–07 tuân theo, verify: spec pass

## 3. Active Record Encryption

- [x] 3.1 Chạy `rtk bin/rails db:encryption:init`, verify: 3 key (primary_key/deterministic_key/key_derivation_salt) được thêm vào `config/credentials.yml.enc`
- [x] 3.2 Verify: `bin/rails runner "puts ActiveRecord::Encryption.config.primary_key.present?"` trả `true`

## 4. Model `AIConnection` (khung rỗng)

- [x] 4.1 Viết `spec/models/ai_connection_spec.rb` (`belongs_to :user`, unique index `user_id` (1 user 1 AIConnection trong POC), `encrypts :access_token, :refresh_token`, cột `access_token_expires_at` (datetime, không mã hoá — không nhạy cảm, chỉ để tính refresh trigger ở change 02), enum status connected/disconnected, giá trị DB là ciphertext không phải plaintext), chạy fail
- [x] 4.2 Tạo `db/migrate/..._create_ai_connections.rb` (kèm `add_index :ai_connections, :user_id, unique: true`) + `app/models/ai_connection.rb` để spec 4.1 pass, verify: spec pass

## 5. Model `AffiliateConnection` + `Product` (khung rỗng) — `affiliate_provider` là STRING, không phải model/FK riêng

- [x] 5.1 Viết `spec/models/affiliate_connection_spec.rb` (`belongs_to :user`, cột `provider` string (vd `"accesstrade"` — KHÔNG tạo model `AffiliateProvider` riêng: POC khoá cứng đúng 1 affiliate provider vĩnh viễn — xem `docs/PROJECT_SPEC.md` Non-Goal — 1 bảng catalog cho 1 giá trị không bao giờ đổi là over-engineering, `PROJECT_SPEC.md` dòng field conceptual của `Product` cũng định nghĩa `affiliate_provider` là field thường, không phải quan hệ), credential mã hoá), chạy fail
- [x] 5.2 Tạo migration + `app/models/affiliate_connection.rb` để spec 5.1 pass, verify: spec pass
- [x] 5.3 Viết `spec/models/product_spec.rb` (đủ field conceptual: `affiliate_provider` (string, vd `"accesstrade"` — không FK), source_product_id, merchant, title, description, images, price, original_price, discount, category, rating, sold, commission, original_product_url, affiliate_url, raw_source_data, last_synced_at — field thiếu nullable; unique index `(affiliate_provider, source_product_id)` chống trùng khi re-import — cả 2 cột đều string/scalar, không phải FK), chạy fail
- [x] 5.4 Tạo `db/migrate/..._create_products.rb` (`affiliate_provider:string`, kèm `add_index :products, [:affiliate_provider, :source_product_id], unique: true`) + `app/models/product.rb` để spec 5.3 pass, verify: spec pass

## 6. Model `SocialConnection`/`SocialDestination` (khung rỗng)

- [x] 6.1 Viết `spec/models/social_connection_spec.rb` (`belongs_to :user`, provider=facebook, token mã hoá, unique index `(user_id, provider)`) + `spec/models/social_destination_spec.rb` (reference SocialConnection, type=page, page token riêng mã hoá, unique index `(social_connection_id, page_id)` chống sync trùng 1 Page nhiều lần), chạy fail
- [x] 6.2 Tạo migration (kèm 2 unique index trên) + `app/models/social_connection.rb` + `app/models/social_destination.rb` để spec 6.1 pass, verify: spec pass

## 7. Model `Content` (khung rỗng)

- [x] 7.1 Viết `spec/models/content_spec.rb` (product association, `belongs_to :user` — ai là người bấm Generate Content, dùng cho ownership check khi tạo Publication ở change 06, enum status generated/review/approved, cột affiliate_url), chạy fail
- [x] 7.2 Tạo `db/migrate/..._create_contents.rb` + `app/models/content.rb` để spec 7.1 pass, verify: spec pass

## 8. Model `Publication` (khung rỗng)

- [x] 8.1 Viết `spec/models/publication_spec.rb` (content_id, social_destination_id, enum status draft/scheduled/publishing/published/failed, scheduled_at, provider_post_id, published_url, published_at, error_code, error_message, attempt_count, last_attempt_at, provider_metadata), chạy fail
- [x] 8.2 Tạo `db/migrate/..._create_publications.rb` + `app/models/publication.rb` để spec 8.1 pass, verify: spec pass

## 8b. Bootstrap user đầu tiên (không có signup — POC chỉ 1 user)

- [x] 8b.1 Thêm `db/seeds.rb` tạo 1 `User` qua `User.find_or_create_by!`: đọc `ENV["SEED_USER_EMAIL"]`/`ENV["SEED_USER_PASSWORD"]`; nếu `Rails.env.production?` và 1 trong 2 ENV chưa set → `raise` ngay, KHÔNG fallback giá trị cố định; chỉ cho phép fallback giá trị dev cố định khi `development`/`test`, verify: `rtk bin/rails db:seed` chạy xong ở development, `User.count == 1`; verify thêm `RAILS_ENV=production rtk bin/rails db:seed` (không set ENV) raise lỗi rõ ràng thay vì tạo user mật khẩu mặc định
- [x] 8b.2 Ghi credential seed user (email/password) vào `affihub/docs/architecture/OVERVIEW.md` hoặc README nội bộ để người verify thủ công (task 2.5, và các "Verify thủ công" ở change 02–07) biết đăng nhập bằng gì

## 9. Verify toàn bộ nền tảng

- [x] 9.1 Chạy `RAILS_ENV=test rtk bundle exec rspec spec/models spec/requests spec/controllers/concerns`, verify: toàn bộ pass, 0 pending/skip
- [x] 9.2 Chạy `rtk bin/rubocop` + `rtk bin/brakeman`, verify: không lỗi mới
- [x] 9.3 `rtk bin/rails db:migrate` trên `affihub_development`, verify: `rtk bin/rails db:prepare` idempotent không lỗi
