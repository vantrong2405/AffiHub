# Tasks

## 1. Porting Note

- [x] 1.1 Viết `affihub/docs/reference-analysis/ai-connection.md` theo template `PROJECT_SPEC.md` (Reference `decolua/9router` MIT license, Implementation, Behavior cần giữ: PKCE flow + fixed port 1455 + refresh rotation (`refreshLeadMs: 10.minutes`) + header giả lập, Không port: toàn bộ UI dashboard 9router/multi-provider registry, Rails mapping, Data flow, State lifecycle, Error handling, Security, License, Implementation plan, Verification), verify: file tồn tại đủ mục

## 2. Migration bổ sung cột (nếu cần)

- [x] 2.1 Viết `spec/models/ai_connection_spec.rb` bổ sung assertion cho `id_token`, `chatgpt_account_id`, `chatgpt_plan_type` (mã hoá `id_token`, 2 cột còn lại không cần mã hoá vì không nhạy cảm) — `access_token_expires_at` đã có từ change 01, chạy fail nếu cột chưa có
- [x] 2.2 Thêm `db/migrate/..._add_codex_fields_to_ai_connections.rb` để spec 2.1 pass, verify: spec pass

## 3. CodexClient — authorize URL + PKCE

- [x] 3.1 Viết `spec/clients/codex_client_spec.rb` cho việc build authorize URL đúng tham số (client_id, scope, code_challenge S256, state, redirect_uri cố định :1455), chạy fail
- [x] 3.2 Implement `app/clients/codex_client.rb#build_authorize_url` để spec 3.1 pass, verify: spec pass

## 4. Token exchange (CodexClient — thuần I/O, chưa đụng DB)

- [x] 4.1 Viết `spec/clients/codex_client_spec.rb` bổ sung case exchange code lấy access_token/refresh_token/id_token tại `auth.openai.com/oauth/token`, chạy fail (stub HTTP ở layer Client)
- [x] 4.2 Implement `app/clients/codex_client.rb#exchange_token` để spec 4.1 pass, verify: spec pass

## 5. Local callback listener (port 1455) — xử lý TOÀN BỘ callback trong 1 response (xem design.md Decision 1)

- [x] 5.0 Thêm `gem "webrick"` vào `Gemfile` (không còn trong stdlib Ruby 3.0+, cần khai báo rõ), chạy `rtk bundle install`, verify: `bundle check` pass, `Gemfile.lock` có `webrick`
- [x] 5.1 Viết `spec/clients/codex_callback_listener_spec.rb` (listener nhận 1 `TCPServer` ĐÃ bind sẵn (không tự bind) qua tham số, nhận GET /auth/callback với code+state đúng state đã closure lúc khởi tạo → gọi `exchange_token`, tạo `AIConnection` qua `ActiveRecord::Base.connection_pool.with_connection`, trả response 302 tới `callback_result_path(outcome: "success")`; tự đóng ngay sau khi trả response), chạy fail
- [x] 5.2 Implement `app/clients/codex_callback_listener.rb` (Rack app tối giản chạy trong `Thread.new(server:, state:, code_verifier:, user_id:)` — nhận `server` (TCPServer) đã bind sẵn từ caller, KHÔNG tự bind `127.0.0.1:1455`, timeout mặc định 120s — xem design.md Decision 1 lý do bind phải xảy ra đồng bộ ở `ConnectOperation` trước khi spawn Thread này) để spec 5.1 pass, verify: spec pass
- [x] 5.3 Viết `spec/clients/codex_callback_listener_spec.rb` bổ sung case state không khớp (Requirement "Callback OAuth an toàn trước khi exchange token" - scenario State không khớp: KHÔNG gọi exchange_token, trả 302 tới `callback_result_path(outcome: "error", reason: "state_mismatch")`), chạy fail
- [x] 5.4 Implement verify state trong listener để spec 5.3 pass, verify: spec pass
- [x] 5.5 Viết `spec/clients/codex_callback_listener_spec.rb` bổ sung case exchange_token thất bại (Requirement "User kết nối Codex qua OAuth/PKCE thật với auth.openai.com" - scenario Token exchange thất bại: không tạo AIConnection, redirect `outcome: "error", reason: "exchange_failed"`), chạy fail
- [x] 5.6 Implement xử lý lỗi exchange trong listener để spec 5.5 pass, verify: spec pass
- [x] 5.7 Viết `spec/clients/codex_callback_listener_spec.rb` bổ sung case callback gọi 2 lần (chỉ xử lý lần đầu, lần 2 bị bỏ qua, không exchange lần nữa, không tạo AIConnection trùng) (Requirement "Callback OAuth an toàn trước khi exchange token" - scenario Callback bị gọi hai lần), chạy fail
- [x] 5.8 Implement guard "đã xử lý 1 callback thì đóng listener ngay" để spec 5.7 pass, verify: spec pass
- [x] 5.9 Viết test xác nhận listener timeout sau 120s không có callback nào tới (Requirement "Callback OAuth an toàn trước khi exchange token" - scenario Callback timeout/User huỷ OAuth giữa chừng): listener tự đóng, không treo, chạy fail
- [x] 5.10 Implement timeout trong listener để spec 5.9 pass, verify: spec pass

