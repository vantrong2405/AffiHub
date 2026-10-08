# Spec Delta

## Purpose

Cho phép người dùng tạo nội dung video qua pipeline AI đã chọn, duyệt từng bước và biết chi phí cùng trạng thái provider trước khi gửi tác vụ có thể tính phí.

## ADDED Requirements

### Requirement: Kết nối LLM bằng đăng nhập tài khoản được cấp quyền
AffiHub MUST hiển thị bốn lựa chọn AI: ChatGPT, Codex, Gemini, Antigravity; MUST dùng đăng nhập tài khoản thay cho ô API key LLM. ChatGPT/Codex MUST dùng chung Sign in with ChatGPT khi ứng dụng/tài khoản đủ điều kiện ChatGPT plan usage; Codex là lựa chọn model/khả năng, không phải OAuth provider riêng. Gemini MUST dùng Google OAuth chính thức cho Gemini API của project AffiHub, không dùng phiên Gemini CLI. Antigravity MUST hiển thị chưa khả dụng và không khởi tạo OAuth khi chưa có contract Google cho bên thứ ba. Credential được phép MUST mã hóa và tách khỏi credential MPT/MuAPI/stock/TTS phía máy chủ. Thiếu kết nối đủ quyền MUST chỉ chặn tạo script/scene LLM; import/edit/render/export local vẫn hoạt động.

#### Scenario: Kết nối ChatGPT được cấp quyền dùng AI
- **WHEN** ứng dụng và tài khoản đủ điều kiện, người dùng hoàn tất OAuth và chấp thuận scope dùng ChatGPT plan
- **THEN** AffiHub kiểm chứng ID token, scope được cấp, lưu connection/token mã hóa và cho người dùng chọn model thuộc tài khoản đó mà không yêu cầu OpenAI API key

#### Scenario: Chỉ đăng nhập danh tính
- **WHEN** callback có danh tính hợp lệ nhưng không có scope dùng ChatGPT plan cho inference
- **THEN** AffiHub báo thiếu quyền dùng AI và không gọi LLM hoặc đánh dấu connection sẵn sàng tạo script

#### Scenario: Callback sai phiên, hết hạn hoặc bị phát lại
- **WHEN** OAuth state/nonce/PKCE hoặc callback URI không hợp lệ, đã dùng, hết hạn hay thuộc phiên khác
- **THEN** AffiHub từ chối connection, không đổi authorization code và không lưu token

#### Scenario: Quyền hoặc hạn mức ChatGPT hết hiệu lực
- **WHEN** access token hết hạn, quyền bị thu hồi hoặc provider báo hết hạn mức
- **THEN** AffiHub refresh theo contract được cấp hoặc yêu cầu đăng nhập lại; bước LLM đang cần quyền bị chặn với lỗi rõ ràng, không tự chuyển sang API key LLM

#### Scenario: Ngắt kết nối LLM
- **WHEN** người dùng ngắt kết nối tài khoản LLM đang dùng
- **THEN** AffiHub vô hiệu credential và khóa yêu cầu LLM mới, còn project/source/render đã lưu vẫn truy cập được

### Requirement: Gemini API OAuth và gate Antigravity
AffiHub MUST chỉ bật Gemini sau khi có Google Cloud project/OAuth client dành cho AffiHub, scope/consent phù hợp, quota/billing được xác minh và request Gemini API thật thành công. AffiHub MUST NOT dùng token Gemini CLI hoặc endpoint Cloud Code Assist nội bộ. AffiHub MUST NOT khởi tạo Antigravity OAuth khi Google chưa có contract cho tích hợp bên thứ ba của AffiHub.

#### Scenario: Gemini API đã đủ quyền
- **WHEN** người dùng kết nối Google OAuth cho Gemini API và quyền/model/quota được xác minh
- **THEN** AffiHub cho chọn model Gemini thuộc quyền đã cấp, lưu token mã hóa và hiển thị nguồn quota/giá theo project, không yêu cầu API key LLM nhập tay

#### Scenario: Gemini chỉ có phiên CLI hoặc thiếu quyền API
- **WHEN** tài khoản chỉ đăng nhập Gemini CLI hoặc OAuth Gemini API thiếu scope/consent/quota phù hợp
- **THEN** AffiHub không coi kết nối sẵn sàng gọi LLM và yêu cầu hoàn tất quyền Gemini API chính thức

#### Scenario: Antigravity chưa có contract bên thứ ba
- **WHEN** người dùng xem lựa chọn Antigravity trong khi Google chưa cấp đường tích hợp phù hợp
- **THEN** AffiHub hiển thị “Chưa khả dụng”, không có hành động bắt đầu OAuth, không dùng token/endpoint từ 9Router hoặc phiên Antigravity

