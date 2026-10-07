# Spec Delta

## Purpose

Cho phép người dùng tạo nội dung video qua pipeline AI đã chọn, duyệt từng bước và biết chi phí cùng trạng thái provider trước khi gửi tác vụ có thể tính phí.

## ADDED Requirements

### Requirement: Khai báo đầu vào mục tiêu video
AffiHub MUST cho người dùng khai báo chủ đề (`topic`), ngôn ngữ (`language`), giọng điệu (`tone`) và thời lượng mục tiêu (`target_duration`) trước khi tạo script.

#### Scenario: Tạo script từ input đã khai báo
- **WHEN** người dùng gửi đủ chủ đề, ngôn ngữ, giọng điệu và thời lượng mục tiêu
- **THEN** AffiHub dùng các giá trị này làm input tạo script, lưu cùng project/job và cho phép người dùng chỉnh sửa trước bước scene prompts

#### Scenario: Thiếu input bắt buộc
- **WHEN** người dùng chưa cung cấp một trong các input bắt buộc
- **THEN** AffiHub không gọi LLM và yêu cầu bổ sung giá trị còn thiếu

### Requirement: Duyệt script và scene prompts theo từng bước
AffiHub MUST yêu cầu thao tác rõ ràng của người dùng trước mỗi bước tạo script, scene prompts hoặc video có thể gọi provider.

#### Scenario: Duyệt script
- **WHEN** người dùng yêu cầu tạo script sau khi xem provider, model và estimate khả dụng
- **THEN** AffiHub gửi yêu cầu tạo script và cho phép người dùng sửa script trước khi tạo scene prompts

#### Scenario: Duyệt scene prompts
- **WHEN** người dùng duyệt script rồi yêu cầu scene prompts
- **THEN** AffiHub tạo prompts có thể sửa và không gửi yêu cầu tạo clip cho tới khi người dùng xác nhận riêng chi phí

### Requirement: Hiển thị breakdown và giới hạn chi phí trước job trả phí
AffiHub MUST tính estimate trên đúng input thực tế, tổng hợp theo scene và phân loại MuAPI, LLM, stock asset, TTS/fallback cùng các khoản chưa biết; hiển thị currency, provider/model, nguồn giá và thời điểm estimate. Với model MuAPI có dynamic pricing, AffiHub MUST gọi `estimate-cost` bằng prompt, duration và resolution sẽ gửi.

#### Scenario: Estimate nằm trong trần
- **WHEN** toàn bộ khoản phí bắt buộc đã có estimate và tổng không vượt trần do người dùng đặt
- **THEN** AffiHub hiển thị tổng cùng breakdown theo cảnh và cho người dùng xác nhận job

#### Scenario: Estimate vượt trần hoặc thiếu khoản phí bắt buộc
- **WHEN** tổng estimate vượt trần hoặc còn khoản phí bắt buộc chưa xác định
- **THEN** AffiHub chặn gửi job cho đến khi người dùng cập nhật trần/giá và xác nhận lại

#### Scenario: Báo giá MuAPI theo từng scene
- **WHEN** estimate có model MuAPI dynamic pricing
- **THEN** AffiHub dùng đúng prompt, duration và resolution của từng scene để lấy giá rồi tổng hợp trước khi yêu cầu xác nhận

#### Scenario: Không lấy được báo giá bắt buộc
- **WHEN** `estimate-cost` hoặc nguồn giá bắt buộc không trả estimate đáng tin cậy
- **THEN** AffiHub đánh dấu khoản đó chưa biết và chặn job trả phí cho tới khi có giá hoặc người dùng chọn phương án không phát sinh khoản phí đó

### Requirement: Chỉ tạo clip AI sau xác nhận chi phí
AffiHub MUST gửi yêu cầu tạo clip có phí chỉ sau xác nhận tường minh của người dùng cho estimate đang hiển thị.

#### Scenario: Người dùng xác nhận
- **WHEN** người dùng xác nhận estimate của model, prompts, thời lượng và độ phân giải hiện tại
- **THEN** AffiHub gửi một job cho các cảnh đã xác nhận và lưu thông tin nhận diện job

#### Scenario: Estimate thay đổi trước khi gửi
- **WHEN** input hoặc estimate thay đổi sau bước xem giá
- **THEN** AffiHub yêu cầu xem lại và xác nhận estimate mới trước khi gọi provider

### Requirement: Phân biệt AI tạo cảnh với stock montage
AffiHub MUST ghi rõ người dùng đang chọn text-to-video hay montage dùng stock footage.

#### Scenario: Chọn stock montage
- **WHEN** người dùng chọn AI script kết hợp stock footage
- **THEN** AffiHub mô tả kết quả là montage footage và không gọi đó là clip text-to-video

### Requirement: Đối soát job AI chưa rõ kết quả
AffiHub MUST giữ job ở trạng thái chưa rõ khi timeout có thể xảy ra sau khi provider nhận yêu cầu và MUST đối soát trước khi cho gửi lại.

#### Scenario: Timeout có thể đã tạo job
- **WHEN** request đã có thể tới provider nhưng AffiHub chưa lưu được kết quả cuối
- **THEN** job chuyển sang `OutcomeUnknown`, tìm task/provider ID hoặc dữ liệu đối soát và chặn gửi lại cho tới khi kết quả được giải quyết

#### Scenario: Provider xác nhận chưa nhận job
- **WHEN** đối soát xác nhận provider chưa tạo job
- **THEN** AffiHub cho phép người dùng xác nhận retry và ghi lại quyết định cùng kết quả đối soát

