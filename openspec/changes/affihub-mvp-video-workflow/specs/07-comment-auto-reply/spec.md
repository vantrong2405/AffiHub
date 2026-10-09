# Spec Delta

## Purpose

Cho phép người dùng tự trả lời comment công khai trên Facebook và Instagram bằng rule cố định, đồng thời theo dõi kết quả và ngăn event lặp tạo nhiều reply.

## ADDED Requirements

### Requirement: Giới hạn nền tảng và loại hội thoại
MVP MUST xử lý comment công khai trên Facebook và Instagram; không xử lý TikTok comments, DM, Messenger hoặc inbox.

#### Scenario: Nhận comment hỗ trợ
- **WHEN** Facebook hoặc Instagram gửi comment công khai mới trên destination đã cấu hình
- **THEN** AffiHub đưa comment vào quy trình khớp rule

#### Scenario: Nhận loại hội thoại ngoài phạm vi
- **WHEN** event là DM, Messenger, inbox hoặc TikTok comment
- **THEN** AffiHub không tạo reply và không báo đây là luồng auto-reply được hỗ trợ

### Requirement: Reply theo câu cố định và keyword rule
AffiHub MUST dùng một câu trả lời mặc định cố định cho destination và chỉ dùng nội dung thay thế từ keyword rule tĩnh do người dùng cấu hình.

#### Scenario: Không khớp keyword
- **WHEN** comment mới không khớp keyword override
- **THEN** AffiHub chọn câu mặc định của destination

#### Scenario: Khớp keyword override
- **WHEN** comment khớp một keyword rule đang bật
- **THEN** AffiHub chọn đúng câu trả lời tĩnh của rule đó và không gọi LLM để sinh nội dung

#### Scenario: Nhiều keyword cùng khớp
- **WHEN** nhiều keyword rule đang bật cùng khớp một comment
- **THEN** AffiHub chọn keyword dài nhất; nếu độ dài bằng nhau thì chọn rule được tạo trước

### Requirement: Nhận comment bằng Meta webhook
AffiHub MUST nhận comment qua Meta Webhooks chính thức: Page field `feed` cho Facebook và field `comments` cho Instagram Business qua Facebook Login. App subscription chỉ được bật khi destination có default rule đang hoạt động. Callback phải xác minh `hub.verify_token` cho GET handshake và HMAC-SHA256 header `X-Hub-Signature-256` trên raw body POST trước khi xử lý payload.

#### Scenario: Xác minh webhook callback
- **WHEN** Meta gọi GET callback với `hub.mode=subscribe` và verify token trùng cấu hình bí mật
- **THEN** AffiHub trả `hub.challenge`; token sai bị từ chối và challenge không được trả

#### Scenario: Nhận comment Facebook mới
- **WHEN** webhook Page có `field=feed`, `item=comment`, `verb=add` và destination Page đã bật default rule
- **THEN** AffiHub nhận `comment_id` cùng `message`, bỏ qua event ngoài loại comment hoặc comment do chính Page gửi, rồi tạo một workflow nền

#### Scenario: Nhận comment Instagram mới
- **WHEN** webhook Instagram có `field=comments`, comment cấp đầu có `id` và `text`, và destination đã bật default rule
- **THEN** AffiHub tạo một workflow nền; bỏ qua field khác, comment do account tự gửi, comment cấp reply và payload thiếu ID/nội dung

#### Scenario: Từ chối webhook không hợp lệ
- **WHEN** chữ ký POST không khớp raw request body hoặc JSON không hợp lệ
- **THEN** AffiHub không tạo AutoReplyEvent/WorkflowRun và không gọi provider reply API

### Requirement: Dedupe và đối soát reply
AffiHub MUST dùng khóa duy nhất theo destination và comment/event ID; timeout sau khi gửi reply MUST được đối soát trước khi retry hoặc nhận quyết định thủ công.

#### Scenario: Webhook comment gửi lặp
- **WHEN** cùng comment/event được Meta gửi lại trong notification retry
- **THEN** AffiHub chỉ tạo một tác vụ reply cho comment đó

#### Scenario: Bài đăng chưa bật auto-reply
- **WHEN** webhook đến destination không có default rule đang hoạt động
- **THEN** AffiHub không tạo tác vụ reply

#### Scenario: Timeout khi gửi reply
- **WHEN** API có thể đã nhận reply nhưng response timeout
- **THEN** AffiHub ghi trạng thái chưa rõ, đối soát trước retry và không gửi reply thứ hai khi kết quả còn chưa rõ

#### Scenario: Người dùng xử lý kết quả không thể đối soát
- **WHEN** API không hỗ trợ lookup đủ tin cậy cho reply chưa rõ
- **THEN** AffiHub cho người dùng ghi “đã xảy ra” kèm URL/reference và bằng chứng, “chắc chắn chưa xảy ra” kèm xác nhận rủi ro trước retry, hoặc “vẫn chưa rõ” để tiếp tục chặn; mọi lựa chọn được lưu audit và không tự đổi thành `Sent`

### Requirement: Ghi log kết quả auto-reply
AffiHub MUST append-only log nguồn/event type, destination, default/override rule, nội dung reply thực tế, trạng thái, lỗi và bằng chứng xử lý thủ công nếu có.

#### Scenario: Reply hoàn tất
- **WHEN** platform xác nhận reply đã gửi
- **THEN** AffiHub lưu xác nhận cuối và hiển thị kết quả trong log

#### Scenario: Reply thất bại
- **WHEN** platform trả lỗi hoặc không thể xác nhận kết quả
- **THEN** AffiHub lưu lỗi/trạng thái tương ứng và không báo reply thành công

#### Scenario: Rule thay đổi sau lần reply
- **WHEN** người dùng sửa hoặc xóa rule sau khi reply đã được gửi
- **THEN** log cũ vẫn giữ snapshot rule và nội dung reply đã dùng để có thể audit lại

### Requirement: Hỗ trợ pause auto-reply
AutoResponder MUST kiểm tra cờ pause trước mỗi lần claim comment mới.

#### Scenario: Auto-reply đang pause
- **WHEN** cờ pause được bật
- **THEN** worker không claim comment mới cho tới khi được resume, còn log và trạng thái hiện có vẫn được giữ
