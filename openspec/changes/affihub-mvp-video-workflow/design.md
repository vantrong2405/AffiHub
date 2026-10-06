# Design

## Context

Xem `proposal.md` để biết lý do/phạm vi và các spec `01`–`10` để biết behavior contract. `affihub/docs/architecture/OVERVIEW.md` ghi nhận chưa có code video để tương thích dữ liệu cũ; Rails local là UI/state owner, PostgreSQL là nguồn sự thật, Solid Queue xử lý job nền. FFmpeg, MoneyPrinterTurbo (MPT), VieNeu-TTS và các API ngoài chạy qua ranh giới worker/service riêng.

## Goals / Non-Goals

**Goals:**

- Dùng chung một model video source → edit → immutable render → destination publication, giữ mỗi connector và integration có thể lỗi độc lập.
- Đảm bảo mọi side effect bên ngoài có trạng thái lưu bền, claim/idempotency và đường đối soát trước retry.
- Giữ credential, media local và lịch đăng trong topology một máy do chủ dự án vận hành.

**Non-Goals:**

- Chọn chính xác API version, permission ID hoặc endpoint có thể đổi theo thời gian trước khi spike implementation; các giá trị đó phải được xác minh bằng tài liệu chính thức lúc triển khai.
- Tạo abstraction publisher chung trước khi có contract thực tế của cả bốn platform.
- Cung cấp SLA khi máy local tắt, hoặc chuyển ứng dụng sang hosted service.

## Decisions

### 1. Rails database là state owner; worker chỉ thực hiện bước đã claim

Lưu trạng thái từng luồng trong Rails: project/source/render, connection/destination, Publication/Schedule, AI task, auto-reply log và Drive/Sheet sync. Mỗi bước side effect có operation/attempt ID, stage và transition nguyên tử; lưu attempt ở `Submitting` trước khi request có thể rời process, dùng provider idempotency key ổn định khi API hỗ trợ. Job dài dùng lease/heartbeat và fencing token cho claim cùng transition nội bộ; sweeper phát hiện lease quá hạn và ghi audit. Fencing token nội bộ không tự ngăn provider nhận request đã rời process. Nếu attempt có thể đã được gửi, worker mới không tạo attempt khác mà reconcile cùng attempt ID hoặc giữ `OutcomeUnknown`; chỉ retry sau khi xác định chưa có side effect, sender cũ đã dừng và cửa sổ request tối đa đã hết nếu request có thể đã tới mạng ngoài. Upload nhiều bước lưu remote session/container ID, upload offset/chunk và publish ID sau mỗi checkpoint; restart tiếp tục từ checkpoint đã xác nhận hoặc reconcile trước khi gửi lại.

Khi timeout làm kết quả ngoài không rõ, lưu `OutcomeUnknown`, giữ nguyên render/destination reference và chặn retry. Tự reconcile bằng API/correlation data nếu hỗ trợ; nếu không, chỉ yêu cầu người dùng xác nhận sau khi sender cũ đã dừng và request có thể đã rời process đã qua timeout tối đa. `ManualOutcomeConfirmed` là trạng thái riêng, không giả thành `Published`. Redact token, authorization header, signed upload URL/session URI và error payload có chứa chúng khỏi log/alert. Cách này giữ một attempt duy nhất trong khi kết quả còn chưa rõ.

### 2. Tách worker theo side effect và lỗi theo integration

Solid Queue điều phối worker riêng cho import/inspection, URL download/discovery, AI, media render, schedule/publish, comment reply, Drive/Sheets và Telegram. Job video không chạy trong request web; giới hạn thời gian/tài nguyên, cancellation và thư mục làm việc theo job. Lỗi Drive chỉ retry Drive; lỗi Sheets chỉ retry SheetSync; Telegram down không dừng publisher; một publisher lỗi không chặn destination khác. Rails vẫn lưu nguồn/render/trạng thái để user tiếp tục edit hoặc export local.

MPT và VieNeu-TTS là service/runtime riêng, không cài Python dependency vào Rails. Container dùng service DNS trên private Docker network; `127.0.0.1` chỉ dùng khi process cùng network namespace. Cả hai service bind nội bộ, không publish port ra LAN/Internet và pin version/image digest; MPT bắt buộc API key cùng state/task ID tra cứu được sau restart. Preflight cần có kết quả kiểm tra persistence/recovery gần nhất cho cấu hình hiện tại; nếu service, state hoặc recovery chưa đạt gate, chặn riêng nhánh AI trả phí, không chặn source đã có.

### 3. Dùng pipeline media chung và render version bất biến

