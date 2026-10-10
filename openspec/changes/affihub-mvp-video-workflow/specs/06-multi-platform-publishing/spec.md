# Spec Delta

## Purpose

Cho phép người dùng publish từng render version tới nhiều Page/kênh qua quy trình riêng từng nền tảng, với trạng thái xác nhận cuối có thể đối soát và không tạo bài trùng khi retry.

## ADDED Requirements

### Requirement: Publication riêng cho từng đích
AffiHub MUST tạo Publication riêng cho mỗi tổ hợp render version và destination, có caption, lịch, trạng thái và kết quả độc lập.

#### Scenario: Chọn nhiều destination
- **WHEN** người dùng chọn nhiều Page/kênh cho một render version
- **THEN** AffiHub tạo một Publication theo từng destination và hiển thị kết quả riêng

### Requirement: Yêu cầu preflight trước publish
AffiHub MUST chặn publish khi điều kiện bắt buộc của destination chưa đạt preflight.

#### Scenario: Preflight chặn một đích
- **WHEN** một destination có lỗi quyền hoặc file không đạt yêu cầu
- **THEN** AffiHub không gửi publish tới destination đó nhưng vẫn cho xử lý các destination độc lập đã đạt

### Requirement: Duyệt tay và auto-publish theo lịch
AffiHub MUST mặc định dùng duyệt tay; auto-publish chỉ chạy khi người dùng bật và xác nhận rõ lịch cho render version cùng danh sách destination.

#### Scenario: Publish thủ công
- **WHEN** người dùng xem đúng preview render, sửa caption theo đích và xác nhận đăng
- **THEN** AffiHub tạo yêu cầu publish cho các destination đã chọn sau khi preflight đạt

#### Scenario: Đến lịch auto-publish
- **WHEN** lịch đã xác nhận đến hạn và auto-publish chưa bị pause
- **THEN** Scheduler claim Publication một lần và publish mà không yêu cầu xác nhận mới cho từng bài

### Requirement: Chỉ ghi Published sau xác nhận cuối
AffiHub MUST ghi `Published` chỉ khi API nền tảng xác nhận trạng thái cuối. AffiHub MUST lưu ID/permalink do provider trả về khi có; không được tự tạo ID hoặc URL. Nếu API xác nhận publish nhưng không cung cấp ID/permalink (TikTok `SELF_ONLY`), vẫn ghi `Published`, lưu provider publish reference và thời điểm xác nhận, để ID/permalink trống và nêu rõ chưa có liên kết công khai.

#### Scenario: API xác nhận publish hoàn tất
- **WHEN** platform workflow hoàn tất và trả kết quả cuối
- **THEN** AffiHub lưu trạng thái `Published`, các platform ID/permalink provider đã trả và thời điểm cho đúng Publication; không giả định mọi provider visibility đều có permalink

#### Scenario: Upload thành công nhưng publish chưa xác nhận
- **WHEN** upload hoặc phản hồi khởi tạo thành công nhưng trạng thái cuối chưa được xác nhận
- **THEN** Publication vẫn ở trạng thái đang xử lý hoặc cần đối soát, không hiển thị `Published`

### Requirement: Đối soát side effect chưa rõ kết quả
AffiHub MUST chuyển request publish timeout sang `OutcomeUnknown`, đối soát trước retry và không gửi lại một Publication ID khi kết quả vẫn chưa rõ.

#### Scenario: Timeout sau khi gửi publish
- **WHEN** request có thể đã tạo bài nhưng response cuối không đến
- **THEN** AffiHub truy vấn trạng thái/provider reference và chặn retry cho đến khi kết quả được giải quyết

#### Scenario: Người dùng xác nhận thủ công
- **WHEN** API không thể xác định kết quả và người dùng ghi nhận bằng chứng kiểm tra bên ngoài
- **THEN** AffiHub lưu `ManualOutcomeConfirmed` riêng, không tự chuyển trạng thái thành `Published`

