# Design

## Context

Scaffold Rails trống, dùng `rails_hmvc` (type=api: Controller/Form/Operation/Serializer/Error). Chưa có `bcrypt`, chưa có bất kỳ migration nào. Xem `proposal.md` cho motivation. Đây là change nền cho cả 6 change capability tiếp theo (02–07).

## Goals / Non-Goals

**Goals:**
- Tạo đủ bảng/model để các change capability sau (02–07) có nền tảng để thêm logic/spec riêng mà không phải sửa migration nền tảng.
- Chuẩn hoá cơ chế mã hoá credential (Active Record Encryption) dùng chung cho `AIConnection`, `SocialConnection`, `SocialDestination`.
- Login tối thiểu đủ để demo thao tác UI qua session, không phải hệ thống auth đầy đủ.

**Non-Goals:**
- Không implement logic nghiệp vụ của từng domain object (OAuth flow, import, publish...) — đó là việc của change 02–06.
- Không làm multi-role/permission — POC chỉ có 1 user thao tác.
- Không OmniAuth/SSO.

## Decisions

### 1. Model khung rỗng, không đặt logic nghiệp vụ ở đây
Mỗi model (`AIConnection`, `SocialConnection`, `SocialDestination`, `Content`, `Publication`) chỉ có schema + association + `encrypts`/enum cần thiết để các RSpec spec của chính change này pass (tồn tại, lưu đúng kiểu dữ liệu, mã hoá đúng cột). State machine/transition method thật được thêm dần ở change tương ứng (vd: `Content#approve!` thêm ở change 04, không thêm ở đây) — tránh việc change 01 phải đoán trước business rule chưa rõ.

Alternative: viết luôn full lifecycle method ở change 01 cho gọn. Bị loại vì vi phạm nguyên tắc "port behavior sau khi đọc reference" của `PROJECT_SPEC.md` — change 01 chạy trước khi đọc Porting Note của từng subsystem, nên không nên khoá cứng business rule sớm.

### 2. Active Record Encryption, không gem ngoài
Dùng `encrypts :access_token, :refresh_token` (Rails 8 built-in) cho mọi cột token. Cần `bin/rails db:encryption:init` sinh 3 key (primary/deterministic/key_derivation_salt) vào credentials, chạy 1 lần ở change này, dùng chung cho mọi change sau.

### 3. Login bằng `has_secure_password` + Rails session, không spec riêng
Login không có `openspec/specs/` vì đây là access-control hạ tầng, không phải domain behavior của POC — nhưng vẫn viết RSpec (TDD) vì đây là code thật, chỉ là không cần OpenSpec spec-delta.

### 4. Code convention Operation/Controller — lấy đúng từ gem `rails_hmvc` đã cài (không bịa, không mượn convention từ project khác)
Đã đọc trực tiếp `vendor/bundle/ruby/3.3.0/gems/rails_hmvc-0.1.2` (generator templates thật) để xác nhận convention, áp dụng xuyên suốt mọi change 02–07:

- **Operation**: generate bằng `rails g hmvc:operation <Namespace>::<Name> step_a step_b ...` — class kế thừa `MainOperation`, có sẵn `attr_reader :params, :current_user, :form, :errors`, `self.call(*args)` (classmethod tạo instance rồi gọi `#call`), `success?`/`error?` dựa trên `errors.empty?`. Method chính là `#call` gọi tuần tự các `step_*` private method theo đúng tên được generate — **tên `step_*` phải mô tả hành động cụ thể** (vd `step_validate_params`, `step_load_product`, `step_build_codex_prompt`, `step_create_content!`), không dùng tên mơ hồ (`step_build`, `step_process`, `step_handle`). Operation trong các change 02–07 khi gọi "Implement `app/operations/.../xxx_operation.rb`" SHALL dùng đúng generator này, không tự viết class Operation tay theo convention khác.
- **Controller**: pattern thật trong gem là `operator = XxxOperation.call(params:)` rồi `render_resource`/`render_collection` (JSON, qua `Renderable` concern) nếu API, hoặc `render :action_name` (HTML) nếu web. **Giới hạn quan trọng phải biết trước khi code**: `Renderable`/`Errorable` sinh sẵn trong `app/controllers/concerns/` chỉ xử lý **JSON** (`render json: ...`) — đây là gem cấu hình `type: api` (`config/rails_hmvc.yml`). Các Controller phục vụ UI HTML (SessionsController, ProductsController, ContentsController, AiConnectionsController, SocialConnectionsController, FacebookPagesController, PublicationsController, DashboardController — toàn bộ UI tối thiểu của POC) đều là HTML, không phải JSON API, nên:
  - vẫn gọi `operator = XxxOperation.call(params:)` (giữ nhất quán Controller mỏng, business logic trong Operation),
  - nhưng **tự render HTML view** (`render :index`, `redirect_to ...`) dựa trên `operator.success?`/`operator.errors`, KHÔNG dùng `render_resource`/`render_collection` (các method đó luôn trả JSON, sai content-type cho trang HTML),
  - lỗi không mong đợi (500) ở Controller HTML vẫn rơi vào `Errorable#handle_standard_error` (hiện tại luôn `render json:`) — chấp nhận giới hạn này cho POC (hiển thị JSON thay vì trang lỗi đẹp khi có exception ngoài dự kiến); không build thêm cơ chế error page HTML riêng cho giai đoạn này (over-engineering so với quy mô POC 1 user) — đây là quyết định có chủ đích, không phải thiếu sót.
