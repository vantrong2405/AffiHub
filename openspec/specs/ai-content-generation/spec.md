# ai-content-generation Specification

## Purpose
Sinh Content (hook/caption/CTA/hashtags) từ Product thật qua provider contract (POC dùng Codex), quản lý lifecycle duyệt nội dung trước khi publish, giữ nguyên Product facts và affiliate URL gốc. Nội dung do AI tạo là bản nháp cần human review; hệ thống không cam kết tự phát hiện mọi claim sai.

## Requirements

### Requirement: Generate Content từ Product facts thật
Hệ thống SHALL chỉ cho `current_user` generate từ Product thuộc user đó; SHALL gửi các facts thật của Product (title, description, price, original_price, discount, rating, sold) cùng platform=Facebook và tone tới AI provider đang kết nối để sinh hook/caption/CTA/hashtags; hệ thống tự attach `affiliate_url` của Product vào Content sau khi sinh, AI không được trả hoặc tự chèn affiliate_url. POC hiện dùng Codex.

#### Scenario: Tạo Content từ Product Library
- **WHEN** sau khi import hoàn tất, user chọn một Product trong Product Library đã có affiliate link và bấm Generate Content
- **THEN** hệ thống gọi AI provider đang kết nối với facts của Product, tạo một row `Content` mới gắn `affiliate_url` do application tự attach (không phải do AI trả về); `Content` đi qua trạng thái nội bộ Generated rồi tự động chuyển sang Review trong cùng thao tác — trạng thái user quan sát được ngay sau khi Generate Content luôn là Review, không phải Generated (xem Requirement "Lifecycle Content Generated → Review → Approved"). Việc Product đã có Content khác ở bất kỳ trạng thái nào không ngăn thao tác này.

#### Scenario: User chọn Product thuộc tài khoản khác
- **WHEN** `current_user` yêu cầu Generate Content cho Product có `user_id` khác
- **THEN** hệ thống từ chối trước khi gọi AI provider, không tạo Content và không tiết lộ Product facts

#### Scenario: Provider từ chối connection
- **WHEN** AI provider báo credential không còn hợp lệ hoặc connection đã disconnected
- **THEN** hệ thống không tạo `Content`, báo user cần kết nối lại provider và không hiển thị chi tiết kỹ thuật hoặc credential

#### Scenario: Provider gặp lỗi tạm thời
- **WHEN** AI provider không phản hồi do timeout hoặc lỗi kết nối tạm thời
- **THEN** hệ thống không tạo `Content`, báo user thử lại sau và không hiển thị chi tiết kỹ thuật hoặc credential

#### Scenario: Generate lại thất bại
- **WHEN** AI provider gặp lỗi trong lúc Regenerate Content đã tồn tại
- **THEN** hệ thống giữ nguyên body, trạng thái và affiliate URL hiện tại, đồng thời hướng dẫn user kết nối lại hoặc thử lại sau tùy loại lỗi

### Requirement: Lifecycle Content Generated → Review → Approved
Hệ thống SHALL quản lý `Content` qua các trạng thái Generated → Review → Approved/Rejected, với hành động Preview/Edit/Regenerate/Approve/Reject khả dụng tương ứng theo trạng thái. Hệ thống SHALL tự động chuyển Content từ Generated sang Review ngay sau khi generate thành công — không có hành động user riêng để "bắt đầu review". **`Generated` là trạng thái transient bên trong `generate_operation`, không phải trạng thái user có thể quan sát hay thao tác lên** — không có UI/action nào hiển thị hay nhận request khi Content đang `generated` (kể cả đọc qua API), vì operation luôn transition sang `review` trước khi trả kết quả; nếu `start_review!` thất bại thì `generate_operation` phải fail toàn bộ (rollback, không để lại Content kẹt ở `generated`), không trả thành công một nửa. Approve/Reject/Edit SHALL chỉ hợp lệ khi Content đang ở Review. Regenerate SHALL hợp lệ ở Review **và** ở Rejected (ngoại lệ duy nhất — đây là lối duy nhất để tạo nội dung mới sau khi Reject, chuyển Content từ Rejected trở lại Review với `body` mới).

#### Scenario: Content tự động chuyển Generated → Review
- **WHEN** `generate_operation` vừa tạo Content thành công ở trạng thái Generated
- **THEN** hệ thống tự động chuyển Content sang Review ngay trong cùng Operation đó, trước khi trả kết quả về cho user — user nhìn thấy Content ở màn Content Review, không bao giờ thấy trạng thái Generated "đứng yên" chờ thao tác riêng

#### Scenario: Approve/Reject/Edit khi Content chưa ở Review
- **WHEN** có lời gọi Approve, Reject, hoặc Edit trên một Content không ở trạng thái Review (ví dụ đã Approved hoặc Rejected)
- **THEN** hệ thống từ chối thao tác, không đổi trạng thái/nội dung Content

