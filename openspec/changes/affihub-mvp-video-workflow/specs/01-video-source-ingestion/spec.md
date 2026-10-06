# Spec Delta

## Purpose

Cho phép người dùng đưa video từ file hoặc nguồn trực tuyến vào cùng một project, xác minh khả năng xử lý và tiếp tục bằng import thủ công khi đường tải tự động không dùng được.

## ADDED Requirements

### Requirement: Trạng thái `VideoProject` và `SourceAsset`
`VideoProject` MUST lưu trạng thái `draft`, `processing`, `ready` hoặc `failed` và mặc định là `draft`. `SourceAsset` MUST lưu trạng thái `pending`, `processing`, `ready` hoặc `failed` và mặc định là `pending`.

#### Scenario: Tạo project mới
- **WHEN** người dùng tạo một `VideoProject`
- **THEN** project được lưu với trạng thái `draft`

#### Scenario: Kiểm tra source
- **WHEN** worker bắt đầu kiểm tra media của `SourceAsset`
- **THEN** source chuyển từ `pending` sang `processing`, rồi thành `ready` nếu kiểm tra thành công hoặc `failed` nếu không đọc được

### Requirement: Import file video local
AffiHub MUST cho phép chọn file MP4 hoặc MOV từ máy và xử lý import nền mà không cần connector mạng xã hội.

#### Scenario: Import file hợp lệ
- **WHEN** người dùng chọn file video hợp lệ
- **THEN** AffiHub lưu source trong project, giữ giao diện dùng được và xếp hàng kiểm tra media

#### Scenario: File không đọc được
- **WHEN** công cụ kiểm tra không đọc được file đã chọn
- **THEN** project và source được giữ với trạng thái lỗi, nguyên nhân cùng hướng dẫn chọn file khác

### Requirement: Tải source URL theo route được phép
AffiHub MUST xử lý URL nguồn trong worker nền theo HTTPS route được cấu hình cho nền tảng, không chặn request giao diện và không dùng `yt-dlp` cho YouTube.

#### Scenario: Tải URL ngoài YouTube
- **WHEN** người dùng gửi URL từ nguồn được hỗ trợ ngoài YouTube sau khi thấy cảnh báo quyền sử dụng và Điều khoản dịch vụ
- **THEN** AffiHub dùng `yt-dlp` best-effort trong job có timeout và chỉ tự retry theo giới hạn đã cấu hình

#### Scenario: Nguồn YouTube
- **WHEN** source có provenance YouTube được đưa vào AffiHub từ URL hoặc file local
- **THEN** AffiHub chỉ dùng route media được YouTube chấp thuận, không chuyển kết quả discovery sang downloader và hướng dẫn owner export/import file nếu chưa có route tự động được chấp thuận

#### Scenario: Import file owner-exported từ YouTube
- **WHEN** người dùng chọn file đã lấy qua YouTube Studio/Takeout và xác nhận provenance YouTube
- **THEN** AffiHub lưu provenance cùng file local; URL tham chiếu chỉ được dùng cho attribution, không tự tải nội dung bằng `yt-dlp`

#### Scenario: Tải URL thất bại
- **WHEN** worker gặp lỗi, timeout hoặc giới hạn từ nền tảng nguồn
- **THEN** AffiHub hiển thị nguyên nhân và hướng dẫn người dùng lấy file qua công cụ tải/xuất của chủ sở hữu rồi import thủ công, không tạo vòng retry tự động khi bị rate-limit hoặc chặn

### Requirement: Chặn URL không an toàn và SSRF
AffiHub MUST chỉ nhận scheme HTTPS và host nằm trong allowlist nguồn đã cấu hình, đồng thời chặn private, loopback, link-local, reserved và metadata-service IP ở URL ban đầu, mọi địa chỉ DNS trả về và mọi redirect. Worker MUST ghim kết nối vào địa chỉ đã kiểm tra cho từng request hoặc dùng egress proxy có cùng bảo đảm để ngăn DNS rebinding giữa lúc kiểm tra và kết nối.

#### Scenario: URL dùng scheme hoặc host ngoài allowlist
- **WHEN** người dùng gửi URL không phải HTTPS hoặc host không thuộc allowlist nguồn
- **THEN** AffiHub từ chối trước khi enqueue downloader và không tạo kết nối mạng tới URL đó

#### Scenario: URL hoặc redirect trỏ vào mạng nội bộ
- **WHEN** DNS resolution hoặc redirect dẫn tới loopback, private, link-local, reserved hay metadata-service IP
- **THEN** AffiHub chặn request, ghi lý do an toàn và không để downloader truy cập địa chỉ đó

#### Scenario: DNS trả nhiều địa chỉ hoặc thay đổi sau kiểm tra
- **WHEN** một hostname trả về ít nhất một địa chỉ bị cấm hoặc DNS thay đổi trước khi kết nối
- **THEN** AffiHub từ chối request hoặc chỉ kết nối tới địa chỉ public đã xác minh, không phân giải lại sang địa chỉ chưa kiểm tra

### Requirement: Discovery chỉ dùng endpoint chính thức
AffiHub MUST gắn nhãn kết quả đúng loại endpoint discovery chính thức; với YouTube dùng `search.list` cho truy vấn từ khóa và `videos.list(chart=mostPopular)` chỉ cho bảng phổ biến theo region/category.

#### Scenario: YouTube discovery
- **WHEN** người dùng yêu cầu tìm video YouTube
- **THEN** keyword search dùng `search.list`; danh sách phổ biến dùng `videos.list(chart=mostPopular)` và được gắn nhãn region/category, không hiển thị như keyword result hoặc trending tổng quát; metadata có attribution và chọn kết quả chỉ tạo yêu cầu lấy media qua route được chấp thuận

#### Scenario: Nền tảng không có discovery API
- **WHEN** TikTok hoặc Instagram không cung cấp endpoint discovery chính thức cho luồng này
- **THEN** AffiHub không tự crawl feed và chỉ cho người dùng nhập URL cụ thể

### Requirement: Giới hạn số lần bắt đầu tải
AffiHub MUST áp dụng tối đa 10 lần bắt đầu tải trong cửa sổ trượt 60 phút cho mỗi cài đặt local, tính chung URL, discovery và lần retry có gọi downloader.

#### Scenario: Đã chạm giới hạn
- **WHEN** yêu cầu tải mới đến trong lúc đã đủ 10 lần bắt đầu tải ở cửa sổ hiện hành
- **THEN** yêu cầu được giữ ở trạng thái chờ giới hạn và tự đủ điều kiện chạy khi cửa sổ trượt cho phép, còn import file local vẫn dùng được

#### Scenario: Hai yêu cầu tranh lượt cuối
- **WHEN** nhiều worker đồng thời claim lượt tải cuối trong cửa sổ 60 phút
- **THEN** việc cấp lượt được nguyên tử để tối đa 10 lần thực sự bắt đầu downloader được tính trong cửa sổ

### Requirement: Kiểm tra và lưu provenance của source
AffiHub MUST kiểm tra file media trước khi dùng, hiển thị metadata đọc được và giữ nguồn gốc nền tảng của từng source.

#### Scenario: Kiểm tra source thành công
- **WHEN** worker kiểm tra được source
- **THEN** giao diện hiển thị thời lượng, kích thước, codec, frame rate và audio track cùng provenance nguồn

#### Scenario: Source không an toàn hoặc vượt giới hạn
- **WHEN** file sai định dạng thực tế hoặc vượt giới hạn cấu hình
- **THEN** AffiHub từ chối đưa file vào bước edit, giữ lại thông tin lỗi và hướng dẫn xử lý mà không làm mất project
