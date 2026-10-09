# Spec Delta

## Purpose

Cho phép người dùng tùy chọn sao lưu render lên Google Drive và đồng bộ mỗi Publication vào Google Sheets mà không chuyển quyền authoritative khỏi database local.

## ADDED Requirements

### Requirement: Kết nối Google là tùy chọn
AffiHub MUST cho phép bỏ qua Drive/Sheets hoặc kết nối sau mà không chặn source, edit, render, local export hay publish.

#### Scenario: Google chưa cấu hình
- **WHEN** người dùng chưa kết nối Drive hoặc Sheets
- **THEN** các luồng video tiếp tục độc lập và audit hiển thị `Chưa cấu hình` cho integration tương ứng

### Requirement: Google sync không phát sinh phí và không cần thẻ thanh toán
AffiHub MUST chỉ dùng hạn mức tiêu chuẩn của Google Drive/Sheets API; MUST NOT yêu cầu người dùng thêm thẻ, bật Google Cloud Billing, mua dung lượng, xin tăng quota trả phí hoặc tự chuyển sang dịch vụ trả phí. Khi quota API hoặc dung lượng Drive miễn phí của tài khoản hết, AffiHub MUST dừng side job Google tương ứng và báo trạng thái; MUST giữ nguyên source/render local cùng các luồng edit, export và publish.

#### Scenario: Quota Google API tiêu chuẩn đã hết
- **WHEN** Google từ chối thao tác vì quota tiêu chuẩn đã hết
- **THEN** AffiHub giữ side job ở trạng thái chờ quota khả dụng, không bật billing hoặc xin quota trả phí, và giữ các luồng video local hoạt động

#### Scenario: Google API trả rate limit tạm thời
- **WHEN** Drive hoặc Sheets trả rate-limit có thể hồi phục như `429` hoặc `userRateLimitExceeded`
- **THEN** AffiHub retry bằng exponential backoff có giới hạn theo cấu hình, không retry vô hạn hoặc xin quota trả phí

#### Scenario: Dung lượng Drive miễn phí đã hết
- **WHEN** Google từ chối upload vì tài khoản không còn dung lượng
- **THEN** AffiHub báo cần giải phóng dung lượng Drive, không mua thêm dung lượng, và giữ render local cùng trạng thái publication

### Requirement: Bảo vệ Google OAuth và token
Drive/Sheets OAuth MUST dùng state ngẫu nhiên, hết hạn, dùng một lần và gắn phiên; dùng PKCE khi hỗ trợ, callback allowlist, scope tối thiểu, mã hóa access/refresh token và không log secret.

#### Scenario: Callback Google bị replay hoặc sai phiên
- **WHEN** state Google đã dùng, hết hạn hoặc callback đến từ phiên khác
- **THEN** AffiHub từ chối callback và không lưu token

#### Scenario: Google scope chỉ đủ thao tác đã chọn
- **WHEN** người dùng chỉ bật Drive hoặc chỉ bật Sheets
- **THEN** AffiHub chỉ yêu cầu scope cần cho dịch vụ đã chọn và đánh dấu reconnect nếu refresh token không còn dùng được

### Requirement: Đồng bộ tại điểm xác nhận người dùng
AffiHub MUST bắt đầu nhánh Drive/Sheets riêng khi người dùng xác nhận publish thủ công hoặc lưu lịch auto-publish đã xác nhận.

#### Scenario: Publish thủ công được xác nhận
- **WHEN** người dùng bấm đăng cho render version và destination
- **THEN** Drive/Sheets jobs được xếp riêng song song với Publication

#### Scenario: Lưu lịch auto-publish
- **WHEN** người dùng lưu lịch cho render version và destination
- **THEN** nhánh Drive/Sheets bắt đầu theo cùng render version mà không chờ Scheduler gửi bài

### Requirement: Backfill có chọn lọc sau khi kết nối Google
Khi người dùng kết nối Drive/Sheets sau khi đã có video, AffiHub MUST chỉ đồng bộ project/render version mà người dùng chọn tường minh; MUST NOT tự đẩy toàn bộ thư viện.

#### Scenario: Người dùng chọn render cũ để đồng bộ
- **WHEN** người dùng kết nối Google và chọn một hoặc nhiều project/render version để backfill
- **THEN** AffiHub xếp các side job tương ứng và hiển thị trạng thái riêng cho từng mục đã chọn

#### Scenario: Kết nối Google không kèm lựa chọn backfill
- **WHEN** OAuth hoàn tất nhưng người dùng chưa chọn project/render version nào để đồng bộ lại
- **THEN** AffiHub không quét hoặc đồng bộ thư viện cũ tự động

