# Design

## Context

Model `AIConnection` khung rỗng đã tồn tại từ change `01` (user association, cột token mã hoá, enum status). Reference-first đã thực hiện qua đọc trực tiếp source `decolua/9router` (MIT, xem `affihub/docs/reference-analysis/ai-connection.md` sẽ được viết ở Task 1). Xem `proposal.md` cho quyết định scope/rủi ro đã được user xác nhận.

## Goals / Non-Goals

**Goals:**
- Port đúng behavior OAuth/PKCE + refresh rotation của 9router's `codex.js` provider (client_id, endpoint, scope, PKCE, callback port cố định) sang Rails.
- Test Connection gọi thật `chatgpt.com/backend-api/codex/responses`, không mock ở tầng integration/demo.
- Giữ nguyên rủi ro đã biết (reverse-engineered endpoint) nhưng cô lập trong 1 Client object để dễ thay thế nếu sau này cần đổi sang API chính thức.

**Non-Goals:**
- Không implement multi-provider AI (chỉ Codex).
- Không tự host 1 dashboard quota như 9router (`/backend-api/wham/usage`) — POC chỉ cần `chatgptPlanType` hiển thị tham khảo, không cần biểu đồ usage.
- Không giải bài toán deploy remote multi-user (đã xác nhận: chỉ chạy localhost dev).

## Decisions

### 1. Local callback listener tạm thời trên port 1455 — xử lý TOÀN BỘ callback (exchange + tạo AIConnection + redirect) trong CÙNG 1 response, không polling/connecting-page
`client_id` public của Codex CLI (`app_EMoamEEZ73f0CkXaXp7hrann`) được `auth.openai.com` cấu hình sẵn redirect_uri cố định `http://localhost:1455/auth/callback` — không thể đổi port. Vì Rails dev server (`bin/dev`) chạy ở port khác (thường 3000), implement 1 Rack app tối giản (`WEBrick`) được spawn trong 1 `Thread.new` riêng (không phải thread xử lý HTTP request của Puma) khi user bấm "Connect Codex".

**Sửa so với bản thiết kế trước (đã bị phát hiện qua review là thiếu rõ ràng/có ảo giác về thứ tự `:id`)**: bản trước ngụ ý tách rời "callback tạo AIConnection" khỏi "redirect browser" bằng 1 trang "connecting" + Turbo Stream polling — nhưng suy xét lại: với flow OAuth redirect toàn trang bình thường (browser rời hẳn khỏi Rails app sang `auth.openai.com` rồi mới quay lại), **không có trang Rails nào để poll trong lúc chờ** (browser đang ở domain khác, không load bất kỳ JS/Turbo Stream nào của ta) — nên toàn bộ ý tưởng "connecting page + polling" giải quyết một vấn đề không tồn tại trong flow 1-tab-redirect này. Lo ngại ban đầu ("không block 1 Puma worker thread") cũng không áp dụng: thời gian user consent ở `auth.openai.com` không giữ bất kỳ Puma thread nào (Puma đã trả response 302 và rảnh ngay từ bước 1; listener ở port 1455 là tiến trình/thread hoàn toàn tách biệt Puma). Vì vậy: **listener xử lý xong toàn bộ (verify state → exchange token → tạo AIConnection) NGAY trong lúc trả lời chính request callback đó**, biết chắc `id` của AIConnection vừa tạo trước khi redirect — không có vấn đề "chưa có `:id`".