### Requirement: Gọi LLM bằng giao thức được quyền đăng nhập hỗ trợ
Với ChatGPT/Codex dùng ChatGPT plan usage, AffiHub MUST gọi Responses API bằng OAuth token đã được cấp quyền cho tài khoản/model được chọn, dùng `store: false` và `stream: true`, và MUST chỉ coi `response.completed` là thành công. Với Gemini, AffiHub MUST dùng Gemini API OAuth đã được xác minh cho project/quota tương ứng. AffiHub MUST NOT truyền các token này vào endpoint MPT/OpenAI-compatible chưa được xác minh hỗ trợ contract đó. Trước khi thay đường LLM của MPT, MUST xác minh các điểm MPT gọi LLM và bảo toàn các bước script/scene/video hiện có.

#### Scenario: Responses API hoàn tất script
- **WHEN** connection có quyền và model được cấp, người dùng yêu cầu tạo script
- **THEN** AffiHub dùng đúng tài khoản/model đã chọn, lưu script chỉ sau sự kiện `response.completed` và ghi provider/model cùng generation

#### Scenario: Luồng Responses bị ngắt hoặc trả lỗi
- **WHEN** provider trả `response.failed`, `response.incomplete` hoặc stream kết thúc không có `response.completed`
- **THEN** AffiHub không đánh dấu script/scene hoàn tất, hiển thị lỗi an toàn và không tự chuyển request sang MPT endpoint không tương thích

#### Scenario: Gemini API trả lỗi quyền hoặc quota
- **WHEN** Gemini API từ chối token, model hoặc quota của project
- **THEN** AffiHub không đánh dấu script/scene hoàn tất, báo rõ kết nối cần xử lý và không chuyển sang credential Gemini CLI

#### Scenario: MPT chưa có đường LLM tương thích
- **WHEN** script/scene stage của MPT vẫn cần giao thức API key không tương thích ChatGPT plan usage và adapter chưa được kiểm chứng
- **THEN** AffiHub khóa đúng bước tạo LLM, giữ video local và dữ liệu AI draft, không gửi OAuth token vào MPT hoặc báo bước AI đã sẵn sàng

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
AffiHub MUST tính estimate trên đúng input thực tế, tổng hợp theo scene và phân loại MuAPI, LLM, stock asset, TTS/fallback cùng các khoản chưa biết; hiển thị currency, provider/model, nguồn giá và thời điểm estimate. Với LLM dùng ChatGPT plan, AffiHub MUST hiển thị hạn mức gói và trạng thái quyền riêng với các khoản tiền tính theo lượt; không ghi giá 0 hoặc tự suy ra số lượt còn lại. Với Gemini API, MUST lấy nguồn giá/quota theo project thực tế và chặn job có khoản phí bắt buộc không ước tính được. Với model MuAPI có dynamic pricing, AffiHub MUST gọi `estimate-cost` bằng prompt, duration và resolution sẽ gửi.

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

#### Scenario: LLM dùng hạn mức ChatGPT plan
- **WHEN** connection có scope và model hợp lệ nhưng provider không công bố báo giá tiền cho từng request thuộc gói
- **THEN** AffiHub hiển thị “Theo hạn mức gói ChatGPT, không có báo giá tiền từng lượt”, không cộng một giá giả vào tổng tiền dịch vụ tính theo lượt và vẫn áp cost gate cho MuAPI/stock/TTS

### Requirement: Chỉ tạo clip AI sau xác nhận chi phí
AffiHub MUST gửi yêu cầu tạo clip có phí chỉ sau xác nhận tường minh của người dùng cho estimate đang hiển thị.

#### Scenario: Người dùng xác nhận
- **WHEN** người dùng xác nhận estimate của model, prompts, thời lượng và độ phân giải hiện tại
- **THEN** AffiHub gửi một job cho các cảnh đã xác nhận và lưu thông tin nhận diện job

#### Scenario: Estimate thay đổi trước khi gửi
- **WHEN** input hoặc estimate thay đổi sau bước xem giá
- **THEN** AffiHub yêu cầu xem lại và xác nhận estimate mới trước khi gọi provider

### Requirement: Lưu attempt và đối soát trước khi gửi job MPT
Trước `POST /api/v1/videos`, AffiHub MUST lưu AI generation cùng `OutboundAttempt` ở trạng thái `Submitting`. AffiHub MUST gửi một correlation ID ổn định qua header `X-Task-ID`; đây chỉ là khóa tra cứu, không phải bảo đảm idempotency từ MPT. Nếu response không có task ID hoặc timeout làm mất response, AffiHub MUST phân trang `GET /api/v1/tasks` để tìm record có `request_id` trùng correlation ID. Nếu không thể xác định kết quả, job MUST giữ `OutcomeUnknown` và không gửi lại cho tới khi provider/đối soát xác nhận request cũ chưa tạo job.

#### Scenario: Response submit bị mất nhưng MPT đã nhận job
- **WHEN** MPT tạo task nhưng AffiHub timeout trước khi lưu task ID
- **THEN** AffiHub tìm task qua `request_id`, gắn task ID tìm được vào cùng generation/attempt và không gọi `POST /api/v1/videos` lần nữa

