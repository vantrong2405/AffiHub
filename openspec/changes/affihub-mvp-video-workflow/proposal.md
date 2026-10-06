# Proposal

## Why

`affihub/docs/PROJECT_SPEC.md` đã mô tả một sản phẩm local-first hoàn chỉnh, nhưng workspace chưa có OpenSpec contract để chia yêu cầu thành hành vi có thể triển khai và nghiệm thu. Luồng video đi qua nhiều worker và API độc lập; cần khóa rõ ranh giới giữa xử lý video, preflight, publish đã được nền tảng xác nhận và các tác vụ phụ để tránh đăng trùng hoặc báo thành công sai.

## What Changes

- Đặc tả end-to-end MVP từ import/tải/khám phá nguồn hoặc tạo video bằng AI, qua biên tập và render version bất biến, đến preflight và đăng thủ công hoặc theo lịch.
- Tách yêu cầu thành các capability cho nguồn video, AI generation, editor/render, preflight, social connection, multi-platform publishing, auto-reply bình luận, Google Drive/Sheets và Telegram.
- Quy định trạng thái, xử lý timeout và phục hồi theo từng luồng: database Rails là nguồn trạng thái authoritative; tác vụ có thể phát sinh side effect bên ngoài phải có idempotency/reconciliation; `Published` chỉ ghi sau xác nhận cuối từ nền tảng. Lỗi dịch vụ phụ không được gọi lại publisher.
- Giữ phạm vi local-first; luồng nhập video, editor và local export không cần credential mạng xã hội, còn mỗi connector có thể lỗi độc lập với các luồng khác.
- Khi nội dung trong các mục cũ xung đột, dùng mục 13 của `PROJECT_SPEC.md` làm căn cứ mới nhất. Cụ thể, auto-reply MVP chỉ xử lý comment công khai trên Facebook/Instagram; không bao gồm DM, Messenger hoặc inbox. Upload Instagram dùng resumable file upload trực tiếp, không yêu cầu public media URL.
- **Ngoài phạm vi:** cơ chế né phát hiện/chống khóa tài khoản; scraping bằng Playwright/browser automation hoặc discovery không có endpoint chính thức; auto-reply TikTok hay nội dung trả lời do AI tự sinh; DM/Messenger; đăng Facebook profile cá nhân; xóa logo chuyển động/thay phông gốc; đồng bộ nhân vật giữa các cảnh AI; hosted service luôn chạy; và cam kết ROI khi chưa có baseline do khách hàng xác nhận.
- Việc nền tảng duyệt app/quyền production được thể hiện thành trạng thái và gate theo từng connector; OpenSpec không cam kết thời hạn duyệt bên ngoài. Nghiệm thu kỹ thuật và mức sẵn sàng đăng công khai phải được ghi riêng.

## Capabilities

### New Capabilities

- `01-video-source-ingestion`: Import file local, tải URL nền theo route phù hợp với nền tảng (`yt-dlp` best-effort ngoài YouTube; YouTube chỉ dùng route được chấp thuận), discovery qua API chính thức khi có, provenance, `ffprobe`, giới hạn tải và fallback thủ công.
- `02-ai-video-generation`: Pipeline MoneyPrinterTurbo cho script, scene prompts, báo giá, xác nhận chi phí, tạo clip/TTS/subtitle và đối soát job chưa rõ kết quả.
- `03-video-editing-rendering`: Editor timeline dùng chung cho mọi nguồn, preview/so sánh, thao tác FFmpeg, local export và `RenderVersion` bất biến.
- `04-media-preflight`: Một lượt audit không phá huỷ cho source, render, đích đăng, connector, worker và integration đang bật; trả trạng thái, lý do và bước khắc phục.
- `05-social-account-connections`: Kết nối nhiều profile, chọn Page/kênh/tài khoản và kiểm tra quyền riêng cho Facebook, TikTok, Instagram và YouTube.
- `06-multi-platform-publishing`: Publication riêng theo đích, publish thủ công/lên lịch, giao thức upload riêng từng nền tảng, giới hạn nội bộ, idempotency, reconciliation và trạng thái cuối.
- `07-comment-auto-reply`: Rule câu trả lời cố định/keyword cho comment công khai trên Facebook/Instagram, dedupe event và log kết quả.
- `08-google-drive-sheets-sync`: Tích hợp tùy chọn, đồng bộ nền theo render version/publication, upsert idempotent và retry độc lập.
- `09-telegram-operations`: Cảnh báo, `/status`, pause/resume automation và allowlist `chat_id`.
- `10-background-worker-reliability`: Claim nguyên tử, lease/heartbeat/fencing, phát hiện job treo và phục hồi side effect sau restart.

### Modified Capabilities

Không có. `openspec/specs/` hiện chưa có capability nào.

## Impact

Thay đổi artifact tại workspace `openspec/`; khi được áp dụng sẽ ảnh hưởng tới ứng dụng Rails trong `affihub/`, PostgreSQL, Solid Queue, FFmpeg, service MoneyPrinterTurbo và các connector chính thức của Meta, TikTok, YouTube, Google cùng Telegram. Database local tiếp tục là nguồn dữ liệu chính; Google Drive/Sheets và Telegram là integration tùy chọn. Vì `affihub/` hiện chỉ có tài liệu, bước đầu tiên dựng Rails/RSpec scaffold đúng `CLAUDE.md`; AI generation nhận topic/language/tone/target duration, Sheets lưu kết quả publish dùng chung và chỉ backfill các project/render được người dùng chọn, còn UI MVP mặc định dùng tiếng Việt. Theo quy ước workspace, mỗi task triển khai tính năng sẽ có bước viết và chạy RSpec thất bại trước bước code; task UI phải qua skill `ui-ux`, còn tích hợp API cần đối chiếu tài liệu chính thức và cấu hình endpoint qua YAML/`Rails.application.config_for`.
