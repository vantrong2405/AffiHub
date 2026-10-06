# Spec Delta

## Purpose

Cho phép người dùng biên tập mọi source trên một timeline, xem trước kết quả và tạo file MP4 có phiên bản rõ ràng mà không làm thay đổi source hoặc bản đã dùng.

## ADDED Requirements

### Requirement: Dùng tiếng Việt trong giao diện MVP
Giao diện hướng người dùng của AffiHub MUST mặc định dùng tiếng Việt; tên dịch vụ, trạng thái hoặc thuật ngữ kỹ thuật có thể giữ nguyên khi cần để tránh làm sai nghĩa.

#### Scenario: Người dùng thao tác với luồng video
- **WHEN** người dùng mở màn hình thuộc luồng import, AI, biên tập, preflight, publish hoặc tích hợp phụ trợ
- **THEN** nhãn, hướng dẫn và lỗi dành cho người dùng được trình bày bằng tiếng Việt nhất quán

### Requirement: Biên tập mọi source trên cùng timeline
AffiHub MUST đưa source local, source đã tải và kết quả AI vào cùng trải nghiệm editor.

#### Scenario: Mở source trong editor
- **WHEN** người dùng chọn source đã kiểm tra thành công
- **THEN** AffiHub hiển thị preview nguồn và timeline để chỉnh sửa trong project đó

### Requirement: Hỗ trợ thao tác video trong MVP
Editor MUST hỗ trợ trim/chia đoạn, crop hoặc fit dọc 9:16, nền khung, brightness/contrast, audio, phụ đề, text, intro/outro và logo overlay.

#### Scenario: Chỉnh timeline và lớp hình
- **WHEN** người dùng đổi điểm cắt, nền, filter, text hoặc vị trí/kích thước/độ trong suốt logo
- **THEN** preview hiển thị thay đổi tương ứng trước khi render

#### Scenario: Chọn nền khung
- **WHEN** người dùng chọn màu, ảnh, video hoặc bản làm mờ của source làm nền
- **THEN** editor đặt nền phía sau toàn bộ khung nguồn mà không tuyên bố đã tách chủ thể khỏi phông gốc

#### Scenario: Preview khớp render
- **WHEN** người dùng render các filter, nền, tốc độ và lớp logo đang xem trước
- **THEN** file MP4 phản ánh cùng vị trí, kích thước, độ trong suốt, nền và timing như preview

### Requirement: Hỗ trợ clip ngắn và retime đầu ra
Editor MUST tạo được đoạn 1 giây và 2 giây với điểm cắt đúng, đồng thời phân biệt tốc độ preview với tốc độ clip đầu ra.

#### Scenario: Retime clip
- **WHEN** người dùng chọn tốc độ 1× hoặc 2× cho clip đầu ra
- **THEN** preview và render áp dụng cùng tốc độ, audio được time-stretch mặc định để khớp thời lượng hoặc bị tắt theo lựa chọn người dùng

### Requirement: Gỡ logo cố định có thể hoàn tác
AffiHub MUST cho phép chọn vùng chữ nhật để thử gỡ logo tĩnh, xem preview và hoàn tác về source nguyên bản.

#### Scenario: Preview vùng gỡ logo
- **WHEN** người dùng chọn vùng gỡ logo trên source
- **THEN** AffiHub hiển thị kết quả preview và giữ source không đổi để người dùng có thể bỏ thao tác

### Requirement: So sánh source với render
AffiHub MUST cung cấp khung hình đối chiếu có timecode từ source và render để người dùng kiểm tra crop, nền, chữ và logo.

#### Scenario: Xem đối chiếu
- **WHEN** người dùng chọn nhịp lấy mẫu 1 giây hoặc 2 giây
- **THEN** AffiHub hiển thị cặp khung hình cạnh nhau với timecode tương ứng