### Requirement: Lưu draft riêng và xác nhận trước khi publish
AffiHub MUST lưu một Publication `draft` cho mỗi destination đạt preflight mà chưa gọi provider; chỉ sau khi người dùng duyệt đúng render/caption/destination và xác nhận rõ ràng mới bắt đầu external publish attempt.

#### Scenario: Lưu draft cho nhiều destination
- **WHEN** người dùng chọn nhiều destination đạt preflight và lưu nội dung đã duyệt
- **THEN** AffiHub lưu một Publication `draft` riêng cho từng destination, cùng render version/caption tương ứng và chưa tạo external side effect

#### Scenario: Sửa caption draft
- **WHEN** người dùng sửa caption khi Publication còn `draft`
- **THEN** AffiHub lưu caption mới và giữ nguyên render version/destination

#### Scenario: Xác nhận publish
- **WHEN** người dùng xem đúng render preview, caption và destination của một Publication `draft` rồi xác nhận đăng
- **THEN** AffiHub bắt đầu workflow publish cho đúng Publication đó và khóa sửa caption/render version/destination sau khi external attempt bắt đầu

#### Scenario: Có destination bị chặn
- **WHEN** một destination được chọn có preflight `Chặn`
- **THEN** AffiHub không tạo external publish attempt cho destination đó nhưng vẫn cho lưu/xác nhận Publication của destination độc lập đã đạt

#### Scenario: Readiness thay đổi trước khi xác nhận
- **WHEN** người dùng xác nhận một draft nhưng destination không còn đạt điều kiện publish hiện tại
- **THEN** AffiHub không bắt đầu external attempt, hiển thị điều kiện đã đổi và yêu cầu preflight lại

#### Scenario: Sửa sau khi gửi hoặc khi kết quả chưa rõ
- **WHEN** Publication đã bắt đầu external attempt hoặc ở `OutcomeUnknown`
- **THEN** AffiHub không cho sửa caption/render version/destination của Publication đó và hướng người dùng theo dõi hoặc đối soát kết quả

### Requirement: Hiển thị OutcomeUnknown như kết quả chưa được giải quyết
Giao diện Publication MUST phân biệt `OutcomeUnknown` với thành công/thất bại, không gửi lại cùng Publication khi chưa đối soát và không coi xác nhận thủ công là `Published`.

#### Scenario: Mở Publication có kết quả chưa rõ
- **WHEN** người dùng xem Publication ở `OutcomeUnknown`
- **THEN** AffiHub nêu trạng thái chưa rõ, hướng đối soát và không cung cấp thao tác gửi lại Publication đó

#### Scenario: Ghi nhận bằng chứng kiểm tra bên ngoài
- **WHEN** người dùng xác minh kết quả bên ngoài và gửi bằng chứng theo luồng cập nhật
- **THEN** AffiHub ghi `ManualOutcomeConfirmed` riêng; `Published` chỉ được đặt khi có xác nhận cuối từ provider

### Requirement: Dùng protocol media transfer riêng từng platform
AffiHub MUST upload đúng Render Version bằng workflow chính thức của từng platform, lưu checkpoint sau mỗi bước remote và polling/reconciliation tới trạng thái cuối.

#### Scenario: Facebook Reels
- **WHEN** Facebook Publication được gửi
- **THEN** AffiHub tạo upload session, tải file, chờ processing, publish đúng Page và đối soát kết quả

#### Scenario: TikTok Direct Post
- **WHEN** TikTok Publication được gửi
- **THEN** AffiHub lấy `creator_info` ngay trước đăng, yêu cầu consent với privacy/interaction/disclosure settings, upload qua `FILE_UPLOAD` theo chunk và poll kết quả theo publish ID; mỗi publish ID, upload reference và chunk checkpoint được lưu trước bước tiếp theo

#### Scenario: TikTok SELF_ONLY hoàn tất nhưng không có public post ID
- **WHEN** TikTok status fetch trả `PUBLISH_COMPLETE` nhưng không trả `publicaly_available_post_id`
- **THEN** AffiHub ghi `Published`, `publish_id` cùng thời điểm xác nhận; `platform_post_id` và permalink được giữ trống, không suy diễn URL từ `publish_id`

