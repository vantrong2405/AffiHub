# Proposal

## Precondition

**Code gate (đủ để BẮT ĐẦU viết task code/test của change này):**
- Change `01` đã hoàn tất mọi task TRỪ nhóm "Verify thủ công end-to-end" cuối cùng của nó — tức migration đã `db:migrate` thật, model/login đã code + RSpec pass. (Change `01` không phụ thuộc provider ngoài, nên trong trường hợp cụ thể của change này, code gate và archive gate dưới đây trùng nhau — không có rủi ro bị chặn vì provider chưa sẵn sàng.)

**Archive gate (chỉ archive change `01`, hoặc coi change `01` "xong hẳn", khi đủ):**
- Change `01` đã ở trạng thái `archived` (`openspec list --json`).
- Toàn bộ task "Verify" cuối cùng của change `01` đã tick xong (RSpec + rubocop/brakeman pass, `db:prepare` idempotent).

## Why

Vertical slice POC cần 1 bước "AI Generate Content (Codex)" chạy thật (không mock). Để gọi được Codex thật mà không trả phí API riêng, theo quyết định của user, hệ thống tái dùng đúng cơ chế mà chính Codex CLI/ChatGPT dùng: OAuth/PKCE thật với `auth.openai.com` (client_id public của Codex CLI, tái dùng không đăng ký app riêng), sau đó gọi thẳng `chatgpt.com/backend-api/codex/responses` — ăn quota gói ChatGPT Plus/Pro/Team của tài khoản đã đăng nhập, không qua `api.openai.com` chính thức. Cách này đã được xác nhận qua Porting Note đọc source thật `decolua/9router` (MIT license). Change này implement capability `ai-connection` dựa trên model khung đã tạo ở change `01-poc-foundation-domain-model`.

## What Changes

- Implement OAuth/PKCE flow thật với `auth.openai.com` dùng `client_id` public của Codex CLI (`app_EMoamEEZ73f0CkXaXp7hrann`), scope `openid profile email offline_access`, `code_challenge_method=S256`.
- Implement listener callback tạm thời trên cổng cố định `1455` (path `/auth/callback`) — chạy trong lúc connect flow trên cùng máy với `bin/dev` (đã xác nhận: POC chạy localhost dev, không phải remote multi-user).
- Implement token exchange + lưu `access_token`/`refresh_token`/`id_token` mã hoá vào `AIConnection`; trích `chatgptAccountId`/`chatgptPlanType` từ `id_token` để hiển thị gói đang dùng.
- Implement auto-refresh access token khi hết hạn (access token sống ~1h), **lưu refresh_token MỚI sau MỖI lần refresh** — refresh_token cũ bị revoke ngay khi refresh_token mới được cấp (tái dùng refresh_token cũ sẽ logout toàn bộ session ChatGPT của tài khoản đó).
- Implement Test Connection: gửi prompt thật tới `https://chatgpt.com/backend-api/codex/responses` với header `originator: codex_cli_rs` + `User-Agent` giả lập Codex CLI thật, nhận response thật hiển thị cho user.
- Đặt provider contract nhỏ giữa AI Operations và Codex adapter để các luồng AI hiện tại dùng chung seam; POC chỉ cài Codex, không triển khai provider khác hay registry/plugin framework.
- **Ngoài scope**: provider selector, nhiều connection trên mỗi user, provider metadata tổng quát và registry/plugin runtime.
- Implement ẩn token khỏi log/serializer/frontend.
- **BREAKING**: không áp dụng.

## Capabilities

### New Capabilities

- `ai-connection`: Quản lý kết nối AI provider (Codex, qua cơ chế ChatGPT backend-api không chính thức) — lưu credential mã hoá, test connection gửi/nhận prompt thật, không log raw token, không expose token ra frontend.

### Modified Capabilities

(không có)

## Impact

- **Code**: `affihub/app/operations/ai_connections/*`, provider contract và Codex adapter cô lập HTTP/OAuth tới `auth.openai.com`/`chatgpt.com/backend-api`, `affihub/app/controllers/ai_connections_controller.rb`, `affihub/app/forms/ai_connections/*`, `affihub/app/serializers/ai_connection_serializer.rb`, `affihub/app/views/ai_connections/*`. Change `04` sẽ gọi provider contract thay vì gọi Codex adapter trực tiếp.
- **Phụ thuộc**: cần change `01-poc-foundation-domain-model` đã archive (model `AIConnection` khung rỗng đã tồn tại).
- **Rủi ro cần ghi nhận rõ (không phải bug, là quyết định có chủ đích của user)**: endpoint `chatgpt.com/backend-api/codex/responses` không phải API chính thức được OpenAI công bố cho bên thứ ba — đây là endpoint nội bộ của ChatGPT mà Codex CLI gọi, bắt chước bằng header giả. Repo tham khảo `decolua/9router` tự đánh dấu provider này `deprecated: true` + `RISK_NOTICE` (rủi ro ToS, có thể bị OpenAI phát hiện/khoá tài khoản). User đã xác nhận chấp nhận rủi ro này cho mục đích POC.
- **Giới hạn deploy**: redirect URI cố định `http://localhost:1455/auth/callback` chỉ hoạt động khi Rails app và browser cùng chạy trên 1 máy (localhost dev) — không dùng được cho deploy remote nhiều người dùng nếu không thiết kế thêm cơ chế forward callback.