#### Scenario: Người dùng xác nhận một trong ba kết quả
- **WHEN** provider không có lookup đủ tin cậy để quyết định kết quả
- **THEN** AffiHub cho người dùng ghi “đã xảy ra” kèm URL/reference và bằng chứng, “chắc chắn chưa xảy ra” kèm xác nhận rủi ro trước retry, hoặc “vẫn chưa rõ” để tiếp tục chặn retry; mọi lựa chọn được lưu audit và không giả tạo output provider

### Requirement: Giữ trạng thái và chi phí thực tế của AI job
AffiHub MUST lưu task ID, trạng thái, model, estimate đã xác nhận và chi phí thực tế mà provider trả về để đối soát sau restart.

#### Scenario: AffiHub khởi động lại khi job đang chạy
- **WHEN** app hoặc worker khởi động lại trước khi job AI hoàn tất
- **THEN** trạng thái vẫn truy xuất được và AffiHub tiếp tục polling/đối soát thay vì tự gửi job thay thế

### Requirement: Chặn job trả phí khi MPT state chưa được xác minh
AffiHub MUST xác minh MPT task/queue state có thể được tra cứu sau restart trước khi báo nhánh AI trả phí sẵn sàng; nếu state chỉ ở memory hoặc chưa được xác minh, chỉ chặn nhánh AI trả phí.

#### Scenario: MPT persistence đã được kiểm chứng
- **WHEN** bài kiểm tra recovery gần nhất xác nhận task ID/state tồn tại và reconcile được sau restart
- **THEN** preflight báo nhánh AI trả phí sẵn sàng cùng thời điểm xác minh

#### Scenario: MPT persistence chưa đạt gate
- **WHEN** state/queue chỉ tồn tại trong memory hoặc recovery chưa được xác minh
- **THEN** preflight chặn job AI trả phí và giữ import, edit, render cùng local export hoạt động

### Requirement: Hiển thị TTS fallback
AffiHub MUST dùng VieNeu-TTS v3 Turbo qua adapter WAV mặc định. Azure Speech chỉ được dùng làm fallback tự động khi provider đã cấu hình, có estimate giá hiện hành và người dùng đã xác nhận chi phí. AffiHub MUST báo rõ provider và chi phí trước khi người dùng duyệt audio fallback. Nếu thiếu estimate hoặc consent, không tự gọi Azure hoặc Edge; chỉ chặn phần TTS/job AI phụ thuộc và giữ các chức năng local hoạt động. Edge TTS chỉ được dùng khi người dùng chọn rõ như phương án best-effort.

#### Scenario: VieNeu-TTS không khả dụng và Azure đã được xác nhận
- **WHEN** VieNeu lỗi, Azure Speech đã cấu hình, estimate hiện hành được chấp nhận và người dùng xác nhận chi phí
- **THEN** AffiHub dùng Azure, hiển thị provider cùng chi phí trước khi người dùng duyệt audio

#### Scenario: Thiếu estimate hoặc consent cho Azure
- **WHEN** VieNeu lỗi và chưa có estimate giá hiện hành hoặc người dùng chưa xác nhận chi phí Azure
- **THEN** AffiHub không gọi Azure hay tự chuyển sang Edge, báo TTS/job AI bị chặn cùng provider/lỗi, còn edit/render/export local vẫn hoạt động

#### Scenario: Người dùng tự chọn Edge TTS
- **WHEN** người dùng chủ động chọn Edge TTS sau khi được thông báo đây là phương án best-effort
- **THEN** AffiHub hiển thị Edge là provider đang dùng trước khi người dùng duyệt audio

### Requirement: Cô lập lỗi nhánh AI
Lỗi LLM, video provider hoặc TTS MUST chỉ dừng job AI phụ thuộc dịch vụ lỗi.

#### Scenario: Provider AI dừng
- **WHEN** một dịch vụ AI không phản hồi hoặc trả lỗi
- **THEN** AffiHub báo trạng thái và hướng khắc phục cho job đó, còn source đã import vẫn có thể edit, render và export local

### Requirement: Dùng preset và scene profile MVP
AffiHub MUST dùng MPT v1.3.8 pinned source với preset mặc định `seedance-lite-t2v` 480p, 5 cảnh × 6 giây; mỗi cảnh cho phép cấu hình 3–12 giây trước estimate.

#### Scenario: Người dùng giữ preset mặc định
- **WHEN** người dùng mở AI generation lần đầu cho project
- **THEN** AffiHub hiển thị model, 480p và 5 cảnh × 6 giây trước khi gửi bất kỳ job tính phí nào

#### Scenario: Người dùng đổi scene duration
- **WHEN** người dùng chỉnh số cảnh hoặc thời lượng từng cảnh
- **THEN** AffiHub chấp nhận thời lượng trong 3–12 giây và tính lại estimate trên input mới

### Requirement: Hoàn tất pipeline thành preview MP4
Sau khi được xác nhận, pipeline AI MUST tạo clip cho các cảnh đã duyệt, ghép timeline, tạo voiceover/subtitle và lưu preview MP4 cùng task ID, model và lỗi provider.

#### Scenario: MPT hoàn tất các cảnh
- **WHEN** MPT hoàn thành job cho mọi cảnh đã xác nhận
- **THEN** AffiHub lưu clip ghép, voiceover, subtitle và preview MP4 thành source có thể mở trong editor

#### Scenario: Một cảnh hoặc bước assembly lỗi
- **WHEN** một scene job hoặc assembly thất bại
- **THEN** AffiHub ghi stage/provider/error riêng và không báo pipeline hoàn tất hoặc tự gửi lại job có thể tính phí