#### Scenario: TikTok public post có ID và share URL
- **WHEN** TikTok trả `publicaly_available_post_id` và Display API `video/query` với scope `video.list` trả `share_url`
- **THEN** AffiHub lưu đúng post ID và URL do API trả; AffiHub không tự ghép permalink

#### Scenario: TikTok không trả được permalink
- **WHEN** TikTok xác nhận `PUBLISH_COMPLETE` nhưng không cấp `video.list` hoặc lookup không trả `share_url`
- **THEN** AffiHub vẫn ghi `Published` theo xác nhận provider, để permalink trống và thông báo chưa có liên kết công khai

#### Scenario: Instagram Reels
- **WHEN** Instagram Publication được gửi
- **THEN** AffiHub tạo container `upload_type=resumable`, upload file trực tiếp qua URI `rupload.facebook.com`, poll upload rồi gọi `media_publish` và lưu container/media ID/permalink cùng checkpoint trước bước tiếp theo

#### Scenario: YouTube video
- **WHEN** YouTube Publication được gửi
- **THEN** AffiHub dùng resumable `videos.insert`, lưu resumable session/video ID/offset và giữ privacy, audience, title/description/tags cùng khai báo synthetic media đã được người dùng xác nhận

### Requirement: Xác nhận điều khoản upload YouTube
AffiHub MUST yêu cầu người dùng xác nhận điều khoản upload hiện hành trước khi gửi YouTube `videos.insert` và lưu xác nhận gắn với account, render version và Publication.

#### Scenario: Chưa xác nhận điều khoản upload
- **WHEN** Publication YouTube chưa có xác nhận điều khoản upload của người dùng
- **THEN** AffiHub chặn upload và yêu cầu người dùng xem/xác nhận điều khoản trước

#### Scenario: Điều khoản upload đã xác nhận
- **WHEN** người dùng xem điều khoản và xác nhận cho đúng channel/render version
- **THEN** AffiHub lưu thời điểm cùng định danh account/render/Publication rồi mới cho phép upload

#### Scenario: Restart giữa upload
- **WHEN** app hoặc worker restart sau một chunk hoặc bước upload đã được xác nhận
- **THEN** worker mới resume hoặc poll từ checkpoint lưu gần nhất và không khởi tạo session/container/post mới trước khi reconcile trạng thái cũ

### Requirement: Áp dụng consent và giới hạn platform
AffiHub MUST áp dụng lựa chọn privacy/disclosure của người dùng và gate review hiện hành theo từng platform trước khi publish.

#### Scenario: TikTok app chưa audit
- **WHEN** TikTok app chưa qua audit Content Posting API
- **THEN** AffiHub chỉ cho flow đáp ứng `SELF_ONLY` và điều kiện account private, đồng thời hiển thị rằng kỹ thuật test này không thay thế nghiệm thu `PUBLIC_TO_EVERYONE` trên production configuration

#### Scenario: TikTok video do AI tạo
- **WHEN** render được khai báo là AI-generated
- **THEN** AffiHub gửi `is_aigc=true` theo consent của người dùng và không thêm logo/watermark/promotional overlay của AffiHub

### Requirement: Lưu TikTok consent và creator settings
AffiHub MUST lấy `creator_info` ngay trước mỗi Direct Post, không đặt privacy mặc định và chỉ gửi các interaction/disclosure settings được creator cho phép.

#### Scenario: Không có privacy choice
- **WHEN** người dùng chưa chọn privacy level tường minh cho TikTok
- **THEN** AffiHub chặn khởi tạo Direct Post và không tự chọn privacy level thay người dùng

#### Scenario: Creator tắt interaction
- **WHEN** creator đã tắt comment, duet hoặc stitch trong `creator_info`
- **THEN** AffiHub khóa lựa chọn đó và không gửi giá trị bật trong publish request