## 6. ConnectOperation — bind port 1455 ĐỒNG BỘ trước khi redirect, rồi điều phối connect action

**Sửa bug đã bị phát hiện qua review**: bind TCP phải xảy ra ĐỒNG BỘ ngay trong `ConnectOperation#call` (chạy trên Puma request thread), KHÔNG xảy ra bên trong `Thread.new` — nếu bind lỗi (port 1455 đã bị chiếm) xảy ra bên trong Thread, Operation đã redirect user sang `auth.openai.com` rồi mới biết lỗi, không có cách báo cho user (xem design.md Decision 1).

- [x] 6.1 Viết `spec/operations/ai_connections/connect_operation_spec.rb` (Requirement "User kết nối Codex qua OAuth/PKCE thật với auth.openai.com": sinh state+PKCE, bind `TCPServer.new("127.0.0.1", 1455)` ĐỒNG BỘ trong `#call` TRƯỚC khi trả `authorize_url`, rồi mới spawn `CodexCallbackListener` qua `Thread.new(server:, state:, code_verifier:, user_id:)`; scenario port 1455 đã bị chiếm — Requirement "Callback OAuth an toàn trước khi exchange token": `Errno::EADDRINUSE` raise ngay trong `#call`, Operation bắt được, `success?` false, errors rõ ràng, KHÔNG trả `authorize_url`, KHÔNG spawn Thread), chạy fail
- [x] 6.2 Implement `app/operations/ai_connections/connect_operation.rb` (bind `TCPServer` đồng bộ, `rescue Errno::EADDRINUSE` convert thành `errors`, chỉ spawn `CodexCallbackListener` Thread sau khi bind thành công) để spec 6.1 pass, verify: spec pass

## 7. Refresh token rotation + trigger (xem design.md Decision 3b)