Mọi đầu vào tạo source có provenance rồi qua kiểm tra media trước khi mở editor. YouTube media chỉ qua route được YouTube chấp thuận; file do chủ dự án xuất từ Studio/Takeout có provenance riêng, còn URL chỉ giữ để attribution. Discovery dùng `search.list` cho keyword và `videos.list(chart=mostPopular)` cho chart theo region/category, hiển thị đúng nhãn và không gọi chart là keyword search/trending tổng quát; metadata có attribution và không tự đi vào downloader. URL download chỉ chấp nhận HTTPS và host/route allowlist; resolver, mọi redirect hop và IP được kiểm tra lại để chặn loopback, private, link-local, reserved và metadata endpoints. Downloader chỉ bật protocol cần thiết, có giới hạn tải và worker egress bị giới hạn; nguồn không tải được có fallback import local.

Editor giữ nguyên file source. Cấu hình chỉnh sửa được áp vào FFmpeg worker; render tạo version mới, bất biến. `Publication` và Drive export tham chiếu đúng version, nên render lại không thể đổi ngược nội dung đã dùng. MVP local import chỉ dừng ở local export; nó không tạo external connection giả, platform ID hay permalink.

### 4. Triển khai connector cụ thể trước khi rút ra interface chung

Làm Facebook Reels smoke path sớm để kiểm chứng OAuth Page, upload session, processing và trạng thái cuối. Tiếp đó spike TikTok, Instagram Reels và YouTube riêng theo tài liệu API chính thức, ghi lại quyền, payload, upload protocol, status polling, error mapping và production review. Chỉ sau khi bốn publisher cụ thể đã được thử mới đưa điểm chung ổn định vào `PublisherResolver`; không áp đặt interface dựa trên một connector duy nhất.

Mỗi Client chứa một private HTTP request method chung cho network calls của Client. Endpoint, API version, permission/config ID, timeout và giới hạn được đặt trong YAML rồi nạp qua `Rails.application.config_for`; OAuth token/API key mã hóa khi lưu, secret không hiện trong log/giao diện. OAuth state phải ngẫu nhiên, hết hạn, dùng một lần và gắn với phiên bắt đầu kết nối; dùng PKCE khi hỗ trợ, callback allowlist và scope tối thiểu. Facebook chỉ publish Page; Instagram MVP dùng Instagram API with Facebook Login qua Facebook Login for Business OAuth, liệt kê Page qua `/me/accounts`, cho người dùng chọn Page rồi lưu Page Access Token cùng `instagram_business_account` ID; resumable upload trực tiếp và đọc `content_publishing_limit` hiện hành trước publish. TikTok dùng `FILE_UPLOAD`, lưu creator/app cap và consent khi có tín hiệu chính thức, recheck consent trước gửi và báo cap chưa thể kiểm tra khi API không expose; YouTube dùng resumable `videos.insert` cùng privacy/audience/synthetic-media disclosure, upload-terms confirmation và bộ đếm quota riêng cho lệnh AffiHub gọi.

### 5. Tách audit khỏi publish và tính phí

Preflight thu kết quả theo project, source, render version, destination, worker và integration đang bật. Tạo dải frame nguồn/render có timecode theo khoảng 1–2 giây để người dùng so sánh trước khi đăng. Các API check chỉ đọc; audit lưu timestamp, trạng thái, lý do và action, không sửa source, khởi tạo upload, gửi publish hoặc tạo AI job có phí. Readiness được tính riêng cho destination đã chọn; lỗi một connector không biến destination khác thành lỗi. Báo cáo đọc cap Instagram hiện hành và quota YouTube mà AffiHub quan sát được; không tuyên bố biết mức dùng của ứng dụng khác trong cùng project Google.

AI cost estimate có source và timestamp, không coi là giá được giữ chỗ. Với dynamic MuAPI pricing, lấy `estimate-cost` theo prompt/duration/resolution của từng scene; breakdown tách MuAPI, LLM, stock, TTS/fallback và khoản chưa biết trước khi cộng tổng. Job trả phí chỉ gửi sau khi người dùng duyệt input/estimate và đặt trần đáp ứng breakdown. Khi timeout không nhận provider ID, giữ `OutcomeUnknown` và reconcile; không gửi lại chỉ vì task không còn trong memory sau restart.

### 6. Chạy đồng bộ phụ trợ theo key riêng

Khi người dùng xác nhận đăng tay hoặc lưu một lịch đã xác nhận, xếp Drive/Sheets jobs độc lập với Publication. Người dùng cũng có thể kết nối Google sau đó và chọn project/render version cụ thể để backfill; tuyệt đối không tự đồng bộ toàn thư viện. Tạo subfolder Drive theo project/video với key idempotency riêng; mỗi file export có key riêng theo render version/export. Trước khi tạo lại sau timeout phải tìm object cũ; lookup timeout hoặc không kết luận được vẫn là `OutcomeUnknown`. Sheets có một hàng hiện trạng mới nhất theo project/render version và destination, gồm `platform_post_id`, permalink và `published_at`; mỗi occurrence recurring cập nhật hàng đó sau khi có kết quả, còn Rails giữ lịch sử Publication của mọi occurrence. Serialize các lần upsert để giảm trùng vì Sheets không có unique constraint/transaction. Không bao giờ dùng kết quả Google làm điều kiện gọi lại publisher. Reservation các quota window và giới hạn nội bộ phải nguyên tử dưới cạnh tranh; Schedule lưu và hiển thị timezone (mặc định timezone máy local khi tạo), và mỗi occurrence tạo Publication riêng theo destination. Lượt bị pause hoặc lỡ giờ không được tự catch-up.