**Flow cụ thể (closure, không cache/model phụ cho việc truyền state)**:
```
1. GET /ai_connections/connect (action "connect", có current_user từ session)
   -> sinh state = SecureRandom.hex(16), code_verifier/code_challenge (PKCE)
   -> BIND SYNCHRONOUS ngay trong request thread của Puma (KHÔNG trong Thread.new):
      `server = TCPServer.new("127.0.0.1", 1455)` — nếu port đã bị chiếm,
      `Errno::EADDRINUSE` raise NGAY TẠI ĐÂY, Operation bắt được, trả lỗi rõ
      ràng cho user (Risk "Listener tạm trên port 1455 có thể conflict") TRƯỚC
      khi redirect — sửa bug đã bị phát hiện qua review: bản thiết kế trước
      bind trong Thread.new rồi redirect ngay, không đợi bind xong/thất bại,
      nên lỗi bind (port busy) không có cách nào báo cho user (request đã
      redirect xong, Thread lỗi âm thầm, user consent xong rồi mới biết
      callback không ai nhận)
   -> Thread.new(server:, state:, code_verifier:, user_id: current_user.id) { ... }
      (đóng gói socket đã bind sẵn + 3 giá trị closure — KHÔNG cần
      Rails.cache/bảng tạm nào để truyền state giữa 2 bước, vì toàn bộ nằm
      trong cùng 1 process Ruby, chỉ khác Thread)
      bên trong thread: dùng `server` đã bind sẵn (`WEBrick::HTTPServer.new(..., Listeners: [server])`
      hoặc tương đương — KHÔNG tự bind lại), block chờ ĐÚNG 1 request
      /auth/callback, timeout 120s (Requirement "Callback OAuth an toàn
      trước khi exchange token")
   -> redirect_to authorize_url (302) — CHỈ sau khi bind ở bước synchronous trên
      thành công, request này kết thúc, Puma thread rảnh (thời gian bind TCP
      local là micro giây, không đáng kể cho request latency)

2. Browser theo redirect 302 -> consent tại auth.openai.com (Puma không liên quan)

3. auth.openai.com redirect browser -> http://localhost:1455/auth/callback?code=...&state=...
   -> listener thread (closure đã có state/code_verifier/user_id từ bước 1) xử lý
      NGAY trong request handler đó:
      a. state param khớp state đã closure? Không khớp -> trả 302 thẳng về
         `http://localhost:3000/ai_connections/callback_result?outcome=error&reason=state_mismatch`,
         KHÔNG exchange, tắt listener
      b. Khớp -> exchange_token (CodexClient), bọc phần ghi DB trong
         `ActiveRecord::Base.connection_pool.with_connection { AIConnection.find_or_create_by!(user_id: ...) ... }`
         (BẮT BUỘC — Thread không phải request Puma nên không tự có connection
         từ pool, phải tự checkout/trả lại, nếu không dễ leak connection)
      c. Thành công -> 302 `http://localhost:3000/ai_connections/callback_result?outcome=success`
         Lỗi exchange -> 302 `...?outcome=error&reason=exchange_failed`
      d. Listener tự tắt ngay sau khi trả response này (single-request server)

4. `AiConnectionsController#callback_result` (route/controller THẬT trên Puma :3000,
   có session cookie của user bình thường) đọc `outcome`/`reason`, set
   `flash[:notice]`/`flash[:alert]` tương ứng, `redirect_to ai_connections_path`
   -> đây là nơi flash/UI hiển thị kết quả, không cần Turbo Stream polling.
```
Vì bước 3 luôn redirect sang `callback_result` (route thật trên Puma, có session) thay vì render thẳng 1 trang final từ listener — listener không cần tự xử lý flash/session (nó là Rack thô, không có middleware session của Rails), mọi hiển thị lỗi/thành công đều đi qua 1 action Rails bình thường.

Alternative (giữ nguyên bản trước — "connecting page" + Turbo Stream polling): bị loại vì giải quyết vấn đề không tồn tại (đã phân tích ở trên), thêm phức tạp (model/cache theo dõi attempt, polling endpoint) không cần thiết cho 1-tab-redirect flow.

### 2. CodexClient là PORO độc lập, giả lập header Codex CLI thật
`app/clients/codex_client.rb` chịu trách nhiệm: build authorize URL (PKCE), exchange/refresh token tại `auth.openai.com`, gọi `chatgpt.com/backend-api/codex/responses` với header `originator: codex_cli_rs`, `User-Agent: codex_cli_rs/<version>`, `version: <version>`. Version string ghim cứng theo bản Codex CLI đã verify hoạt động tại thời điểm viết Porting Note (có thể cần update nếu OpenAI đổi cách detect).

### 3. Refresh token rotation: luôn ghi đè, không giữ lịch sử
`AIConnection#refresh_token` bị ghi đè ngay sau mỗi lần refresh thành công. Operation refresh chạy trong 1 transaction DB để tránh race condition giữa 2 request đồng thời cùng cố refresh bằng refresh_token cũ (chỉ request đầu thành công, request sau nhận lỗi từ OpenAI và phải đọc lại `AIConnection` mới nhất trước khi coi là disconnected thật).

### 3b. Refresh trigger: kiểm tra `access_token_expires_at` TRƯỚC khi gọi Codex, không phải retry-sau-401
Decision 3 nói rotation (ghi đè refresh_token mới) nhưng chưa nói AI GỌI refresh lúc nào — đây là lỗ hổng đã bị phát hiện qua review. Chốt: dùng đúng số liệu thật đã đọc được từ `9router`'s `codex.js` provider config (`refreshLeadMs: 600000` = 10 phút lead trước khi access token hết hạn) — không tự bịa ngưỡng khác.

