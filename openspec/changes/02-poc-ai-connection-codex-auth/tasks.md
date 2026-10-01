# Tasks

## 1. Porting Note

- [ ] 1.1 Viết `affihub/docs/reference-analysis/ai-connection.md` theo template `PROJECT_SPEC.md` (Reference `decolua/9router` MIT license, Implementation, Behavior cần giữ: PKCE flow + fixed port 1455 + refresh rotation (`refreshLeadMs: 10.minutes`) + header giả lập, Không port: toàn bộ UI dashboard 9router/multi-provider registry, Rails mapping, Data flow, State lifecycle, Error handling, Security, License, Implementation plan, Verification), verify: file tồn tại đủ mục

## 2. Migration bổ sung cột (nếu cần)

- [ ] 2.1 Viết `spec/models/ai_connection_spec.rb` bổ sung assertion cho `id_token`, `chatgpt_account_id`, `chatgpt_plan_type` (mã hoá `id_token`, 2 cột còn lại không cần mã hoá vì không nhạy cảm) — `access_token_expires_at` đã có từ change 01, chạy fail nếu cột chưa có
- [ ] 2.2 Thêm `db/migrate/..._add_codex_fields_to_ai_connections.rb` để spec 2.1 pass, verify: spec pass

## 3. CodexClient — authorize URL + PKCE

- [ ] 3.1 Viết `spec/clients/codex_client_spec.rb` cho việc build authorize URL đúng tham số (client_id, scope, code_challenge S256, state, redirect_uri cố định :1455), chạy fail
- [ ] 3.2 Implement `app/clients/codex_client.rb#build_authorize_url` để spec 3.1 pass, verify: spec pass

## 4. Token exchange (CodexClient — thuần I/O, chưa đụng DB)

- [ ] 4.1 Viết `spec/clients/codex_client_spec.rb` bổ sung case exchange code lấy access_token/refresh_token/id_token tại `auth.openai.com/oauth/token`, chạy fail (stub HTTP ở layer Client)
- [ ] 4.2 Implement `app/clients/codex_client.rb#exchange_token` để spec 4.1 pass, verify: spec pass

## 5. Local callback listener (port 1455) — xử lý TOÀN BỘ callback trong 1 response (xem design.md Decision 1)

- [ ] 5.0 Thêm `gem "webrick"` vào `Gemfile` (không còn trong stdlib Ruby 3.0+, cần khai báo rõ), chạy `rtk bundle install`, verify: `bundle check` pass, `Gemfile.lock` có `webrick`
- [ ] 5.1 Viết `spec/clients/codex_callback_listener_spec.rb` (listener nhận 1 `TCPServer` ĐÃ bind sẵn (không tự bind) qua tham số, nhận GET /auth/callback với code+state đúng state đã closure lúc khởi tạo → gọi `exchange_token`, tạo `AIConnection` qua `ActiveRecord::Base.connection_pool.with_connection`, trả response 302 tới `callback_result_path(outcome: "success")`; tự đóng ngay sau khi trả response), chạy fail
- [ ] 5.2 Implement `app/clients/codex_callback_listener.rb` (Rack app tối giản chạy trong `Thread.new(server:, state:, code_verifier:, user_id:)` — nhận `server` (TCPServer) đã bind sẵn từ caller, KHÔNG tự bind `127.0.0.1:1455`, timeout mặc định 120s — xem design.md Decision 1 lý do bind phải xảy ra đồng bộ ở `ConnectOperation` trước khi spawn Thread này) để spec 5.1 pass, verify: spec pass
- [ ] 5.3 Viết `spec/clients/codex_callback_listener_spec.rb` bổ sung case state không khớp (Requirement "Callback OAuth an toàn trước khi exchange token" - scenario State không khớp: KHÔNG gọi exchange_token, trả 302 tới `callback_result_path(outcome: "error", reason: "state_mismatch")`), chạy fail
- [ ] 5.4 Implement verify state trong listener để spec 5.3 pass, verify: spec pass
- [ ] 5.5 Viết `spec/clients/codex_callback_listener_spec.rb` bổ sung case exchange_token thất bại (Requirement "User kết nối Codex qua OAuth/PKCE thật với auth.openai.com" - scenario Token exchange thất bại: không tạo AIConnection, redirect `outcome: "error", reason: "exchange_failed"`), chạy fail
- [ ] 5.6 Implement xử lý lỗi exchange trong listener để spec 5.5 pass, verify: spec pass
- [ ] 5.7 Viết `spec/clients/codex_callback_listener_spec.rb` bổ sung case callback gọi 2 lần (chỉ xử lý lần đầu, lần 2 bị bỏ qua, không exchange lần nữa, không tạo AIConnection trùng) (Requirement "Callback OAuth an toàn trước khi exchange token" - scenario Callback bị gọi hai lần), chạy fail
- [ ] 5.8 Implement guard "đã xử lý 1 callback thì đóng listener ngay" để spec 5.7 pass, verify: spec pass
- [ ] 5.9 Viết test xác nhận listener timeout sau 120s không có callback nào tới (Requirement "Callback OAuth an toàn trước khi exchange token" - scenario Callback timeout/User huỷ OAuth giữa chừng): listener tự đóng, không treo, chạy fail
- [ ] 5.10 Implement timeout trong listener để spec 5.9 pass, verify: spec pass