### Requirement: Lưu render version riêng tư trên Drive
AffiHub MUST tạo subfolder theo project/video và upload từng MP4 render export bằng resumable upload với quyền kế thừa folder gốc, không tự đặt file/folder thành public.

#### Scenario: Drive upload hoàn tất
- **WHEN** người dùng đã kết nối Drive và file render sẵn sàng
- **THEN** AffiHub lưu ID/URL thư mục và file theo đúng render version

### Requirement: Chống tạo bản trùng trên Drive
AffiHub MUST dùng folder key ổn định theo project/video và file key riêng theo render version/export, rồi dò lại object bằng metadata trước khi tạo lại sau timeout.

#### Scenario: Drive tạo file nhưng response timeout
- **WHEN** Drive có thể đã tạo folder/file nhưng AffiHub chưa nhận response cuối
- **THEN** worker tìm lại bằng metadata/idempotency key trước khi tạo folder hoặc upload lần nữa

#### Scenario: Cùng video có render version mới
- **WHEN** người dùng tạo một render export khác cho cùng project/video
- **THEN** AffiHub dùng lại subfolder video và tạo/tìm file theo key của render version/export mới

#### Scenario: Drive lookup lỗi hoặc không kết luận được
- **WHEN** worker không thể xác định folder/file đã được tạo hay chưa
- **THEN** sync giữ `OutcomeUnknown`, tiếp tục reconcile hoặc yêu cầu người dùng xử lý thủ công; không coi “chưa tìm thấy” là căn cứ đủ để tạo bản mới

#### Scenario: Người dùng xử lý Drive result thủ công
- **WHEN** API không cho phép đối soát chắc chắn
- **THEN** AffiHub lưu một trong ba kết quả “đã xảy ra” kèm reference/bằng chứng, “chắc chắn chưa xảy ra” kèm xác nhận rủi ro trước retry, hoặc “vẫn chưa rõ” để tiếp tục chặn

### Requirement: Upsert một hàng Sheets theo Publication
AffiHub MUST duy trì một hàng hiện trạng mới nhất cho mỗi project, render version và destination, gồm caption/tóm tắt, link Drive, trạng thái Publication gần nhất, `platform_post_id`, permalink, `published_at`, lỗi liên quan và thời điểm cập nhật; Rails database giữ đầy đủ lịch sử Publication theo từng occurrence.

#### Scenario: Hàng đã tồn tại
- **WHEN** sync retry tìm thấy `sheet_row_key` đã có
- **THEN** AffiHub cập nhật hàng đó thay vì append hàng mới

#### Scenario: Hàng chưa tồn tại
- **WHEN** chưa có hàng cho render version/destination
- **THEN** AffiHub thêm đúng một hàng theo key và ghi dữ liệu dạng `RAW`

#### Scenario: Publication đã có kết quả nền tảng
- **WHEN** destination xác nhận Publication ở trạng thái cuối
- **THEN** AffiHub upsert `platform_post_id`, permalink và `published_at` tương ứng vào cùng hàng render version/destination

#### Scenario: Publication định kỳ có kết quả mới
- **WHEN** một occurrence mới của Schedule có trạng thái hoặc kết quả publish cần đồng bộ
- **THEN** AffiHub upsert cùng hàng render version/destination thành trạng thái mới nhất, còn các Publication occurrence trước vẫn có thể tra cứu trong Rails

### Requirement: Giữ Rails database authoritative
Rails database MUST giữ trạng thái đồng bộ chính; Drive/Sheets chỉ là bản phụ và không thay thế trạng thái Publication.

#### Scenario: Sheets lỗi sau Drive upload
- **WHEN** Drive upload thành công nhưng Sheets upsert thất bại
- **THEN** AffiHub chỉ retry SheetSync và giữ kết quả Drive/Publication hiện có

### Requirement: Cô lập lỗi Google với publish
Lỗi Drive hoặc Sheets MUST không làm render lại, gửi lại Publication hoặc chặn connector khác.

#### Scenario: Google API trả lỗi
- **WHEN** Drive hoặc Sheets trả lỗi hoặc timeout
- **THEN** AffiHub hiển thị trạng thái retry của integration đó và không gọi publisher lần nữa

### Requirement: Hiển thị trạng thái kết nối lại
AffiHub MUST hiển thị trạng thái riêng cho Drive, Sheets và thời hạn OAuth để người dùng biết khi nào cần kết nối lại.

#### Scenario: OAuth hết hạn
- **WHEN** Google refresh token không còn dùng được
- **THEN** AffiHub đánh dấu integration cần kết nối lại và giữ nguyên dữ liệu local cùng trạng thái retry