- **Form**: kế thừa `MainForm` (`ActiveModel::Model` + `Attributes` + `Validations`), có sẵn `#valid!` (raise `Errors::ResourceError` nếu invalid).
- **Không có Query layer riêng** trong `rails_hmvc` — filter/scope dữ liệu (vd Product Library filter ở change `03`) đặt trong model scope hoặc trực tiếp trong Operation, không tạo thư mục `app/queries/*` mới (không có trong contract gem, không cần thêm layer cho khối lượng filter đơn giản của POC).
- **View engine là ERB** (Rails mặc định), không phải Slim — xác nhận `Gemfile.lock` không có gem `slim`. Mọi task "implement views" trong change 02–07 SHALL dùng `.html.erb`, không phải `.html.slim`.

### 5. `OperationRenderable` — concern chung biến `operator.success?`/`errors` thành response, dùng ở mọi HTML Controller
Trước change này, hướng dẫn chỉ nói "Controller tự render/redirect dựa trên `operator.success?`" — mỗi Controller sẽ tự viết `if/else` riêng, dễ lệch format (chỗ dùng `flash[:notice]`, chỗ dùng `flash[:success]`; chỗ trả 422, chỗ quên set status). Fix: thêm 1 concern duy nhất `app/controllers/concerns/operation_renderable.rb`, include vào `MainController` (áp dụng cho mọi Controller kế thừa nó, tức toàn bộ Controller HTML của vertical slice), cung cấp 1 method duy nhất:

```ruby
render_operation(operator, success:, failure: nil, notice: nil, alert: nil)
```

- Thành công (`operator.success?`): `redirect_to success, notice: notice`.
- Thất bại: `flash.now[:alert] = alert || operator.errors.full_messages.to_sentence`, `render (failure || default_action_for(action_name)), status: :unprocessable_entity` — `default_action_for` trả `:new` nếu action hiện tại là `create`, `:edit` nếu `update`, ngược lại `action_name.to_sym`.

Mọi **command/form action** từ change `02` đến `07` (connect, create, update, approve, reject, regenerate, post now, schedule, retry...) SHALL gọi `render_operation` thay vì tự viết `if operator.success? ... else ... end` + `render`/`redirect_to` riêng lẻ trong từng action.

Các **read-only action** (`index`, `show`, `status`, dashboard) vẫn phải gọi Operation để lấy dữ liệu và không được query/mutate Model trực tiếp trong Controller, nhưng khi thành công được `render` view trực tiếp vì `render_operation` có success contract là redirect. Nếu Operation thất bại, action dùng cùng failure behavior của `OperationRenderable` (flash alert + HTTP 422 + action fallback), không tự tạo format lỗi riêng.

Alternative: để mỗi Controller tự quyết định format response. Bị loại — đây chính là nguyên nhân khiến 7 change độc lập (code bởi các phiên làm việc khác nhau, có thể cách nhau nhiều ngày) dễ sinh ra 7 kiểu flash/status khác nhau cho cùng 1 khái niệm "Operation thất bại".

## Risks / Trade-offs

- [Model khung rỗng có thể thiếu field phát hiện muộn khi đọc Porting Note ở change 02–06] → Mitigation: migration ở change sau được phép `add_column` bổ sung nếu Porting Note phát hiện field còn thiếu, không cần sửa lại change 01 đã archive.
- [Chưa bật encryption đúng cách (thiếu key) sẽ chặn toàn bộ change sau] → Mitigation: task cuối của change này verify thủ công bằng `bin/rails runner` xác nhận ciphertext thật trong DB trước khi coi change 01 là archived.

## Migration Plan

DB đang trống hoàn toàn (development/test), không có dữ liệu cần giữ. `bin/rails db:migrate` chạy tuần tự theo thứ tự migration tạo ra trong change này. Rollback: `bin/rails db:rollback STEP=n` nếu cần, an toàn vì chưa có traffic thật.