`AIConnection#ensure_fresh_token!` (method mới, gọi trước MỌI lần dùng `access_token` để gọi Codex — cả Test Connection ở change 02 lẫn `generate_operation`/`regenerate_operation` ở change 04):
```ruby
def ensure_fresh_token!
  return unless access_token_expires_at.nil? || access_token_expires_at < 10.minutes.from_now
  result = RefreshTokenOperation.call(params: { ai_connection: self })
  raise AIConnectionDisconnectedError, "refresh thất bại, AIConnection đã disconnected" unless result.success?
end
```
(Operation kế thừa `MainOperation#initialize(params:)` — mọi `.call` SHALL truyền qua `params:` hash, không nhận keyword args riêng; xem `affihub/CLAUDE.md` convention task 01/2.6)
**Chốt rõ (đã bị phát hiện qua review là thiếu): refresh thất bại PHẢI chặn request, không được âm thầm tiếp tục gọi `send_prompt` bằng access_token cũ** — `ensure_fresh_token!` raise `AIConnectionDisconnectedError` (class lỗi riêng, không phải generic `StandardError`) nếu `RefreshTokenOperation` thất bại; caller (`TestConnectionOperation`, `GenerateOperation`, `RegenerateOperation`) KHÔNG rescue lỗi này ở tầng gọi `ensure_fresh_token!` — để nó propagate lên và khiến Operation/Controller fail rõ ràng (hiển thị "Codex đã mất kết nối, cần Connect lại" cho user), KHÔNG được phép tiếp tục gọi `send_prompt` với access_token đã biết là hết hạn/không refresh được.

Chọn "check trước khi gọi" (proactive) thay vì "gọi trước, catch 401 rồi refresh, retry" (reactive): proactive đơn giản hơn để test (deterministic theo `access_token_expires_at`, không cần giả lập response 401 thật của `chatgpt.com/backend-api` — vốn không phải API chính thức nên response lỗi khi token hết hạn CHƯA CHẮC là HTTP 401 chuẩn, có thể trả dạng khác). Cả 2 nơi gọi Codex (`TestConnectionOperation` change 02, `GenerateOperation`/`RegenerateOperation` change 04) đều gọi `ai_connection.ensure_fresh_token!` trước `codex_client.send_prompt`, dùng CHUNG 1 method, không lặp logic.

`access_token_expires_at` set bằng `Time.current + tokens["expires_in"].seconds` ngay sau mỗi lần exchange/refresh thành công.

### 4. id_token chỉ dùng để hiển thị, không dùng để xác thực authorization
`chatgptAccountId`/`chatgptPlanType` trích từ `id_token` (JWT) chỉ parse payload để hiển thị, không cần verify signature (không dùng id_token để authorize bất kỳ hành động nào trong hệ thống — authorization thật dựa trên access_token khi gọi API).

## Risks / Trade-offs

- [Endpoint `chatgpt.com/backend-api/codex/responses` không phải API chính thức — OpenAI có thể thay đổi/chặn bất kỳ lúc nào, hoặc khoá tài khoản nếu phát hiện] → Mitigation: cô lập toàn bộ logic này trong `CodexClient`, không rải rác; ghi rõ rủi ro trong Porting Note; user đã xác nhận chấp nhận cho mục đích POC.
- [Header/version giả lập có thể lỗi thời nếu OpenAI đổi cách detect Codex CLI thật] → Mitigation: Porting Note ghi version CLI đã verify, task cuối có bước verify thủ công bằng Test Connection thật trước khi coi Done.
- [Listener tạm trên port 1455 có thể conflict nếu port đã bị process khác chiếm] → Mitigation: Operation bắt lỗi bind port rõ ràng, báo lỗi cho user thay vì treo.
- [Refresh_token rotation: nếu 2 process cùng refresh song song sẽ có 1 process bị logout toàn bộ account] → Mitigation: transaction + lock (xem Decision 3), và trong POC chỉ có 1 user/1 process nên rủi ro race condition thấp.

## Migration Plan

Không cần migration dữ liệu (model khung đã có từ change 01, chỉ thêm cột nếu Porting Note phát hiện thiếu — vd `id_token`, `chatgpt_account_id`, `chatgpt_plan_type`). Rollback: revert migration bổ sung + code, không ảnh hưởng change khác vì `AIConnection` chưa được capability nào khác tham chiếu field cụ thể ngoài association.
