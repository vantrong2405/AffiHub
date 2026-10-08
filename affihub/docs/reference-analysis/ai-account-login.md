# Porting Note — đăng nhập tài khoản AI cho LLM

Ngày đối chiếu: 2026-10-08. Phạm vi: bốn lựa chọn người dùng yêu cầu là **ChatGPT, Antigravity, Gemini, Codex** để tạo script/scene prompts. Credential kỹ thuật MPT, MuAPI, stock footage và TTS vẫn do máy chủ quản lý.

## Repo tham khảo và file đã đọc

- [decolua/9router](https://github.com/decolua/9router), commit `a99cf57239ff778b61e434c2786009d5ed1c412c`: ứng dụng Next.js định tuyến nhiều AI provider. Đã đọc `docs/ARCHITECTURE.md`, `src/lib/oauth/providers/codex.js`, `src/lib/oauth/providers/antigravity.js`, `src/lib/oauth/providers/gemini-cli.js`, `src/lib/oauth/services/codex.js`, `src/lib/oauth/services/gemini.js`. Tham khảo cách chia provider adapter, OAuth state/PKCE và lưu connection. 9Router không phải nguồn cấp quyền cho AffiHub.
- 9Router dùng endpoint Cloud Code Assist nội bộ cho Antigravity/Gemini CLI và callback/token flow của client khác. **Không sao chép** endpoint nội bộ, client credential, phiên CLI, MITM, quota workaround hoặc giả định quyền sử dụng từ 9Router vào AffiHub.
- [openai/sign-in-with-chatgpt-devkit](https://github.com/openai/sign-in-with-chatgpt-devkit), commit `0a36fefeb913055c8c7a1a29b63d82b96b2e841a`: đã đọc `packages/local/src/oauth.ts`, `models.ts`, `responses.ts`, `storage.ts`, `examples/paste-perfect/`. Dùng làm repo tham khảo cho dynamic client registration, callback local, account-specific model list, Responses stream và bảo vệ credential. DevKit có Noncommercial License; AffiHub chỉ dựa contract/file map và tự tích hợp theo Rails, không đưa source DevKit vào bundle.
- [googleapis/google-auth-library-ruby](https://github.com/googleapis/google-auth-library-ruby), commit `01431c9ecd59e1efc5d262694971ded925044fdc`: đã đọc `lib/googleauth/web_user_authorizer.rb`, `lib/googleauth/user_authorizer.rb`, `lib/googleauth/user_refresh.rb`, `lib/googleauth/id_tokens/verifier.rb`. Đây là repo OAuth/OIDC Ruby chính thức để chọn cách dùng thư viện thay cho tự viết token verification/refresh.
- [jwt/ruby-jwt](https://github.com/jwt/ruby-jwt), commit `028d89e8ac613b5e140a3e026a32cfb2bc75fc86`: đã đọc `README.md` mục JWKS và `lib/jwt/jwk/set.rb`; repo tham khảo cho xác minh OpenAI ID token bằng signing key đã lấy từ issuer allowlist.
- Repo/code nội bộ AffiHub được tái sử dụng: `SocialConnections::CreateService`, `ConnectionCallbacks::ShowService`, `SocialConnection`, `Meta::Client#request`; AI stage hiện tại nằm ở `AiGenerations::CreateScriptService`, `AiGenerations::CreateScenePromptsService`, `Mpt::Client#generate_script/#generate_terms`. Mỗi thay đổi Ruby phải theo `affihub/CLAUDE.md`: controller gọi Service, Service điều phối bằng private `step_*`, Client gom HTTP qua một private request method và có RSpec trước implementation.
- [MPT v1.3.8 pinned source note](ai-video-mpt-vieneu.md): `/scripts` và `/terms` đi qua LLM provider/config của MPT; phải spike mọi điểm gọi LLM trước khi thay đường đăng nhập.

## Contract chính thức

- [OpenAI Sign in with ChatGPT quickstart](https://developers.openai.com/siwc/quickstart), [OAuth đăng nhập cho ứng dụng local/OSS](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [models/inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), [errors/recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery): OpenAI hiện có contract dynamic registration cho app nguồn mở/chạy local. Lần đầu dùng `client_id=dynamic_agent_client`, tên AffiHub và `ext_agent_host_id` ổn định; callback HTTP loopback phải là `127.0.0.1`, giữ nguyên scheme/host/path và cùng port giữa authorize/token exchange. Không cần client secret hoặc API key đối tác. Mỗi lần dùng state, nonce, PKCE S256; xác minh ID token/JWKS/issuer/audience/nonce và scope `chatgpt.tokens.use.direct`. Identity sign-in không đồng nghĩa quyền dùng plan. Danh sách model lấy bằng OAuth token của account; inference dùng Responses API công khai với `store: false`, `stream: true`, chỉ thành công ở `response.completed`.
- [OpenAI Codex app-server](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server): Codex dùng cùng OAuth token Sign in with ChatGPT khi được cấp quyền. **Codex là lựa chọn UI/model, không phải OAuth provider thứ hai.** Không đọc file phiên Codex CLI.
- [OpenAI website sign-in availability](https://developers.openai.com/siwc/website) và [Sign in with ChatGPT Terms](https://openai.com/policies/sign-in-with-chatgpt-terms/): luồng web identity-only hiện chỉ mở cho đối tác thương mại được chọn; AffiHub không dùng luồng đó. Luồng OSS/local plan usage phải phát sinh từ runtime local do chính user kiểm soát, chỉ phục vụ app đã kết nối, không chia sẻ token/quota giữa người dùng và không thu phí người dùng cho phần dùng plan. Nếu AffiHub được phân phối như dịch vụ thương mại/remote, phải xin client/approval riêng trước khi mở đường đó.
- [Google Gemini API OAuth](https://ai.google.dev/gemini-api/docs/oauth), [GenerateContent API reference](https://ai.google.dev/api/generate-content), [OAuth web-server flow](https://developers.google.com/identity/protocols/oauth2/web-server): có hướng dẫn OAuth quickstart cho Gemini API qua Google Cloud project, Generative Language API, OAuth consent/client và credential người dùng. Quickstart tự giới hạn là cấu hình thử nghiệm; cần kiểm chứng web-app OAuth scope, consent verification, quota/billing và inference thật cho AffiHub trước khi mở. Trang GenerateContent chưa đưa ví dụ REST OAuth tương ứng. Đường này tách khỏi đăng nhập Gemini CLI và kết nối Google Drive/YouTube.
- [Gemini CLI terms/privacy](https://geminicli.com/docs/resources/tos-privacy/): không dùng OAuth của Gemini CLI trong ứng dụng bên thứ ba để tiêu thụ quyền/hạn mức CLI.
- [Google Antigravity terms](https://www.antigravity.google/terms): điều 6 cấm phần mềm bên thứ ba truy cập dịch vụ bằng Antigravity OAuth và nêu nguy cơ đình chỉ tài khoản. **Lựa chọn Antigravity hiện chưa khả dụng**; chỉ đánh giá lại khi Google công bố contract cho AffiHub hoặc cấp quyền phù hợp. Không dùng luồng nội bộ từ 9Router.

## Quyết định sản phẩm

| Lựa chọn UI | Kết nối thực tế | Trạng thái trước khi xác minh |
| --- | --- | --- |
| ChatGPT | OpenAI Sign in with ChatGPT dynamic registration cho runtime local, kèm quyền ChatGPT plan usage | Có contract chính thức cho app local/OSS; account, scope, model và request thật vẫn phải được xác minh |
| Codex | Cùng OpenAI connection; UI có thể chọn capability/model được account trả về | Không đăng nhập Codex riêng, không đọc session Codex CLI; không suy diễn entitlement từ tên model |
| Gemini | Google OAuth cho **Gemini API** của project AffiHub | Chờ xác minh scope/consent, quota/billing và inference thật; không dùng Gemini CLI token |
| Antigravity | Chưa có contract tích hợp bên thứ ba phù hợp | Hiện “Chưa khả dụng”; không có nút khởi tạo OAuth |

Không yêu cầu người dùng dán API key LLM. OAuth token mã hóa trong Rails DB, không trả ra HTML/log; provider/model và connection được snapshot theo generation. Token của OpenAI chỉ gọi endpoint được cấp quyền, không chuyển vào MPT Chat Completions. Script/scene có thể cần Rails LLM Client riêng, còn MPT tiếp tục video pipeline. Nếu chưa chứng minh được contract kết nối và đường LLM, khóa riêng bước LLM; import/edit/render/export local vẫn dùng được.

Hạn mức ChatGPT plan không phải báo giá tiền từng lượt và không được ghi thành giá 0. Gemini API phải hiển thị nguồn giá/quota theo project thật; nếu không có estimate đáng tin cậy cho khoản tính tiền bắt buộc thì chặn job trả phí. MuAPI/stock/TTS vẫn theo cost gate hiện có.

## Cổng trước khi bật

1. OpenAI: hoàn thành dynamic registration chính thức cho runtime local, callback thật và một request Responses API hoàn tất với account/model được cấp; không lưu token vào `.env`, chỉ lưu credential mã hóa trong DB local do user kiểm soát.
2. Gemini: tạo Google Cloud project/OAuth client dành cho AffiHub, xác minh scope/consent production, quota/billing, callback và một request Gemini API thật; không dùng credential Gemini CLI.
3. MPT: kiểm tra source đã pin ở `/scripts`, `/terms`, `/videos`; xác định adapter hoặc tách stage LLM sang Rails mà vẫn giữ video pipeline. Kiểm tra refresh, thu hồi, đổi tài khoản, hết hạn mức và redaction.
4. Antigravity: giữ gate đóng cho tới khi có contract hoặc chấp thuận chính thức phù hợp cho AffiHub; bản thân 9Router không chứng minh quyền này.

## Trạng thái cấu hình tài khoản ngày 2026-10-08

- Đã tạo Google Cloud project riêng `AffiHub MVP`, project ID `affihub-mvp`, và bật `generativelanguage.googleapis.com`.
- Google Auth Platform đã cấu hình app External ở chế độ Testing, thêm tài khoản hiện tại làm test user, chấp nhận Google API Services User Data Policy và tạo OAuth Web client có callback `http://localhost:3000/ai/auth/callback`.
- Client ID/secret của ứng dụng được lưu trong `affihub/.env` (file local bị Git ignore, quyền `0600`); user access/refresh token và mật khẩu không nằm trong file này. Billing chưa liên kết.
- Gemini OAuth quickstart xác nhận bearer-token cho `GET /v1/models` cùng `x-goog-user-project`, và ví dụ Python đưa OAuth credentials vào Google Gen AI SDK. Tuy nhiên quickstart tự giới hạn là cấu hình đơn giản cho môi trường thử nghiệm; API reference `models.generateContent` hiện minh họa API key và không có request REST OAuth tương ứng. Cần smoke test thực tế bằng OAuth Web client cho `generateContent`, kiểm tra scope/refresh/quota/billing, trước khi bật Gemini hoặc đánh dấu đường inference đã xác minh.
- Tài liệu OpenAI hiện xác nhận dynamic registration cho app local/OSS không cần static client ID hay client secret. Chưa hoàn tất callback thật, chưa biết account có cấp scope/model ChatGPT plan usage hay không; chưa ghi nhận runtime inference.
