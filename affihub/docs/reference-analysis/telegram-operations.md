# Telegram operations — Porting Note

Ngày đối chiếu: 2026-10-09

## Phạm vi

Telegram chỉ dùng cho cảnh báo vận hành và các lệnh emergency control trong OpenSpec `09-telegram-operations`. Không dùng bot để đăng video lên Telegram. Các lệnh được đặc tả là `/status`, `/pause_auto_publish`, `/resume_auto_publish`, `/pause_auto_reply` và `/resume_auto_reply`.

## Nguồn đã đọc

- [Telegram Bot API](https://core.telegram.org/bots/api), tài liệu hiện hành ghi Bot API 10.3 (2026-08-24). Đây là nguồn sự thật cho request, response và giới hạn API.
- [Telegram Bots FAQ](https://core.telegram.org/bots/faq), đối chiếu long polling, xác nhận update và giới hạn gửi tin.
- [`atipugin/telegram-bot-ruby` tại tag `v2.7.0`](https://github.com/atipugin/telegram-bot-ruby/tree/v2.7.0), đọc `README.md` và metadata hiển thị của repo. RubyGems hiện liệt kê `2.8.1` (2026-08-02), nên tag này chỉ là source reference đã kiểm tra; task 12.3 phải kiểm tra lại đúng phiên bản trước khi thêm dependency.
- [RubyGems metadata của `telegram-bot-ruby` 2.8.1](https://rubygems.org/gems/telegram-bot-ruby/versions/2.8.1) ghi `Licenses: No License`. GitHub tag page `v2.7.0` hiển thị nhãn `WTFPL`; file `LICENSE` không tải được trong lần đối chiếu này. Vì vậy thông tin `MIT` trong `PROJECT_SPEC.md` không có căn cứ và đã được thay bằng ghi chú về chênh lệch metadata. Cần xem xét license trước khi khóa gem làm runtime dependency.

## Bot API đã xác minh

### Nhận update

- Bot API chỉ cung cấp hai chế độ nhận update: `getUpdates` long polling hoặc `setWebhook`; hai chế độ loại trừ nhau.
- `getUpdates` trả update chưa xác nhận. Gọi lại với `offset` lớn hơn `update_id` sẽ xác nhận update; FAQ khuyến nghị `last_processed_update_id + 1`. Nếu chưa xác nhận, update có thể được gửi lại.
- `setWebhook` nhận HTTPS URL và gửi update bằng HTTPS POST. Có thể đặt `secret_token`; Telegram gửi giá trị đó trong header `X-Telegram-Bot-Api-Secret-Token`. Khi webhook đang bật thì `getUpdates` không dùng được.
- Telegram nói sẽ thử gửi lại webhook khi nhận HTTP status ngoài `2xx`, rồi dừng sau một số lần thử “reasonable”; tài liệu không cam kết con số retry cụ thể.

### Gửi tin nhắn

- `sendMessage` yêu cầu `chat_id` và `text`, trả về `Message` khi thành công. `text` dài từ 1 đến 4096 ký tự sau khi parse entities.
- Lời gọi Bot API đi qua HTTPS URL có dạng `https://api.telegram.org/bot<token>/METHOD_NAME`; bot token nằm trong URL path. Không ghi URL này vào log, exception, tracing, metrics hoặc thông báo lỗi.
- FAQ nêu các mức gửi hiện hành: tránh quá một tin mỗi giây trong một chat; tối đa 20 tin/phút trong group; broadcast khoảng 30 tin/giây trước khi có thể nhận `429`. Đây là giới hạn Telegram, không phải giá trị cấu hình nội bộ cố định của AffiHub.
- Response lỗi có `ok: false`, `description` và có thể có `parameters`; không xem `error_code` là giá trị ổn định vì tài liệu cho biết nó có thể thay đổi.

## Gem reference đã xác minh

README ở tag `v2.7.0` minh họa `Telegram::Bot::Client.run(token)`, `bot.listen`, và `bot.api.send_message(chat_id:, text:)`. `bot.api` bọc các method Bot API; gem dùng Faraday và mặc định dùng `NullLogger`. README nói muốn dùng webhook thì ứng dụng phải tự cung cấp webhook callback server; gem không cung cấp sẵn Rails webhook route/controller. Gem có `bot.stop` để dừng long-poll listener một cách graceful.

OpenSpec hiện chưa yêu cầu webhook route. Với AffiHub local-first, long polling là lựa chọn phù hợp để task 12.3 đánh giá vì không đòi public HTTPS callback server; đây là khuyến nghị kiến trúc, không phải bảo đảm runtime đã được thử. Nếu chọn webhook sau này, phải cập nhật design/routes trước khi thêm endpoint.

## Contract bắt buộc của AffiHub

1. Đọc `chat_id` từ update và kiểm tra allowlist ngay đầu xử lý, trước khi parse command, đọc trạng thái, đổi cờ hoặc gửi phản hồi. Chat ngoài allowlist bị bỏ qua im lặng, theo spec 09.
2. Chỉ xử lý năm command đã nêu ở phạm vi. Không diễn giải nội dung tự do thành lệnh, không gọi shell hoặc LLM.
3. Dùng token từ Rails credentials. Các giá trị không bí mật như `allowed_chat_ids`, trạng thái bật/tắt và giới hạn polling/retry đặt trong `config/telegram.yml`, đọc qua `Rails.application.config_for(:telegram)` theo quy ước dự án. Không đưa token vào YAML.
4. Bọc các lời gọi gem dùng chung theo task 12.3; không viết HTTP wrapper riêng. Redact token khỏi URL/exception vì token xuất hiện trong path của request.
5. Lỗi Bot API chỉ làm trạng thái nhận lệnh/gửi cảnh báo Telegram thất bại; không dừng dashboard, worker, publisher hoặc integration khác. Không retry publish chỉ vì Telegram gửi cảnh báo lỗi.
6. `update_id` có thể được gửi lại khi chưa xác nhận. Khi triển khai cần bảo đảm command pause/resume lặp không tạo side effect lặp; cơ chế lưu/dedupe update cụ thể thuộc task 12.2/12.3.

Allowlist `chat_id` là gate bảo mật bắt buộc theo OpenSpec. Nếu cấu hình chat dùng chung cho nhiều người, chỉ kiểm tra `chat_id` sẽ cho phép mọi thành viên của chat gửi command; spec hiện không có `user_id` allowlist. Task 12.2 cần giữ rõ giới hạn này hoặc cập nhật spec trước khi mở control cho group chat.

## Phần không suy diễn và cách kiểm chứng

- Không khẳng định Telegram webhook retry chính xác bao nhiêu lần; tài liệu chỉ nói một số lần hợp lý.
- README được kiểm tra ở tag `v2.7.0`, còn RubyGems có `2.8.1`; không suy ra tag nào sẽ được khóa trong Gemfile.
- Không dùng Postiz làm nguồn contract: `telegram.provider.ts` là adapter publish Telegram dựa trên `node-telegram-bot-api`, không phải bot operations Ruby của AffiHub.
- Chưa có token bot để gọi `getMe`, gửi/nhận update thật hoặc kiểm tra log runtime. Đây là kiểm chứng thuộc task implementation/smoke sau; note này chỉ xác nhận contract tài liệu và source đã đọc.

## Tài liệu OpenSpec

- `openspec/changes/affihub-mvp-video-workflow/specs/09-telegram-operations/spec.md`
- `openspec/changes/affihub-mvp-video-workflow/design.md`, mục Telegram operations
- `openspec/changes/affihub-mvp-video-workflow/tasks.md`, task 12.1–12.3
