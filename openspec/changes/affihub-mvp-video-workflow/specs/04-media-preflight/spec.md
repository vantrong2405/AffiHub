# Spec Delta

## Purpose

Cho người dùng một lượt kiểm tra không phá huỷ trên source, render, connector, worker và các integration đang bật để biết chính xác đích nào sẵn sàng trước khi tiếp tục.

## ADDED Requirements

### Requirement: Chạy audit toàn project không phá huỷ
AffiHub MUST kiểm tra project, source, các render version được Publication tham chiếu, mọi đích đã chọn và integration đang bật mà không publish, sửa nội dung hoặc tạo job AI có phí.

#### Scenario: Người dùng chạy Kiểm tra toàn bộ
- **WHEN** người dùng bắt đầu audit cho project
- **THEN** AffiHub chạy một lượt kiểm tra và lưu thời điểm cùng phạm vi được kiểm tra

#### Scenario: Audit gặp dịch vụ lỗi
- **WHEN** một connector hoặc worker không phản hồi trong lúc audit
- **THEN** AffiHub ghi lỗi cho đúng mục kiểm tra và không tạo side effect publish hay render

### Requirement: Hiển thị kết quả có thể hành động
Mỗi mục audit MUST có trạng thái `Đạt`, `Cảnh báo`, `Chặn` hoặc `Chưa thể kiểm tra`, đối tượng liên quan, lý do và bước khắc phục.

#### Scenario: Có lỗi cấu hình
- **WHEN** connector thiếu quyền hoặc media không đạt yêu cầu
- **THEN** kết quả chỉ rõ Page/kênh/asset bị ảnh hưởng và hành động cần thực hiện

### Requirement: Kiểm tra source, timeline và render
Audit MUST xác minh source còn đọc được, timeline hợp lệ, asset được tham chiếu tồn tại, thông số render thực tế và điều kiện riêng của từng đích.

#### Scenario: Render không đạt định dạng đích
- **WHEN** file render có thông số không phù hợp với một đích đã chọn
- **THEN** audit chặn riêng đích đó và hiển thị thông số đo cùng lý do

#### Scenario: TikTok render có overlay AffiHub
- **WHEN** version TikTok được chọn có logo, watermark hoặc promotional overlay do AffiHub thêm
- **THEN** audit đánh dấu đích TikTok là `Chặn`

#### Scenario: Tạo dải khung hình đối chiếu
- **WHEN** audit kiểm tra một render version được Publication tham chiếu
- **THEN** AffiHub tạo dải khung source/render có timecode ở nhịp 1 giây hoặc 2 giây mà không thay đổi asset

### Requirement: Kiểm tra connector, media transfer và worker
Audit MUST kiểm tra trạng thái OAuth/đích, quyền API đọc được, worker local và khả năng cấu hình đường truyền media theo connector mà không upload hoặc publish bài.

#### Scenario: Một connector không sẵn sàng
- **WHEN** Facebook không đạt kiểm tra quyền còn TikTok đạt
- **THEN** audit báo riêng hai trạng thái và không đánh dấu TikTok thất bại theo Facebook

#### Scenario: Worker local không chạy
- **WHEN** worker cần thiết cho render, AI hoặc lịch đang dừng
- **THEN** audit nêu dịch vụ liên quan và không tuyên bố các tác vụ phụ thuộc đã sẵn sàng

#### Scenario: Lease của job đã stale
- **WHEN** job `Rendering`, `Uploading` hoặc `Generating` vượt lease/heartbeat đã lưu
- **THEN** audit nêu stage/worker cuối và hướng dẫn reconcile trước khi claim side effect mới

### Requirement: Tách readiness theo đích và integration tùy chọn
AffiHub MUST chỉ báo sẵn sàng publish cho các đích đã chọn có mọi điều kiện bắt buộc đạt; integration chưa bật phải hiện `Chưa cấu hình`.

#### Scenario: Chưa chọn đích publish
- **WHEN** người dùng audit project nhưng chưa chọn Page/kênh/tài khoản đích
- **THEN** audit chỉ xác nhận khả năng xử lý hoặc export local và ghi rõ chưa xác nhận readiness publish