- [x] 7.1 Viết `spec/clients/codex_client_spec.rb` bổ sung case refresh token (trả `access_token`/`refresh_token`/`expires_in` mới), chạy fail
- [x] 7.2 Implement `app/clients/codex_client.rb#refresh_token` để spec 7.1 pass, verify: spec pass
- [x] 7.3 Viết `spec/operations/ai_connections/refresh_token_operation_spec.rb` (Requirement "Refresh token tự động, không tái dùng refresh_token cũ": refresh thành công ghi đè refresh_token mới + set `access_token_expires_at = Time.current + expires_in.seconds`; refresh thất bại do token đã bị thay thế → disconnected), chạy fail
- [x] 7.4 Implement `app/operations/ai_connections/refresh_token_operation.rb` (transaction, ghi đè refresh_token + expires_at) để spec 7.3 pass, verify: spec pass
- [x] 7.5 Viết `spec/models/ai_connection_spec.rb` cho `#ensure_fresh_token!` (gọi `RefreshTokenOperation` khi `access_token_expires_at.nil?` hoặc còn dưới 10 phút; không gọi gì khi còn hạn xa; **refresh thất bại → raise `AIConnectionDisconnectedError`, KHÔNG return im lặng**), chạy fail
- [x] 7.6 Implement `AIConnection#ensure_fresh_token!` + class lỗi `AIConnectionDisconnectedError` (`lib/errors/` hoặc ngay trong `ai_connection.rb`) trong `app/models/ai_connection.rb` để spec 7.5 pass, verify: spec pass

## 8. Test Connection (gọi `ensure_fresh_token!` trước khi gửi prompt)

- [x] 8.1 Viết `spec/clients/codex_client_spec.rb` khóa request Responses API theo reference `decolua/9router`: header originator/User-Agent/version, model trong config, input dạng message `input_text`, `stream: true`, `store: false`, Accept SSE; đồng thời xác nhận parse text delta, chạy fail
- [x] 8.2 Implement `app/clients/codex_client.rb#send_prompt` theo request/stream contract ở spec 8.1, verify: spec pass
- [x] 8.3 Viết `spec/operations/ai_connections/test_connection_operation_spec.rb` (Requirement "Test Connection gửi/nhận prompt thật qua ChatGPT backend-api": gọi `ai_connection.ensure_fresh_token!` TRƯỚC `send_prompt`), chạy fail
- [x] 8.4 Implement `app/operations/ai_connections/test_connection_operation.rb` (gọi `ensure_fresh_token!` trước `send_prompt`) để spec 8.3 pass, verify: spec pass
- [x] 8.5 Viết `spec/operations/ai_connections/test_connection_operation_spec.rb` bổ sung case refresh thất bại (Requirement "Refresh token tự động, không tái dùng refresh_token cũ": `ensure_fresh_token!` raise `AIConnectionDisconnectedError` → Operation KHÔNG gọi `send_prompt`, `success?` false, lỗi "Codex đã mất kết nối, cần Connect lại"), chạy fail
- [x] 8.6 Implement `TestConnectionOperation` bắt lỗi mất kết nối và lỗi HTTP từ Codex ở tầng Operation (để convert thành `errors`/message cho `render_operation`, KHÔNG để exception leak ra Controller), vẫn KHÔNG gọi `send_prompt` sau khi refresh lỗi, verify: spec pass

## 9. Ẩn credential

- [x] 9.1 Viết `spec/serializers/ai_connection_serializer_spec.rb` (Requirement "Không lộ credential" — serializer không có field token), chạy fail
- [x] 9.2 Implement `app/serializers/ai_connection_serializer.rb` để spec pass, verify: spec pass
- [x] 9.3 Viết test xác nhận log filter (`config/initializers/filter_parameter_logging.rb` hoặc custom log subscriber) không log raw token, chạy fail
- [x] 9.4 Implement log filter để spec pass, verify: spec pass + kiểm tra `log/development.log` sau khi Test Connection không chứa token

## 10. UI + verify thủ công