#### Scenario: Commercial disclosure
- **WHEN** người dùng mở màn hình consent TikTok
- **THEN** Commercial Content toggle mặc định tắt, trạng thái branded content không được chọn cùng `SELF_ONLY`, và các disclosure đã xác nhận được lưu với account, render version và Schedule

#### Scenario: Schedule dùng TikTok consent đã lưu
- **WHEN** Schedule tới hạn sau khi creator settings đã thay đổi
- **THEN** AffiHub lấy `creator_info` mới và tạm dừng Publication để người dùng xác nhận lại nếu consent đã lưu không còn hợp lệ

### Requirement: Áp dụng TikTok poster và creator caps
AffiHub MUST áp dụng cap app-local đã biết trước Direct Post, gồm giới hạn app chưa audit tối đa 5 poster khác nhau trong 24 giờ. AffiHub MUST coi `spam_risk_too_many_posts` từ TikTok Query Creator Info/Direct Post là tín hiệu chính thức rằng creator đã chạm daily posting cap, và `reached_active_user_cap` là tín hiệu app client đã chạm daily active creator quota. API không trả số usage/cap còn lại hoặc thời điểm reset trong các tín hiệu này; AffiHub MUST NOT ước lượng từ mức điển hình được tài liệu nhắc tới. Khi Query Creator Info thành công mà không có lỗi cap, AffiHub MUST hiển thị `Chưa thể kiểm tra số bài còn lại`, không tuyên bố creator cap đã đạt.

#### Scenario: TikTok creator posting cap đã đạt
- **WHEN** Query Creator Info hoặc Direct Post trả `spam_risk_too_many_posts`
- **THEN** AffiHub chặn riêng Direct Post đó, ghi nhận provider báo creator cap đã đạt và không tự tạo retry; AffiHub không hiển thị usage, quota còn lại hoặc giờ thử lại nếu API không trả các giá trị đó

#### Scenario: TikTok app active creator cap đã đạt
- **WHEN** TikTok trả `reached_active_user_cap`
- **THEN** AffiHub chặn riêng Direct Post đó, ghi nhận app-client active creator quota đã đạt và không tự tạo retry

#### Scenario: TikTok creator cap chưa có counter
- **WHEN** Query Creator Info thành công nhưng không có lỗi cap
- **THEN** AffiHub hiển thị `Chưa thể kiểm tra số bài còn lại`, không ước lượng số bài hoặc reset time; trạng thái này không được diễn giải thành cap đã đạt

#### Scenario: TikTok cap app-local đã đạt
- **WHEN** app chưa audit đã dùng đủ 5 poster khác nhau trong 24 giờ
- **THEN** AffiHub chặn Direct Post mới cho poster tiếp theo và hiển thị thời điểm thử lại chỉ khi local rolling-window counter xác định được

### Requirement: Kiểm tra Instagram publishing limit hiện hành
AffiHub MUST gọi API đọc `content_publishing_limit` trước publish Reels và không hardcode cap nền tảng lịch sử.

#### Scenario: Instagram cap đã đạt
- **WHEN** API báo Page/Instagram account đã đạt publishing limit hiện hành
- **THEN** AffiHub chặn riêng Instagram Publication và hiển thị usage/cap trả về cùng cách khắc phục

### Requirement: Giữ nguyên quyền riêng tư YouTube đã được người dùng chọn
AffiHub MUST gửi đúng `privacyStatus` người dùng đã xác nhận trong request `videos.insert`, không âm thầm đổi lựa chọn. AffiHub MUST chỉ đánh dấu `Published` khi trạng thái cuối API trả về khớp lựa chọn đã xác nhận. Tài liệu `videos.insert` và `status.privacyStatus` hiện hành không áp đặt private-only cho API project chưa audit; audit là điều kiện xin quota vượt mức mặc định, không phải căn cứ để khóa `unlisted` hoặc `public` trong UI.