#### Scenario: Google chưa bật
- **WHEN** Drive hoặc Sheets chưa được kết nối
- **THEN** audit hiển thị `Chưa cấu hình` riêng cho integration đó mà không chặn editor, local export hoặc connector social

### Requirement: Dùng estimate AI như thông tin tham khảo
Audit MUST hiển thị nguồn và thời điểm estimate AI nếu có, đồng thời MUST NOT gửi job tính phí chỉ để kiểm tra.

#### Scenario: Kiểm tra chi phí AI
- **WHEN** audit project có nhánh AI generation
- **THEN** AffiHub hiển thị estimate hiện có là ước tính không được giữ giá và không gọi endpoint tạo job

### Requirement: Kiểm tra MPT state recovery trước job trả phí
Audit MUST xác minh có bằng chứng gần nhất rằng MPT task/queue state truy xuất và reconcile được sau restart; nếu chưa xác minh hoặc chỉ lưu in-memory, chặn riêng readiness của AI trả phí.

#### Scenario: MPT recovery chưa được xác minh
- **WHEN** người dùng chạy audit và chưa có kết quả recovery bền vững cho cấu hình MPT hiện tại
- **THEN** AI trả phí ở trạng thái `Chặn` hoặc `Chưa thể kiểm tra`, nêu bước chạy kiểm tra restart/reconcile, còn source/edit/render/local export vẫn độc lập

#### Scenario: MPT state chỉ ở memory
- **WHEN** MPT không thể tra cứu task/queue sau restart
- **THEN** audit chặn job AI trả phí và không cho gửi job thay thế chỉ vì task ID không còn trong memory

#### Scenario: MPT recovery đã được xác minh
- **WHEN** kiểm tra restart/reconcile gần nhất thành công với cấu hình hiện tại
- **THEN** audit hiển thị thời điểm xác minh và AI readiness riêng, không làm thay đổi readiness của destination social

### Requirement: Kiểm tra Instagram cap hiện hành
Audit MUST hiển thị kết quả `content_publishing_limit` cho Instagram destination đã chọn nếu API đọc được.

#### Scenario: Instagram cap không đọc được
- **WHEN** API không trả current publishing limit
- **THEN** audit đánh dấu riêng Instagram là `Chưa thể kiểm tra` và không hardcode cap cũ hoặc chặn destination khác

### Requirement: Hiển thị YouTube quota do AffiHub sử dụng
Audit MUST hiển thị bộ đếm call `search.list`/`videos.insert` do AffiHub tạo, nguồn limit đang dùng và link Google Cloud Console.

#### Scenario: Dùng chung Google Cloud project
- **WHEN** quota project có thể bị ứng dụng khác sử dụng
- **THEN** AffiHub nói rõ counter chỉ gồm call của AffiHub và Console mới là nguồn tổng usage authoritative

#### Scenario: YouTube quota hết
- **WHEN** call tiếp theo thuộc bucket đã hết quota theo limit hiện hành
- **THEN** AffiHub chặn riêng operation YouTube đó, ghi lỗi quota và giữ import/edit/export cùng connector khác hoạt động

### Requirement: Gắn báo cáo preflight với render và destination đã kiểm tra
Mỗi `PreflightReport` dùng để publish MUST tham chiếu đúng một `RenderVersion` và ghi lại tập destination đã kiểm tra; report chỉ cho phép tiếp tục với đúng version và destination đó.

#### Scenario: Tiếp tục từ báo cáo còn hiệu lực
- **WHEN** người dùng mở bước tạo Publication từ một báo cáo preflight
- **THEN** AffiHub giữ nguyên `RenderVersion` và các destination trong phạm vi báo cáo

#### Scenario: Thay render hoặc destination
- **WHEN** người dùng chọn render version khác hoặc thêm destination chưa có trong báo cáo
- **THEN** AffiHub yêu cầu tạo preflight mới cho phạm vi đã đổi trước khi cho tạo Publication