## 6. ConnectOperation — bind port 1455 ĐỒNG BỘ trước khi redirect, rồi điều phối connect action

**Sửa bug đã bị phát hiện qua review**: bind TCP phải xảy ra ĐỒNG BỘ ngay trong `ConnectOperation#call` (chạy trên Puma request thread), KHÔNG xảy ra bên trong `Thread.new` — nếu bind lỗi (port 1455 đã bị chiếm) xảy ra bên trong Thread, Operation đã redirect user sang `auth.openai.com` rồi mới biết lỗi, không có cách báo cho user (xem design.md Decision 1).

- [ ] 6.1 Viết `spec/operations/ai_connections/connect_operation_spec.rb` (Requirement "User kết nối Codex qua OAuth/PKCE thật với auth.openai.com": sinh state+PKCE, bind `TCPServer.new("127.0.0.1", 1455)` ĐỒNG BỘ trong `#call` TRƯỚC khi trả `authorize_url`, rồi mới spawn `CodexCallbackListener` qua `Thread.new(server:, state:, code_verifier:, user_id:)`; scenario port 1455 đã bị chiếm — Requirement "Callback OAuth an toàn trước khi exchange token": `Errno::EADDRINUSE` raise ngay trong `#call`, Operation bắt được, `success?` false, errors rõ ràng, KHÔNG trả `authorize_url`, KHÔNG spawn Thread), chạy fail
- [ ] 6.2 Implement `app/operations/ai_connections/connect_operation.rb` (bind `TCPServer` đồng bộ, `rescue Errno::EADDRINUSE` convert thành `errors`, chỉ spawn `CodexCallbackListener` Thread sau khi bind thành công) để spec 6.1 pass, verify: spec pass

## 7. Refresh token rotation + trigger (xem design.md Decision 3b)

- [ ] 7.1 Viết `spec/clients/codex_client_spec.rb` bổ sung case refresh token (trả `access_token`/`refresh_token`/`expires_in` mới), chạy fail
- [ ] 7.2 Implement `app/clients/codex_client.rb#refresh_token` để spec 7.1 pass, verify: spec pass
- [ ] 7.3 Viết `spec/operations/ai_connections/refresh_token_operation_spec.rb` (Requirement "Refresh token tự động, không tái dùng refresh_token cũ": refresh thành công ghi đè refresh_token mới + set `access_token_expires_at = Time.current + expires_in.seconds`; refresh thất bại do token đã bị thay thế → disconnected), chạy fail
- [ ] 7.4 Implement `app/operations/ai_connections/refresh_token_operation.rb` (transaction, ghi đè refresh_token + expires_at) để spec 7.3 pass, verify: spec pass
- [ ] 7.5 Viết `spec/models/ai_connection_spec.rb` cho `#ensure_fresh_token!` (gọi `RefreshTokenOperation` khi `access_token_expires_at.nil?` hoặc còn dưới 10 phút; không gọi gì khi còn hạn xa; **refresh thất bại → raise `AIConnectionDisconnectedError`, KHÔNG return im lặng**), chạy fail
- [ ] 7.6 Implement `AIConnection#ensure_fresh_token!` + class lỗi `AIConnectionDisconnectedError` (`lib/errors/` hoặc ngay trong `ai_connection.rb`) trong `app/models/ai_connection.rb` để spec 7.5 pass, verify: spec pass

## 8. Test Connection (gọi `ensure_fresh_token!` trước khi gửi prompt)