- [x] 10.1 Viết `spec/requests/ai_connections_spec.rb` (action `connect` (GET) redirect 302 sang authorizeUrl và kết thúc ngay — không block; action `callback_result` (GET, route thật trên Puma, đọc `outcome`/`reason` param, set flash, `redirect_to ai_connections_path`); test connection endpoint dùng `render_operation`), chạy fail
- [x] 10.2 Thêm route `get "ai_connections/connect"`, `get "ai_connections/callback_result"` + `resource :ai_connection` (hoặc tương đương) cho Test Connection action vào `config/routes.rb`. Dùng skill `ui-ux` để quyết định layout/component/token màu cho trang AI Connection (Connect button, status, Test Connection) trước khi viết view; implement `app/controllers/ai_connections_controller.rb` (`connect` gọi `operator = ConnectOperation.call(params:)`; khi `operator.success?` → `redirect_to operator.authorize_url`; khi false (vd `Errno::EADDRINUSE`) → `render_operation` hoặc set `flash[:alert] = operator.errors.full_messages.to_sentence` rồi `redirect_to ai_connections_path`, KHÔNG được redirect sang `authorize_url` khi Operation fail; `callback_result` set flash theo `outcome`/`reason` rồi redirect — đây là relay thuần, không có Operation nào để dùng `render_operation`, set flash trực tiếp; Test Connection dùng `render_operation`) + view (Connect button, hiển thị status/plan, Test Connection button) để spec 10.1 pass, verify: spec pass + request spec có case `connect` khi port 1455 bị chiếm → render lỗi, không redirect `auth.openai.com`
- [ ] 10.3 Verify thủ công: `rtk bin/dev`, bấm Connect Codex, hoàn tất login thật tài khoản ChatGPT, xác nhận redirect về `callback_result` → flash success → trang AIConnection hiển thị connected, bấm Test Connection, xác nhận response thật hiển thị trên UI — không fake/hard-code
- [x] 10.4 Verify thủ công: thử bấm Connect Codex rồi đóng tab giữa chừng (không hoàn tất consent), xác nhận sau ~120s listener tự đóng, không treo (không có cách poll kết quả này qua UI vì browser đã rời Rails app — verify bằng log/process, không phải qua UI). Đã thấy log timeout sau 120s và port 1455 được giải phóng.

## 11. Chuẩn hoá shared HTTP transport theo rule client của workspace

- [x] 11.1 Rà/bổ sung `spec/clients/codex_client_spec.rb` để khóa request body/headers cho cả token exchange (form-encoded) và `send_prompt` (JSON), đồng thời xác nhận mọi request dùng timeout từ config; chạy spec trước refactor và bổ sung assertion nào còn thiếu
- [x] 11.2 Thêm timeout defaults vào `config/codex.yml`; refactor `CodexClient` để `post_token` và `post_json` chỉ dựng request-specific data rồi cùng gọi một private `request` method duy nhất, method này chọn body encoding theo config/type và thực hiện `Net::HTTP` đúng một chỗ; giữ nguyên mọi behavior đã port từ `decolua/9router`, không hard-code URL/ID/version/timeout
- [x] 11.3 Chạy `RAILS_ENV=test rtk bundle exec rspec spec/clients/codex_client_spec.rb` và rà source xác nhận không còn `Net::HTTP` call ngoài shared `request` method

## 12. Connection usable và reconnect an toàn

- [x] 12.1 Viết RSpec cho Test Connection với status disconnected, thiếu access token, thiếu refresh token khi refresh cần thiết, và token hợp lệ; xác nhận không gửi prompt trong các trường hợp không usable
- [x] 12.2 Cập nhật `AIConnection`/Operations để enforce contract usable dùng chung; chạy các spec 12.1 pass
- [x] 12.3 Viết RSpec cho OAuth reconnect thất bại khi connection đã tồn tại; xác nhận token/status/connected_at cũ được giữ nguyên
- [x] 12.4 Cập nhật persistence để exchange/persist reconnect nguyên tử, chỉ cập nhật `connected_at` khi thành công; chạy spec 12.3 pass

## 13. Refresh tuần tự và lỗi phân biệt

- [x] 13.1 Viết RSpec cho hai refresh cạnh tranh; xác nhận request thứ hai reload connection mới và refresh token cũ không được dùng lại
- [x] 13.2 Thêm serialization/row lock và reload/recheck trạng thái trước refresh; chạy spec 13.1 pass
- [x] 13.3 Viết RSpec cho provider xác nhận invalid/revoked, lỗi transport tạm thời, và response lỗi không phân loại; xác nhận chỉ invalid/revoked làm disconnected
- [x] 13.4 Phân loại lỗi refresh; giữ credential/status khi lỗi tạm thời và chặn prompt sau mọi lỗi refresh; chạy spec 13.3 pass

