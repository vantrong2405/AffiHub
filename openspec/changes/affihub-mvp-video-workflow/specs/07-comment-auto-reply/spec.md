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

### Requirement: Theo dõi comment sau publish
AffiHub MUST bắt đầu webhook hoặc polling comment chính thức sau khi publication trên Facebook/Instagram được xác nhận.

#### Scenario: Bài đăng được xác nhận
- **WHEN** platform xác nhận publication cuối cùng
- **THEN** AffiHub theo dõi comment mới cho destination đó nếu auto-reply đã được bật

### Requirement: Dedupe và đối soát reply
AffiHub MUST dùng khóa duy nhất theo destination và comment/event ID; timeout sau khi gửi reply MUST được đối soát trước khi retry hoặc nhận quyết định thủ công.

#### Scenario: Webhook comment gửi lặp
- **WHEN** cùng comment/event được nhận lại qua webhook hoặc polling
- **THEN** AffiHub chỉ tạo một tác vụ reply cho comment đó

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
