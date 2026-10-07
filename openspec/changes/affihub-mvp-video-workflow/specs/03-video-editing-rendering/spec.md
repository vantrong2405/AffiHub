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

### Requirement: Dùng edit_config có schema phiên bản
Mỗi `RenderVersion.edit_config` MUST là JSON object với đúng các key `schema_version`, `segments`, `canvas`, `filters`, `overlays` và `delogo_regions`; `schema_version` MUST là số nguyên `1`, `segments` MUST có ít nhất một phần tử, các phần còn lại MUST hiện diện dù có thể rỗng. Mỗi segment có đúng `start_seconds`, `end_seconds`, `speed` (`1.0` hoặc `2.0`), `audio_mode` (`keep` hoặc `mute`) và `audio_volume` trong khoảng 0–2. Segment phải nằm trong duration của source và có `end_seconds > start_seconds`. `canvas` có đúng `mode` (`fit` hoặc `crop`) và `background`; background có đúng `type` (`blur`, `color`, `image` hoặc `video`) cùng `color` dạng `#RRGGBB` nếu là màu, `project_media_asset_id` nếu là ảnh, hoặc `source_asset_id` nếu là video. Ảnh tham chiếu `ProjectMediaAsset` cùng project; video tham chiếu `SourceAsset` `ready` cùng project. Video nền được trim nếu dài hơn output và lặp từ đầu nếu ngắn hơn. `filters` có đúng `brightness` trong khoảng -1–1 và `contrast` trong khoảng 0–2. Mỗi overlay có `type` (`text`, `subtitle` hoặc `logo`), `output_start_seconds`, `output_end_seconds`, `x`, `y`, `width`, `height` và `opacity`; tọa độ/kích thước/opacity là số normalized 0–1, nằm trọn canvas. Text/subtitle có thêm đúng key `text`; logo có thêm đúng key `project_media_asset_id`. Thời gian overlay phải nằm trong duration output. Text/subtitle được vẽ bằng filter `drawtext` trên worker FFmpeg, đọc text từ file tạm thay vì nội suy nội dung người dùng vào filtergraph; worker image MUST có font Noto Sans cấu hình tại `media.ffmpeg_font_file` để hỗ trợ tiếng Việt. Logo và ảnh nền chỉ được tham chiếu `ProjectMediaAsset` cùng project. Mỗi `delogo_regions` phần tử có đúng `x`, `y`, `width`, `height` là tọa độ pixel nguyên trên source trước crop/scale và phải nằm trọn trong kích thước source. Không nhận key lạ, trường thiếu hoặc kiểu dữ liệu sai.

`video_workflow.yml` giới hạn `limits.render_segment_max_count` (mặc định 50), `limits.render_overlay_max_count` (20), `limits.render_text_max_characters` (1000) và `limits.delogo_region_max_count` (20). Giới hạn áp dụng trước khi lưu hoặc enqueue render; text rỗng, text vượt giới hạn và mảng vượt giới hạn bị từ chối.

#### Scenario: Tạo clip 1–2 giây và đổi tốc độ đầu ra
- **WHEN** người dùng cấu hình một hay nhiều segment dài 1 hoặc 2 giây, tốc độ 1× hoặc 2× và chọn giữ/tắt audio nguồn
- **THEN** AffiHub lưu đúng thứ tự, điểm cắt, tốc độ và lựa chọn audio để worker render theo cùng timeline

#### Scenario: Tham chiếu asset thuộc project khác
- **WHEN** edit config chọn ảnh nền, logo hoặc video nền không thuộc project hiện tại hay chưa `ready`
- **THEN** AffiHub từ chối tạo `RenderVersion` và không enqueue worker

#### Scenario: Gỡ rồi hoàn tác vùng logo tĩnh
- **WHEN** người dùng tạo version có vùng `delogo`, rồi tạo version tiếp theo sau khi bỏ vùng đó khỏi edit config
- **THEN** version cũ và source không đổi; version mới giữ nguyên source pixels tại vùng đó

