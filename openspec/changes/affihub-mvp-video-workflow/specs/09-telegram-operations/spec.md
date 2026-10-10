# Spec Delta

## Purpose

Cho phép chủ AffiHub nhận cảnh báo vận hành và dừng hoặc tiếp tục automation từ xa qua bot Telegram được giới hạn bằng allowlist.

## ADDED Requirements

### Requirement: Gửi cảnh báo vận hành
Telegram bot MUST có thể báo worker down, Publication `Failed`/`OutcomeUnknown`, lỗi hoặc giới hạn API, lỗi auto-reply và lỗi sync đã hết retry.

#### Scenario: Publication chưa rõ kết quả
- **WHEN** Publication chuyển sang `OutcomeUnknown`
- **THEN** bot gửi cảnh báo có destination và bước kiểm tra phù hợp mà không đưa token hoặc secret vào tin nhắn

#### Scenario: Scheduler tự kích hoạt bài
- **WHEN** Scheduler claim một Publication auto-publish
- **THEN** bot gửi thông báo kết quả thành công hoặc thất bại khi có kết quả cuối

### Requirement: Giới hạn lệnh bằng chat allowlist
Bot MUST chỉ thực thi lệnh từ `chat_id` nằm trong allowlist cấu hình; token bot MUST không bị ghi vào log.

#### Scenario: Lệnh từ chat được phép
- **WHEN** chat trong allowlist gửi lệnh hợp lệ
- **THEN** AffiHub xác thực người gửi rồi thực hiện lệnh

#### Scenario: Lệnh từ chat không được phép
- **WHEN** chat ngoài allowlist gửi tin hoặc lệnh
- **THEN** AffiHub không thực hiện lệnh và không phản hồi để lộ cấu hình bot

### Requirement: Hỗ trợ lệnh trạng thái
Bot MUST hỗ trợ `/status` để trả trạng thái worker, Publication đang Scheduled/OutcomeUnknown và lỗi gần nhất.

#### Scenario: Chủ dự án hỏi status
- **WHEN** chat được phép gửi `/status`
- **THEN** bot trả trạng thái vận hành hiện tại mà không tiết lộ credential

### Requirement: Dừng và tiếp tục automation
Bot MUST hỗ trợ `/pause_auto_publish`, `/resume_auto_publish`, `/pause_auto_reply` và `/resume_auto_reply`.

#### Scenario: Pause auto-publish
- **WHEN** chat được phép gửi `/pause_auto_publish`
- **THEN** Scheduler dừng claim Publication mới từ lượt kế tiếp mà không cần restart worker

#### Scenario: Resume auto-reply
- **WHEN** chat được phép gửi `/resume_auto_reply`
- **THEN** AutoResponder tiếp tục claim comment mới theo rule hiện hành

### Requirement: Telegram lỗi không chặn AffiHub
Lỗi Telegram API MUST chỉ ảnh hưởng gửi thông báo hoặc nhận lệnh Telegram, không dừng dashboard, worker hoặc connector khác.

#### Scenario: Telegram API không khả dụng
- **WHEN** Bot API timeout hoặc trả lỗi
- **THEN** AffiHub ghi lỗi thông báo/điều khiển để xử lý và giữ các luồng local cùng publication độc lập