#### Scenario: Không thể đối soát MPT task
- **WHEN** task list không truy cập được hoặc chưa tìm thấy correlation ID sau timeout
- **THEN** AffiHub giữ `OutcomeUnknown`, chặn lần submit thứ hai và cho phép tiếp tục đối soát hoặc xử lý thủ công theo bằng chứng

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
AffiHub MUST dùng VieNeu-TTS v3 Turbo qua adapter WAV mặc định. MPT MUST yêu cầu Azure fallback qua callback nội bộ được xác thực; Rails MUST đối chiếu callback với AI generation đã lưu, đúng narration text/voice, estimate Azure hiện hành và consent đã lưu trước khi gọi Azure. Rails MUST lưu outbound attempt ở `Submitting` trước request Azure, lưu WAV/provider/chi phí trước khi trả audio cho MPT, và trả lại audio đã lưu cho callback lặp có cùng generation/scene thay vì gọi Azure lần nữa. Request Azure có kết quả chưa rõ MUST chuyển attempt sang `OutcomeUnknown`, không được gửi Azure lần nữa hoặc đánh dấu task hoàn tất trước khi reconcile. AffiHub MUST báo rõ provider và chi phí trước khi người dùng duyệt audio fallback. Nếu thiếu estimate hoặc consent, callback không hợp lệ, hoặc estimate không khớp narration/voice thì không gọi Azure; chỉ chặn phần TTS/job AI phụ thuộc và giữ các chức năng local hoạt động. Edge TTS chỉ được dùng khi người dùng chọn rõ như phương án best-effort.

Rails MUST lưu narration, voice, estimate, consent, trạng thái và WAV fallback riêng cho từng scene; callback chỉ dùng correlation ID ổn định cùng scene index để tra generation/scene đã lưu, không dùng body callback làm căn cứ cấp quyền. Với MPT đã pin, TTS nhận toàn bộ `video_script` trong một lần; scene index `0` đại diện segment voiceover đó cho tới khi pipeline MPT hỗ trợ narration riêng từng clip.

#### Scenario: MPT yêu cầu fallback cho narration đã được xác nhận
- **WHEN** VieNeu lỗi và MPT gửi callback hợp lệ cho generation/scene có narration, voice, estimate Azure hiện hành và consent khớp dữ liệu Rails đã lưu
- **THEN** Rails lưu `OutboundAttempt` trước khi gọi Azure, lưu WAV cùng provider/chi phí rồi trả audio cho MPT để tiếp tục pipeline

#### Scenario: Thiếu estimate hoặc consent cho Azure
- **WHEN** VieNeu lỗi và chưa có estimate giá hiện hành hoặc người dùng chưa xác nhận chi phí Azure
- **THEN** AffiHub không gọi Azure hay tự chuyển sang Edge, báo TTS/job AI bị chặn cùng provider/lỗi, còn edit/render/export local vẫn hoạt động

#### Scenario: Callback fallback được gửi lại sau khi Azure hoàn tất
- **WHEN** MPT gửi lại callback cho generation/scene đã có WAV fallback được lưu
- **THEN** Rails trả lại WAV đã lưu và không tạo outbound attempt hoặc Azure request thứ hai

#### Scenario: Azure timeout sau khi request có thể đã được gửi
- **WHEN** Azure có thể đã xử lý request nhưng Rails không nhận được kết quả cuối
- **THEN** Rails giữ attempt ở `OutcomeUnknown`, không gọi Azure lại, và MPT không đánh dấu pipeline hoàn tất cho tới khi fallback được reconcile

#### Scenario: Callback không khớp dữ liệu đã duyệt
- **WHEN** callback sai chữ ký, generation/scene không khớp, narration/voice đổi, estimate hết hạn hoặc consent không khớp
- **THEN** Rails từ chối fallback trước khi gọi Azure và chỉ chặn nhánh TTS/job AI phụ thuộc

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

#### Scenario: Người dùng đổi số cảnh hoặc thời lượng chung
- **WHEN** người dùng chỉnh số cảnh hoặc thời lượng áp dụng chung cho các cảnh
- **THEN** AffiHub chấp nhận thời lượng trong 3–12 giây, gửi cùng giá trị video_clip_duration cho MPT và tính lại estimate riêng cho prompt từng cảnh

### Requirement: Hoàn tất pipeline thành preview MP4
Sau khi được xác nhận, pipeline AI MUST tạo clip cho các cảnh đã duyệt, ghép timeline, tạo voiceover/subtitle và lưu preview MP4 cùng task ID, model và lỗi provider.

#### Scenario: MPT hoàn tất các cảnh
- **WHEN** MPT hoàn thành job cho mọi cảnh đã xác nhận
- **THEN** AffiHub lưu clip ghép, voiceover, subtitle và preview MP4 thành source có thể mở trong editor

#### Scenario: Một cảnh hoặc bước assembly lỗi
- **WHEN** một scene job hoặc assembly thất bại
- **THEN** AffiHub ghi stage/provider/error riêng và không báo pipeline hoàn tất hoặc tự gửi lại job có thể tính phí