#### Scenario: Cấu hình nằm ngoài giới hạn
- **WHEN** segment vượt duration, speed không thuộc 1×/2×, filter/audio/overlay vượt miền giá trị hoặc vùng `delogo` vượt source frame
- **THEN** AffiHub trả lỗi validation, giữ dữ liệu form có thể sửa và không enqueue worker

### Requirement: Quản lý ảnh nền và logo theo project
AffiHub MUST lưu ảnh nền tĩnh và logo trong `ProjectMediaAsset` thuộc một `VideoProject`; chỉ chấp nhận PNG, JPEG hoặc WebP có MIME/signature tương thích và kích thước không quá giới hạn cấu hình mặc định 20 MiB. `RenderVersion` chỉ được tham chiếu asset cùng project.

#### Scenario: Tải ảnh nền hoặc logo hợp lệ
- **WHEN** người dùng thêm PNG, JPEG hoặc WebP hợp lệ có kích thước trong giới hạn
- **THEN** AffiHub lưu file trong project và cho phép chọn làm nền hoặc logo overlay

#### Scenario: Tải ảnh không an toàn hoặc quá lớn
- **WHEN** file không qua kiểm tra MIME/signature hoặc vượt giới hạn cấu hình
- **THEN** AffiHub từ chối gắn file vào project và không đưa file vào render

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
`RenderVersion` MUST lưu trạng thái `pending`, `processing`, `ready` hoặc `failed` và mặc định là `pending`. `version_number` bắt đầu từ 1 và tăng đơn điệu, không trùng lặp trong phạm vi một `SourceAsset`. Mỗi lần render MUST tạo một version mới, còn source và mọi version đã được Publication hoặc Drive export tham chiếu MUST giữ nguyên.

#### Scenario: Render lại sau chỉnh sửa
- **WHEN** người dùng thay filter hoặc thông số rồi render lại
- **THEN** AffiHub tạo version mới và giữ nguyên file, metadata cùng liên kết của version cũ

#### Scenario: FFmpeg hoặc worker lỗi
- **WHEN** render thất bại hoặc worker dừng
- **THEN** version đang render chuyển sang `failed`; AffiHub giữ project, source và các render version có sẵn, đồng thời hiển thị lỗi chẩn đoán

Render MUST chạy trong worker riêng, dùng argv tách biệt và giới hạn timeout/thread đọc từ `video_workflow.yml` (`media.ffmpeg_command`, mặc định `ffmpeg`; `media.ffmpeg_timeout_seconds`, mặc định 1800 giây; `media.ffmpeg_threads`, mặc định 2; `media.ffmpeg_font_file`, mặc định `/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf`). `RenderVersion.metadata` lưu số đo thực tế từ file MP4: `duration_seconds`, `file_size_bytes`, `video_codec`, `width`, `height`, rational-string `frame_rate`, `has_audio` và `audio_codec` nullable. `RenderVersion.render_error` lưu chẩn đoán tiếng Việt an toàn (`Không tìm thấy FFmpeg trên worker.`, `Render vượt quá giới hạn thời gian cho phép.` hoặc `Không thể render video với cấu hình hiện tại.`) và không chứa path/stderr nội bộ; trường này được xóa khi render thành công. Nếu mọi segment đều `mute`, output không có audio stream. Hết timeout hoặc worker thiếu FFmpeg phải chuyển version đang render sang `failed`, lưu chẩn đoán tương ứng và giữ file nguồn/version cũ.

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

### Requirement: Tạo RenderVersion từ source sẵn sàng trong project
AffiHub MUST gắn cấu hình và mọi `RenderVersion` mới với một `SourceAsset` `ready` thuộc cùng `VideoProject`.

#### Scenario: Chọn source để biên tập
- **WHEN** người dùng mở form tạo render trong một project
- **THEN** AffiHub chỉ cho chọn source `ready` của project đó, hiển thị preview nguồn và gắn source được chọn vào cấu hình render

#### Scenario: Source chưa sẵn sàng hoặc thuộc project khác
- **WHEN** source đang `pending`, `processing`, `failed` hoặc không thuộc project hiện tại
- **THEN** AffiHub không cho tạo render từ source đó và hiển thị trạng thái/lý do ngay trong form