### Requirement: Tạo render version bất biến
`RenderVersion` MUST lưu trạng thái `pending`, `processing`, `ready` hoặc `failed` và mặc định là `pending`. Mỗi lần render thành công MUST tạo một version mới, còn source và mọi version đã được Publication hoặc Drive export tham chiếu MUST giữ nguyên.

#### Scenario: Render lại sau chỉnh sửa
- **WHEN** người dùng thay filter hoặc thông số rồi render lại
- **THEN** AffiHub tạo version mới và giữ nguyên file, metadata cùng liên kết của version cũ

#### Scenario: FFmpeg hoặc worker lỗi
- **WHEN** render thất bại hoặc worker dừng
- **THEN** version đang render chuyển sang `failed`; AffiHub giữ project, source và các render version có sẵn, đồng thời hiển thị lỗi chẩn đoán

### Requirement: Xuất MP4 local và phân biệt trạng thái publish
AffiHub MUST cho phép tải MP4 local mà không cần social credential và MUST phân biệt local export với publication đã đăng.

#### Scenario: Luồng local không cần credential mạng xã hội
- **WHEN** người dùng import, edit, render và export video trong AffiHub
- **THEN** AffiHub hoàn thành luồng local mà không gọi API social hay tạo platform ID/permalink giả

### Requirement: Áp dụng profile render mặc định
Render mặc định MUST tạo MP4 H.264, AAC, 1080×1920, 30 fps và MUST được kiểm tra lại theo từng đích trước publish.

#### Scenario: Render hoàn tất
- **WHEN** FFmpeg tạo file đầu ra
- **THEN** AffiHub lưu thông số đo từ file thực tế và liên kết chúng với đúng render version

### Requirement: Hạn chế overlay cho TikTok
Render dùng cho TikTok MUST không chứa logo, watermark hoặc promotional overlay do AffiHub thêm.

#### Scenario: Chọn render cho TikTok
- **WHEN** người dùng chọn TikTok làm đích của render version
- **THEN** AffiHub chặn hoặc yêu cầu tạo version phù hợp nếu version có overlay do AffiHub thêm

### Requirement: Dùng chung component library cho giao diện video
Giao diện HTML thuộc luồng video MUST dùng component daisyUI đã tích hợp cùng Tailwind CSS 4 cho các control phổ biến như nút, card, thông báo, badge và chọn tệp. Tailwind utility MUST chỉ bổ sung bố cục, khoảng cách và responsive cho các component đó. Giao diện MUST ưu tiên hành vi sẵn có của HTML/Rails/Turbo và MUST NOT viết JavaScript hoặc CSS riêng để bắt chước component daisyUI tương đương.

#### Scenario: Chọn tệp trong luồng local
- **WHEN** người dùng mở form nhập video
- **THEN** AffiHub dùng file input của daisyUI và hành vi chọn tệp gốc của trình duyệt, đồng thời nêu rõ định dạng được hỗ trợ

#### Scenario: Dùng lại control trong các màn video
- **WHEN** một màn video cần nút, card, thông báo hoặc badge
- **THEN** AffiHub dùng component daisyUI chung để kiểu dáng nhất quán giữa các màn

### Requirement: Hướng dẫn MVP bằng hành động và trạng thái rõ ràng
Giao diện MUST gọi đúng hành động người dùng, nêu định dạng được hỗ trợ và giải thích tệp được lưu hoặc publish ở đâu. Giao diện MUST NOT gắn nhãn chức năng MVP đang hoạt động là demo.

#### Scenario: Tải video lên
- **WHEN** người dùng mở màn nhập video
- **THEN** AffiHub nêu rõ MP4 được hỗ trợ, nút tải lên sẽ mở bước xem trước và video chưa được đăng lên mạng xã hội

#### Scenario: Xem trước và tải file
- **WHEN** người dùng mở video đã nhập
- **THEN** AffiHub hiển thị trạng thái sẵn sàng, thông tin file và hành động tải MP4 về máy