## 14. Callback cạnh tranh, lỗi OAuth và cleanup

- [x] 14.1 Viết RSpec callback cạnh tranh đồng thời, callback thiếu code/OAuth error, lỗi exchange transport/JSON/DB, và lỗi setup sau bind
- [x] 14.2 Thêm one-shot atomic guard, redirect lỗi tổng quát, log an toàn và cleanup socket đúng ownership; chạy spec 14.1 pass
- [x] 14.3 Viết RSpec đảm bảo chỉ request thắng được shutdown listener và callback thứ hai không làm gián đoạn request đầu
- [x] 14.4 Sửa listener để request bị bỏ qua không shutdown server của request đang xử lý; chạy spec 14.3 pass

## 15. Provider contract và xác minh account context

- [x] 15.1 Đọc `open-sse/providers/registry/codex.js` của `decolua/9router`, lần theo import/registration để xác định provider abstraction thực sự; cập nhật Porting Note ghi rõ source path đã đọc, contract behavior được dùng làm reference, phần registry/plugin không port và Rails mapping. Verify: đường dẫn và quyết định port/not-port được ghi rõ, không suy diễn từ tên file
- [x] 15.2 Viết RSpec cho Test Connection gọi provider contract chung và cho contract xử lý freshness/refresh trước prompt; chạy fail
- [x] 15.3 Tách contract nhỏ và Codex adapter dựa trên abstraction đã đọc ở task 15.1; giữ POC chỉ có Codex và một connection/user, không port registry/plugin của 9router; chạy spec 15.2 pass
- [x] 15.4 Viết RSpec cho ID token signature, issuer, audience, expiry và account ID thiếu/sai
- [x] 15.5 Thêm xác minh ID token trước khi persist hoặc dùng account context; chạy spec 15.4 pass

## 16. Codex stream và transport errors

- [x] 16.1 Viết RSpec cho completion có text, output rỗng, provider error event, thiếu completion và transport interruption
- [x] 16.2 Chỉ coi stream hoàn chỉnh có text là thành công; ánh xạ prompt transport errors thành Operation errors; chạy spec 16.1 pass

## 17. Config, method khởi tạo và serializer

- [x] 17.1 Viết RSpec cho callback host/port/path lấy từ config và khớp giữa bind với redirect URI; viết request spec xác nhận connect dùng POST
- [x] 17.2 Đưa callback host/port/path, refresh lead và các cấu hình liên quan về `config/codex.yml`; bind theo cùng loopback host; đổi route connect sang POST; chạy spec 17.1 pass
- [x] 17.3 Viết RSpec cho serializer chỉ phát status/plan/connected_at, không phát token/account ID; xác nhận reconnect thành công cập nhật connected_at
- [x] 17.4 Thêm migration `connected_at`, cập nhật serializer/persistence và bỏ account ID khỏi public serializer; chạy spec 17.3 pass

## 18. Đồng bộ OpenSpec và xác minh

- [x] 18.1 Xác nhận `openspec/specs/ai-connection/spec.md` phản ánh contract hiện hành và chạy `rtk openspec validate --specs`; validation chỉ kiểm tra artifact, không xác nhận app sẵn sàng demo. Tiến độ implementation phải căn theo task chưa hoàn tất; readiness toàn chuỗi chỉ được xác nhận bằng evidence 34 bước ở change `07`.
- [x] 18.2 Sau khi tasks 12–17 hoàn tất, chạy các RSpec file liên quan theo từng file với `RAILS_ENV=test`; chạy manual OAuth/Test Connection trước khi đánh dấu change hoàn tất