#### Scenario: Người dùng chọn quyền riêng tư được cấu hình
- **WHEN** người dùng xác nhận `private`, `unlisted` hoặc `public` đã được cấu hình cho YouTube
- **THEN** AffiHub gửi cùng giá trị trong `videos.insert` và chỉ ghi `Published` sau khi API xác nhận upload đã xử lý xong với privacy status khớp lựa chọn

#### Scenario: API trả privacy status khác lựa chọn đã xác nhận
- **WHEN** trạng thái cuối YouTube trả về khác `privacyStatus` đã lưu trong consent snapshot
- **THEN** AffiHub không ghi `Published`, giữ trạng thái lỗi có thể kiểm tra và không gửi lại upload tự động

### Requirement: Áp dụng giới hạn publish nội bộ
AffiHub MUST cấp lượt publish nguyên tử và giới hạn tối đa 5 Publication mới trong cửa sổ trượt 24 giờ trên mỗi destination, gộp manual và scheduled.

#### Scenario: Destination đạt giới hạn
- **WHEN** destination đã có 5 Publication mới trong cửa sổ hiện hành
- **THEN** AffiHub chặn Publication mới cho tới thời điểm mở lượt kế tiếp và hiển thị số lượt đã dùng cùng thời điểm chính xác có thể gửi Publication mới

#### Scenario: Retry cùng Publication ID
- **WHEN** cùng Publication tiếp tục upload chunk, poll, reconciliation hoặc retry được phép
- **THEN** thao tác không bị tính là Publication mới; `OutcomeUnknown` vẫn chiếm lượt và không retry khi chưa giải quyết

#### Scenario: Hai Publication tranh lượt cuối
- **WHEN** nhiều request đồng thời xin lượt thứ năm trên cùng destination
- **THEN** chỉ một reservation được cấp nguyên tử; lượt được tính khi publish request đầu tiên có thể đã gửi, còn `OutcomeUnknown` vẫn chiếm lượt

### Requirement: Lưu lịch local và xử lý missed schedule
AffiHub MUST hỗ trợ lịch một lần hoặc lặp hàng ngày/hàng tuần, không publish trước giờ người dùng chọn, lưu timezone local lúc tạo và không tự đăng muộn sau khi máy/app/worker dừng vào giờ hẹn.

#### Scenario: Tạo lịch với timezone mặc định
- **WHEN** người dùng tạo Schedule mà không đổi timezone
- **THEN** AffiHub mặc định theo timezone máy local tại thời điểm tạo, lưu timezone đó và hiển thị timezone trên từng lịch

#### Scenario: Tạo lịch với timezone được chọn
- **WHEN** người dùng chọn timezone khác timezone máy
- **THEN** AffiHub lưu lựa chọn và luôn hiển thị timezone đã chọn khi xem hoặc sửa Schedule

#### Scenario: Scheduler áp dụng jitter
- **WHEN** lịch tới giờ theo timezone đã lưu
- **THEN** Scheduler chỉ chạy trong khoảng 5–30 phút sau giờ hẹn, không đăng trước giờ đó

#### Scenario: Máy tắt lúc đến lịch
- **WHEN** app hoặc worker local không hoạt động tại thời điểm publish
- **THEN** AffiHub đánh dấu lịch bị lỡ sau khi khởi động lại và yêu cầu người dùng quyết định lên lịch lại hoặc đăng tay

#### Scenario: Lịch lặp tới kỳ kế tiếp
- **WHEN** một lịch lặp hằng ngày hoặc hằng tuần tới occurrence mới
- **THEN** AffiHub tạo Publication riêng cho mỗi destination/occurrence với idempotency key duy nhất, áp dụng preflight, jitter và quota như lịch một lần

#### Scenario: Occurrence bị pause hoặc missed
- **WHEN** occurrence tới hạn lúc Scheduler đang pause hoặc worker local ngừng
- **THEN** occurrence đó được đánh dấu skipped/missed, không tự đăng bù khi resume, còn occurrence tương lai của lịch lặp vẫn giữ nguyên
