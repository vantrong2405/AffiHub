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

### Requirement: Đặt tên VideoProject
AffiHub MUST yêu cầu tên không rỗng khi tạo `VideoProject` và hiển thị tên đó trong danh sách cùng trang chi tiết project.

#### Scenario: Tạo project có tên
- **WHEN** người dùng tạo project với tên hợp lệ
- **THEN** AffiHub lưu tên project cùng trạng thái `draft` và hiển thị tên trong danh sách/trang chi tiết

#### Scenario: Tên project bị bỏ trống
- **WHEN** người dùng gửi form tạo project không có tên
- **THEN** AffiHub không tạo project và trả lỗi validation cùng dữ liệu form để người dùng sửa

### Requirement: Import file video local
AffiHub MUST cho phép chọn file MP4 hoặc MOV từ máy và xử lý import nền mà không cần connector mạng xã hội. File được kiểm tra MIME khai báo và chữ ký container trước khi tạo source; tên file và MIME do trình duyệt gửi không được xem là bằng chứng định dạng độc lập. MIME hỗ trợ là `video/mp4` và `video/quicktime`; `application/octet-stream` chỉ được chấp nhận khi chữ ký xác nhận MP4/MOV. Giới hạn mặc định là 1 GiB và đọc từ `Rails.application.config_for(:video_workflow)` tại `limits.source_file_max_bytes`.

#### Scenario: Import file hợp lệ
- **WHEN** người dùng chọn file video hợp lệ
- **THEN** AffiHub lưu source trong project, giữ giao diện dùng được và xếp hàng kiểm tra media

#### Scenario: File khai báo MIME không tương thích với nội dung
- **WHEN** file có MIME không hỗ trợ hoặc chữ ký byte không phải container MP4/MOV
- **THEN** AffiHub từ chối trước khi tạo/đính kèm `SourceAsset` hoặc xếp job, đồng thời trả lỗi có thể sửa được

#### Scenario: File vượt giới hạn cấu hình
- **WHEN** kích thước file lớn hơn `limits.source_file_max_bytes`
- **THEN** AffiHub từ chối trước khi tạo/đính kèm `SourceAsset` hoặc xếp job và hiển thị giới hạn hiện hành

#### Scenario: File không đọc được
- **WHEN** công cụ kiểm tra không đọc được file đã chọn
- **THEN** project và source được giữ với trạng thái lỗi, nguyên nhân cùng hướng dẫn chọn file khác

### Requirement: Tải source URL bằng yt-dlp
AffiHub MUST xử lý URL nguồn trong worker nền bằng `yt-dlp` best-effort cho các nền tảng/host được cấu hình, bao gồm YouTube; công việc tải MUST NOT chặn request giao diện. Trước khi enqueue, giao diện MUST cảnh báo về quyền sử dụng và Điều khoản dịch vụ của nguồn.

#### Scenario: Tải URL từ nguồn được cấu hình
- **WHEN** người dùng gửi URL HTTPS từ một nguồn được cấu hình, bao gồm YouTube, sau khi thấy cảnh báo quyền sử dụng và Điều khoản dịch vụ
- **THEN** AffiHub enqueue `yt-dlp` trong job có timeout và chỉ retry theo giới hạn đã cấu hình

#### Scenario: Tải URL YouTube
- **WHEN** người dùng gửi URL video YouTube hợp lệ theo allowlist
- **THEN** AffiHub thử tải bằng `yt-dlp` trong worker; nếu extractor, nguồn hoặc nền tảng từ chối tải, AffiHub hiển thị nguyên nhân và hướng dẫn import file đã xuất/tải thủ công

#### Scenario: Import file owner-exported từ YouTube
- **WHEN** người dùng chọn file đã lấy qua YouTube Studio/Takeout và xác nhận provenance YouTube
- **THEN** AffiHub lưu provenance cùng file local và không gọi downloader cho file đã được import

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

### Requirement: Tìm video bằng endpoint discovery chính thức
AffiHub MUST chỉ dùng endpoint chính thức để tìm metadata video và gắn nhãn đúng loại kết quả; với YouTube dùng `search.list` cho truy vấn từ khóa và `videos.list(chart=mostPopular)` chỉ cho bảng phổ biến theo region/category. Tìm metadata và tải media là hai bước riêng: chỉ sau khi người dùng chọn kết quả, AffiHub mới enqueue `yt-dlp` với URL video đã chọn.

#### Scenario: Tìm và tải video YouTube đã chọn
- **WHEN** người dùng yêu cầu tìm video YouTube
- **THEN** keyword search dùng `search.list`; danh sách phổ biến dùng `videos.list(chart=mostPopular)` và được gắn nhãn region/category, không hiển thị như keyword result hoặc trending tổng quát; metadata có attribution; khi người dùng chọn một kết quả, AffiHub tạo `SourceAsset` kèm URL/provenance và enqueue `yt-dlp` để tải media

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
AffiHub MUST kiểm tra file media trước khi dùng, lưu metadata đã kiểm tra trong `SourceAsset.media_metadata`, hiển thị metadata và giữ provenance nguồn. `SourceAssets::InspectJob` MUST là nơi duy nhất gọi `ffprobe` cho source video; analyzer video mặc định của Active Storage MUST được tắt để không tạo lần probe thứ hai không có timeout. Worker MUST gọi `ffprobe` với argv tách biệt, không ghép path hoặc tên file vào shell command, và có timeout lấy từ cấu hình `video_workflow`. Metadata gồm `duration_seconds`, `file_size_bytes`, `video_codec`, `width`, `height`, `frame_rate` dạng rational string, `has_audio` và `audio_codec` (null khi không có audio). Chỉ source `ready` mới được đưa vào editor.

#### Scenario: Kiểm tra source thành công
- **WHEN** worker kiểm tra được source
- **THEN** worker lưu đủ metadata đã nêu, chuyển source thành `ready`, và giao diện hiển thị thời lượng, kích thước, codec, frame rate, audio track cùng provenance nguồn

#### Scenario: Source không an toàn hoặc vượt giới hạn
- **WHEN** file sai định dạng thực tế hoặc vượt giới hạn cấu hình
- **THEN** AffiHub từ chối đưa file vào bước edit, giữ lại thông tin lỗi và hướng dẫn xử lý mà không làm mất project

#### Scenario: Worker không đọc được media
- **WHEN** `ffprobe` timeout, thoát lỗi hoặc không tìm thấy video stream sau khi source đã được chấp nhận
- **THEN** AffiHub giữ project, attachment và provenance, chuyển source thành `failed`, lưu thông báo lỗi đã loại bỏ path nội bộ, và không cho tạo render version từ source đó

#### Scenario: Import file do chủ sở hữu xuất từ YouTube
- **WHEN** người dùng xác nhận file lấy từ YouTube Studio hoặc Google Takeout
- **THEN** AffiHub lưu provenance platform/method cùng file và chỉ xếp job kiểm tra media, không xếp hoặc gọi downloader