- [ ] 8.1 Viết `spec/clients/codex_client_spec.rb` bổ sung case gọi `chatgpt.com/backend-api/codex/responses` với header originator/User-Agent đúng, chạy fail
- [ ] 8.2 Implement `app/clients/codex_client.rb#send_prompt` để spec 8.1 pass, verify: spec pass
- [ ] 8.3 Viết `spec/operations/ai_connections/test_connection_operation_spec.rb` (Requirement "Test Connection gửi/nhận prompt thật qua ChatGPT backend-api": gọi `ai_connection.ensure_fresh_token!` TRƯỚC `send_prompt`), chạy fail
- [ ] 8.4 Implement `app/operations/ai_connections/test_connection_operation.rb` (gọi `ensure_fresh_token!` trước `send_prompt`) để spec 8.3 pass, verify: spec pass
- [ ] 8.5 Viết `spec/operations/ai_connections/test_connection_operation_spec.rb` bổ sung case refresh thất bại (Requirement "Refresh token tự động, không tái dùng refresh_token cũ": `ensure_fresh_token!` raise `AIConnectionDisconnectedError` → Operation KHÔNG gọi `send_prompt`, `success?` false, lỗi "Codex đã mất kết nối, cần Connect lại"), chạy fail
- [ ] 8.6 Implement `TestConnectionOperation` bắt `AIConnectionDisconnectedError` ở tầng Operation (để convert thành `errors`/message cho `render_operation`, KHÔNG để exception leak ra Controller) — nhưng vẫn KHÔNG gọi `send_prompt` sau đó, để spec 8.5 pass, verify: spec pass

## 9. Ẩn credential

- [ ] 9.1 Viết `spec/serializers/ai_connection_serializer_spec.rb` (Requirement "Không lộ credential" — serializer không có field token), chạy fail
- [ ] 9.2 Implement `app/serializers/ai_connection_serializer.rb` để spec pass, verify: spec pass
- [ ] 9.3 Viết test xác nhận log filter (`config/initializers/filter_parameter_logging.rb` hoặc custom log subscriber) không log raw token, chạy fail
- [ ] 9.4 Implement log filter để spec pass, verify: spec pass + kiểm tra `log/development.log` sau khi Test Connection không chứa token

## 10. UI + verify thủ công

- [ ] 10.1 Viết `spec/requests/ai_connections_spec.rb` (action `connect` (GET) redirect 302 sang authorizeUrl và kết thúc ngay — không block; action `callback_result` (GET, route thật trên Puma, đọc `outcome`/`reason` param, set flash, `redirect_to ai_connections_path`); test connection endpoint dùng `render_operation`), chạy fail
- [ ] 10.2 Thêm route `get "ai_connections/connect"`, `get "ai_connections/callback_result"` + `resource :ai_connection` (hoặc tương đương) cho Test Connection action vào `config/routes.rb`. Dùng skill `ui-ux` để quyết định layout/component/token màu cho trang AI Connection (Connect button, status, Test Connection) trước khi viết view; implement `app/controllers/ai_connections_controller.rb` (`connect` gọi `operator = ConnectOperation.call(params:)`; khi `operator.success?` → `redirect_to operator.authorize_url`; khi false (vd `Errno::EADDRINUSE`) → `render_operation` hoặc set `flash[:alert] = operator.errors.full_messages.to_sentence` rồi `redirect_to ai_connections_path`, KHÔNG được redirect sang `authorize_url` khi Operation fail; `callback_result` set flash theo `outcome`/`reason` rồi redirect — đây là relay thuần, không có Operation nào để dùng `render_operation`, set flash trực tiếp; Test Connection dùng `render_operation`) + view (Connect button, hiển thị status/plan, Test Connection button) để spec 10.1 pass, verify: spec pass + request spec có case `connect` khi port 1455 bị chiếm → render lỗi, không redirect `auth.openai.com`
- [ ] 10.3 Verify thủ công: `rtk bin/dev`, bấm Connect Codex, hoàn tất login thật tài khoản ChatGPT, xác nhận redirect về `callback_result` → flash success → trang AIConnection hiển thị connected, bấm Test Connection, xác nhận response thật hiển thị trên UI — không fake/hard-code
- [ ] 10.4 Verify thủ công: thử bấm Connect Codex rồi đóng tab giữa chừng (không hoàn tất consent), xác nhận sau ~120s listener tự đóng, không treo (không có cách poll kết quả này qua UI vì browser đã rời Rails app — verify bằng log/process, không phải qua UI)