#### Scenario: Regenerate từ Rejected quay lại Review
- **WHEN** user bấm Regenerate trên một Content đang Rejected
- **THEN** hệ thống gọi lại Codex, ghi đè `body` mới, chuyển Content từ Rejected sang Review (không tạo row Content mới)

#### Scenario: Regenerate khi Content ở Generated hoặc Approved
- **WHEN** có lời gọi Regenerate trên một Content đang Generated hoặc Approved
- **THEN** hệ thống từ chối thao tác, không đổi trạng thái/nội dung Content và báo rõ Content này không thể regenerate sau khi Approved; user vẫn có thể tạo một Content mới từ cùng Product

#### Scenario: User approve Content
- **WHEN** Content đang ở trạng thái Review và user bấm Approve
- **THEN** hệ thống chuyển Content sang Approved, cho phép tạo Publication từ Content này

#### Scenario: User reject Content
- **WHEN** Content đang ở trạng thái Review và user bấm Reject
- **THEN** hệ thống giữ Content ở trạng thái không Approved, không cho tạo Publication từ Content này

### Requirement: Edit Content chỉ sửa nội dung, không sửa Product/affiliate_url
Hệ thống SHALL cho phép user Edit trực tiếp nội dung (`body`) của Content khi đang ở Review, SHALL không cho phép Edit thay đổi `product_id` hay `affiliate_url`. Edit SHALL chỉ hợp lệ khi Content đang ở Review (cùng rule với Approve/Reject/Regenerate).

#### Scenario: User Edit nội dung ở Review
- **WHEN** user sửa trực tiếp `body` của 1 Content đang Review và lưu
- **THEN** hệ thống cập nhật `body`, giữ nguyên `product_id` và `affiliate_url`, Content vẫn ở Review (chưa Approve)

#### Scenario: Edit cố thay đổi affiliate_url
- **WHEN** request Edit gửi kèm giá trị `affiliate_url` khác giá trị hiện tại của Content
- **THEN** hệ thống bỏ qua giá trị đó, không cho phép ghi đè `affiliate_url`

### Requirement: Regenerate không đổi Product facts hoặc affiliate URL
Hệ thống SHALL cho phép Regenerate Content (tạo lại hook/caption/CTA/hashtags) nhưng SHALL giữ nguyên Product ID gốc, facts gốc, và `affiliate_url` gốc.

#### Scenario: User bấm Regenerate
- **WHEN** user bấm Regenerate trên một Content đang Review
- **THEN** hệ thống gọi lại Codex với cùng Product facts, tạo nội dung copy mới, nhưng `affiliate_url` và tham chiếu Product không đổi

### Requirement: Một Product có thể có nhiều Content độc lập
Hệ thống SHALL cho phép một Product có nhiều Content; mỗi Content là một bản nội dung riêng, có ID, body, trạng thái review, generation count và Publication liên kết độc lập. `Product` SHALL có quan hệ một-nhiều với `Content`; database SHALL không áp unique constraint trên `contents.product_id`. Regenerate cập nhật cùng row Content; Generate luôn tạo row Content mới kể cả Product đã có Content Approved. Approved là trạng thái terminal của chính Content đó: không thể Edit, Reject hoặc Regenerate bản đã Approved, nhưng không khóa Product hay các Content khác. POC không cần model Campaign; nếu cần nhóm Content thành chiến dịch thì đó là mở rộng riêng.

#### Scenario: Generate thêm Content cho Product đã có Content
- **WHEN** user yêu cầu Generate cho Product đang có một hoặc nhiều Content, kể cả Content Approved
- **THEN** hệ thống tạo Content row mới, giữ nguyên các Content hiện có và gắn Product/affiliate URL facts như các Content khác của Product

#### Scenario: Regenerate chỉ thay phiên bản đang thao tác
- **WHEN** user regenerate một Content đang Review hoặc Rejected trong khi Product còn Content khác
- **THEN** hệ thống cập nhật body và lifecycle của đúng Content đó, không thay đổi các Content khác hoặc Publication đã tham chiếu chúng

#### Scenario: Approved terminal theo từng Content
- **WHEN** user thử sửa hoặc regenerate một Content đã Approved, hoặc tạo Content mới từ Product đã có Content Approved
- **THEN** hệ thống từ chối sửa/regenerate row Approved đó nhưng vẫn cho phép tạo Content row mới từ Product; trạng thái các Content và Publication khác không đổi

#### Scenario: Claim trong bản nháp cần người duyệt
- **WHEN** Content được tạo hoặc regenerate thành công
- **THEN** hệ thống giữ nguyên Product record và affiliate URL gốc, đưa nội dung vào Review và không đánh dấu các claim trong body là đã được hệ thống xác minh; user phải review và approve tường minh trước khi có thể publish