Telegram là kênh quan sát và emergency control. Bot command validate `chat_id` allowlist trước khi đọc hoặc đổi cờ pause; Scheduler và AutoResponder đọc cờ trước mỗi claim mới. Bot API lỗi chỉ làm trạng thái alert/command lỗi, không chặn job chính. Token không ghi log.

### 7. Controller gọi Service theo action; service sở hữu xử lý nghiệp vụ

Controller chỉ nhận HTTP input và tạo response; controller gọi Service có tên theo hành động trong `app/services/`. Service gọi Form/Model và sở hữu persistence, business logic cùng I/O; không đặt `demo` trong namespace hoặc tên file code. HTML UI dùng ERB/Hotwire theo convention trong `affihub/CLAUDE.md`. Trước khi implement view, task phải chạy skill `ui-ux`. Mọi feature task tách RSpec behavior spec chạy đỏ trước code, sau đó code tối thiểu, chạy xanh và refactor. Mỗi subsystem được triển khai sau Porting Note đọc source tham khảo đã pin và tài liệu API chính thức; Postiz chỉ dùng đối chiếu ranh giới kiến trúc, không làm nguồn contract hoặc runtime dependency.

### 8. Dùng daisyUI làm thư viện component cho giao diện

Giao diện Rails dùng ERB với Tailwind CSS 4 và daisyUI 5.7.47. Cài daisyUI dưới dạng npm dev dependency trong `affihub/package.json`, khóa phiên bản trong `package-lock.json`, rồi nạp plugin bằng `@plugin "daisyui"` tại `app/assets/tailwind/application.css` theo hướng dẫn chính thức của `tailwindcss-rails`. Dùng component `btn`, `card`, `file-input`, `alert`, `badge` và các component tương ứng trong view; Tailwind utility chỉ bổ sung bố cục, khoảng cách và responsive. Không tự dựng lại phần hiển thị mà daisyUI đã có, không thêm JavaScript cho hiệu ứng chỉ để thay component CSS hoặc control HTML gốc. Nghiệp vụ upload, lưu file, preview và export nằm ở Rails Service/model.

## Risks / Trade-offs

- [API review hoặc quyền public thay đổi/được duyệt chậm] → Hiển thị trạng thái connector và nghiệm thu kỹ thuật riêng với public readiness; không đặt deadline bên ngoài làm điều kiện code hoàn tất.
- [`yt-dlp` extractor hỏng hoặc source từ chối tải] → Pin và cập nhật version có chủ ý, giới hạn request, hiện lỗi và fallback file local; không retry khi bị rate-limit/block.
- [Máy local tắt khi tới lịch] → Không hứa chạy khi máy ngủ; đánh dấu lịch bị lỡ và yêu cầu user chọn lịch lại hoặc đăng tay.
- [Timeout sau external side effect] → Giữ `OutcomeUnknown`, reconcile trước retry, dùng idempotency key/claim guard và lưu `ManualOutcomeConfirmed` riêng.
- [FFmpeg/MPT/TTS tiêu tốn tài nguyên hoặc không sẵn sàng] → Health check từ đúng network namespace, giới hạn worker và báo service lỗi riêng; giữ source/render có sẵn.
- [Google Sheets không có transaction/unique key] → Serialize upsert, dò key trước append, đối soát sau timeout; Rails database giữ authoritative record.
- [Nhiều platform có contract không đồng nhất] → Giữ workflow cụ thể theo connector, kiểm thử smoke riêng trên tài khoản test rồi mới trừu tượng hóa phần thực sự chung.

## Migration Plan

Chưa có video model hoặc user data video cần migrate. Thực hiện foundation/domain và luồng video local trước; chạy Meta OAuth/Page/upload smoke spike sớm như section 2 để gỡ rủi ro API, rồi làm local source/edit/render, MPT/TTS, và hoàn thiện `MetaGraphPublisher`/review flow sau đó. Tiếp tục URL/discovery; TikTok/Instagram/YouTube; PublisherResolver/Scheduler; comment reply; Google; Telegram; cuối cùng chạy e2e từng nhánh. Spike Meta sớm là bước xác minh riêng, không phải publisher hoàn chỉnh. Schema được thêm cùng feature và RSpec; không ghi đè file source/render cũ.

Nếu cần dừng triển khai sau một phase, pause Scheduler/AutoResponder, disable connector/job mới tương ứng và giữ database, source, render cùng external outcome đã lưu. Không tự xóa bài đã publish hoặc dữ liệu Drive; rollback schema chỉ thực hiện theo migration đã review và không được làm mất record side effect ngoài hệ thống.
