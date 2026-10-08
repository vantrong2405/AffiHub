# Porting Note — đăng nhập tài khoản AI cho LLM

Ngày đối chiếu: 2026-10-08. Phạm vi: bốn lựa chọn người dùng yêu cầu là **ChatGPT, Antigravity, Gemini, Codex** để tạo script/scene prompts. Credential kỹ thuật MPT, MuAPI, stock footage và TTS vẫn do máy chủ quản lý.

## Repo tham khảo và file đã đọc

- [decolua/9router](https://github.com/decolua/9router), commit `a99cf57239ff778b61e434c2786009d5ed1c412c`: ứng dụng Next.js định tuyến nhiều AI provider. Đã đọc `docs/ARCHITECTURE.md`, `src/lib/oauth/providers/codex.js`, `src/lib/oauth/providers/antigravity.js`, `src/lib/oauth/providers/gemini-cli.js`, `src/lib/oauth/services/codex.js`, `src/lib/oauth/services/gemini.js`. Tham khảo cách chia provider adapter, OAuth state/PKCE và lưu connection. 9Router không phải nguồn cấp quyền cho AffiHub.
- 9Router dùng endpoint Cloud Code Assist nội bộ cho Antigravity/Gemini CLI và callback/token flow của client khác. **Không sao chép** endpoint nội bộ, client credential, phiên CLI, MITM, quota workaround hoặc giả định quyền sử dụng từ 9Router vào AffiHub.
- [MPT v1.3.8 pinned source note](ai-video-mpt-vieneu.md): `/scripts` và `/terms` đi qua LLM provider/config của MPT; phải spike mọi điểm gọi LLM trước khi thay đường đăng nhập.

## Contract chính thức

- [OpenAI Sign in with ChatGPT](https://developers.openai.com/siwc/quickstart), [OAuth sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [models/inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference): quyền danh tính và quyền dùng gói là riêng; ứng dụng/tài khoản phải đủ điều kiện ChatGPT plan usage. OAuth dùng state, nonce, PKCE S256, callback loopback, ID token/scope validation. Inference được cấp quyền đi qua Responses API; thành công khi có `response.completed`.
- [OpenAI Codex app-server](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server): Codex dùng cùng OAuth token Sign in with ChatGPT khi được cấp quyền. **Codex là lựa chọn UI/model, không phải OAuth provider thứ hai.** Không đọc file phiên Codex CLI.
- [Google Gemini API OAuth](https://ai.google.dev/gemini-api/docs/oauth): có đường OAuth chính thức cho Gemini API qua Google Cloud project, Generative Language API, OAuth consent/client và credential người dùng. Quickstart là môi trường thử nghiệm; cần kiểm chứng web-app OAuth scope, consent verification, quota/billing và inference thật cho AffiHub trước khi mở. Đường này tách khỏi đăng nhập Gemini CLI và kết nối Google Drive/YouTube.
- [Gemini CLI terms/privacy](https://geminicli.com/docs/resources/tos-privacy/): không dùng OAuth của Gemini CLI trong ứng dụng bên thứ ba để tiêu thụ quyền/hạn mức CLI.
- [Google Antigravity terms](https://www.antigravity.google/terms): điều 6 cấm phần mềm bên thứ ba truy cập dịch vụ bằng Antigravity OAuth và nêu nguy cơ đình chỉ tài khoản. **Lựa chọn Antigravity hiện chưa khả dụng**; chỉ đánh giá lại khi Google công bố contract cho AffiHub hoặc cấp quyền phù hợp. Không dùng luồng nội bộ từ 9Router.

## Quyết định sản phẩm

| Lựa chọn UI | Kết nối thực tế | Trạng thái trước khi xác minh |
| --- | --- | --- |
| ChatGPT | OpenAI Sign in with ChatGPT, kèm quyền ChatGPT plan usage | Chờ xác minh quyền ứng dụng/tài khoản và request thật |
| Codex | Cùng OpenAI connection; chỉ hiện model/khả năng được tài khoản cấp | Chờ quyền ChatGPT và model tương ứng; không đăng nhập Codex riêng |
| Gemini | Google OAuth cho **Gemini API** của project AffiHub | Chờ xác minh scope/consent, quota/billing và inference thật; không dùng Gemini CLI token |
| Antigravity | Chưa có contract tích hợp bên thứ ba phù hợp | Hiện “Chưa khả dụng”; không có nút khởi tạo OAuth |

Không yêu cầu người dùng dán API key LLM. OAuth token mã hóa trong Rails DB, không trả ra HTML/log; provider/model và connection được snapshot theo generation. Token của OpenAI chỉ gọi endpoint được cấp quyền, không chuyển vào MPT Chat Completions. Script/scene có thể cần Rails LLM Client riêng, còn MPT tiếp tục video pipeline. Nếu chưa chứng minh được contract kết nối và đường LLM, khóa riêng bước LLM; import/edit/render/export local vẫn dùng được.

Hạn mức ChatGPT plan không phải báo giá tiền từng lượt và không được ghi thành giá 0. Gemini API phải hiển thị nguồn giá/quota theo project thật; nếu không có estimate đáng tin cậy cho khoản tính tiền bắt buộc thì chặn job trả phí. MuAPI/stock/TTS vẫn theo cost gate hiện có.

## Cổng trước khi bật

1. OpenAI: xác minh AffiHub được cấp ChatGPT plan usage, callback thật và một request Responses API hoàn tất với account/model được cấp.
2. Gemini: tạo Google Cloud project/OAuth client dành cho AffiHub, xác minh scope/consent production, quota/billing, callback và một request Gemini API thật; không dùng credential Gemini CLI.
3. MPT: kiểm tra source đã pin ở `/scripts`, `/terms`, `/videos`; xác định adapter hoặc tách stage LLM sang Rails mà vẫn giữ video pipeline. Kiểm tra refresh, thu hồi, đổi tài khoản, hết hạn mức và redaction.
4. Antigravity: giữ gate đóng cho tới khi có contract hoặc chấp thuận chính thức phù hợp cho AffiHub; bản thân 9Router không chứng minh quyền này.
