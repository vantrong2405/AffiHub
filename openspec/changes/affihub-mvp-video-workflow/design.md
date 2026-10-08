# Design

## Context

Xem `proposal.md` để biết lý do/phạm vi và các spec `01`–`10` để biết behavior contract. `affihub/docs/architecture/OVERVIEW.md` là bản đồ code hiện tại; design baseline bắt đầu từ Rails scaffold và không có video data cũ cần migrate. Rails local là UI/state owner, PostgreSQL là nguồn sự thật, Solid Queue xử lý job nền. FFmpeg, MoneyPrinterTurbo (MPT), VieNeu-TTS và các API ngoài chạy qua ranh giới worker/service riêng.

## Goals / Non-Goals

**Goals:**

- Dùng chung một model video source → edit → immutable render → destination publication, giữ mỗi connector và integration có thể lỗi độc lập.
- Đảm bảo mọi side effect bên ngoài có trạng thái lưu bền, claim/idempotency và đường đối soát trước retry.
- Giữ credential, media local và lịch đăng trong topology một máy do chủ dự án vận hành.
- Cho người dùng kết nối LLM bằng đăng nhập tài khoản được nhà cung cấp cho phép, chọn model có quyền và dùng AI mà không nhập API key LLM trong giao diện.

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

MPT không gọi Azure trực tiếp. Khi VieNeu lỗi, MPT gửi callback có HMAC và timestamp tới endpoint riêng của Rails qua private Docker network. Rails xác thực chữ ký rồi tải AI generation/scene đã lưu; mọi input, voice, quote và consent trong body chỉ là dữ liệu để so khớp, không phải căn cứ cấp quyền. `AiGenerationScene` là bản ghi con duy nhất theo cặp generation/scene index, lưu narration, voice, estimate, consent, chi phí và attachment WAV của scene đó. MPT v1.3.8 đã pin gửi toàn bộ `video_script` vào một lần gọi TTS, vì vậy segment voiceover hiện tại dùng scene index `0`; các scene clip vẫn được lưu trong generation snapshot và không bị hiểu nhầm thành nhiều narration độc lập. Callback dùng correlation ID ổn định từ `X-Task-ID`, phải khớp chính xác narration/voice với snapshot đã được người dùng duyệt, Azure quote còn hạn, provider/voice/amount/currency/source và consent gắn với scene. Một khóa idempotency ổn định theo generation/scene xác định một fallback attempt. Rails lưu `OutboundAttempt` ở `Submitting` trước request Azure; khi thành công, lưu WAV, provider, quote chi phí và kết quả trước khi trả audio cho MPT. Callback lặp trả artifact đã lưu. Attempt đang gửi hoặc `OutcomeUnknown` không được phát sinh Azure request thứ hai; task MPT tiếp tục bị chặn cho tới khi kết quả được reconcile. Chữ ký, narration, token và payload nhạy cảm không được ghi log.

Với `POST /api/v1/videos`, Rails lưu generation và `OutboundAttempt` ở `Submitting` trước khi gọi MPT, rồi gửi correlation ID ngẫu nhiên, ổn định qua header `X-Task-ID`. Ở source đã pin, MPT lưu giá trị này thành `request_id` của task; `GET /api/v1/tasks` trả danh sách phân trang và giữ trường `request_id`, còn `GET /api/v1/tasks/{task_id}` đọc trạng thái theo task ID. Khi response submit bị mất, Rails quét danh sách để tìm đúng correlation ID và phục hồi task ID vào attempt đã có. `X-Task-ID` chỉ hỗ trợ tra cứu, không làm MPT POST trở thành idempotent. Không tìm thấy ngay hoặc lỗi task-list không chứng minh MPT chưa nhận job; giữ `OutcomeUnknown` và không POST lần nữa cho đến khi có bằng chứng reconcile đủ tin cậy.

### 3. Dùng pipeline media chung và render version bất biến

Mọi đầu vào tạo source có provenance rồi qua kiểm tra media trước khi mở editor. Import MP4/MOV local được xác thực chữ ký container cùng MIME khai báo (cho phép `application/octet-stream` khi chữ ký xác nhận định dạng) và bị giới hạn mặc định 1 GiB qua `video_workflow.yml` (`limits.source_file_max_bytes`). `SourceAssets::InspectJob` lấy file từ Active Storage, gọi `ffprobe` bằng argv tách biệt với timeout cấu hình, rồi lưu metadata media có cấu trúc vào `SourceAsset.media_metadata`; lỗi inspection giữ attachment/provenance nhưng để source ở `failed`. Job này là nguồn metadata duy nhất cho source video, nên analyzer video mặc định của Active Storage bị tắt để tránh chạy một probe thứ hai không có giới hạn thời gian. Tên file và path do client gửi không được ghép vào shell command. URL từ nguồn/host được cấu hình, kể cả YouTube, được thử tải bằng `yt-dlp` trong worker sau khi người dùng thấy cảnh báo quyền sử dụng và Điều khoản dịch vụ; file do chủ dự án xuất từ Studio/Takeout vẫn được import trực tiếp và giữ provenance riêng, không đi qua downloader. Discovery chỉ dùng API chính thức: YouTube `search.list` cho keyword và `videos.list(chart=mostPopular)` cho chart theo region/category; Instagram hashtag discovery và TikTok Research API không được bật nếu chưa xác minh account, permission, access tier và mục đích sử dụng. Metadata YouTube non-authorized được refresh hoặc xóa trước mốc 30 ngày. Khi người dùng chọn kết quả, URL mới được chuyển sang job download; hành động chọn và cảnh báo không chứng minh quyền tải. YouTube policy cấm API Client scrape YouTube Applications, còn `yt-dlp` là extractor bên thứ ba; tính phù hợp của luồng API discovery → `yt-dlp` chưa được nguồn đọc xác nhận, nên cần compliance review và không được quảng bá là API download chính thức. Không dùng downloader để tìm kiếm hoặc scrape feed. URL download chỉ chấp nhận HTTPS và host nằm trong allowlist; resolver/egress proxy kiểm tra mọi redirect, DNS answer và IP cho cả manifest/segment để chặn loopback, private, link-local, reserved và metadata endpoints. Downloader có timeout/kích thước/retry giới hạn; lỗi có fallback import local.

Mỗi lần tìm YouTube được lưu thành `SourceDiscovery` thuộc `VideoProject`; các `SourceDiscoveryResult` giữ thứ tự và liên kết tới `YoutubeDiscoveryMetadata` dùng chung theo video ID. Trang `source_discoveries#show` chỉ đọc kết quả của phiên tìm trong project hiện tại. Chọn kết quả gửi cả ID phiên tìm và ID metadata; service kiểm tra quan hệ trước khi tạo `SourceAsset`. Phiên tìm và liên kết metadata bị xóa cùng dữ liệu API-derived trước giới hạn 30 ngày. Loại tìm kiếm, region, danh mục và giới hạn độ dài query nằm trong `youtube.yml`. Khi download bị hoãn do giới hạn local, `SourceAsset.status` là `waiting_for_download_slot` và status/default tiếp tục lấy từ `video_workflow.yml`.

Editor giữ nguyên file source. Cấu hình chỉnh sửa được áp vào FFmpeg worker; render tạo version mới, bất biến, với `version_number` tăng đơn điệu và duy nhất trong mỗi source. `Publication` và Drive export tham chiếu đúng version, nên render lại không thể đổi ngược nội dung đã dùng. MVP local import chỉ dừng ở local export; nó không tạo external connection giả, platform ID hay permalink.

`RenderVersion.edit_config` dùng JSON schema phiên bản 1 với đúng các key `schema_version`, `segments`, `canvas`, `filters`, `overlays`, `delogo_regions`; mỗi section có cấu trúc, giá trị và miền tọa độ được quy định trong spec delta. Mảng segments/overlays/delogo có giới hạn cấu hình; text overlay dùng `drawtext` đọc nội dung qua file tạm và worker image có font Noto Sans. Segment theo thứ tự output hỗ trợ time range, speed 1×/2× và audio keep/mute; canvas fit/crop có nền blur/màu/ảnh/video; filters brightness/contrast; text/subtitle/logo overlay dùng output time range và tọa độ normalized; delogo dùng pixel source trước crop/scale. Segment/overlay bị ràng buộc với duration và kích thước nguồn/canvas. Video nền tham chiếu `SourceAsset` ready cùng project, được trim hoặc lặp để khớp duration output. Ảnh nền/logo tham chiếu `ProjectMediaAsset` cùng project; model này chỉ nhận PNG/JPEG/WebP, tối đa mặc định 20 MiB qua `limits.project_media_asset_max_bytes`. Bỏ vùng `delogo` tạo RenderVersion mới, không sửa source hoặc version cũ. FFmpeg worker gọi argv tách biệt, tối đa 2 thread qua `media.ffmpeg_threads` và timeout mặc định 1800 giây qua `media.ffmpeg_timeout_seconds`; lỗi/timeout đánh dấu version hiện tại thất bại, ghi diagnostic không lộ path nội bộ, và giữ file source/version cũ.

### 4. Triển khai connector cụ thể trước khi rút ra interface chung

Làm Facebook Reels smoke path sớm để kiểm chứng OAuth Page, upload session, processing và trạng thái cuối. Tiếp đó spike TikTok, Instagram Reels và YouTube riêng theo tài liệu API chính thức, ghi lại quyền, payload, upload protocol, status polling, error mapping và production review. Chỉ sau khi bốn publisher cụ thể đã được thử mới đưa điểm chung ổn định vào `PublisherResolver`; không áp đặt interface dựa trên một connector duy nhất.

Mỗi Client chứa một private HTTP request method chung cho network calls của Client. Endpoint, API version, permission/config ID, timeout và giới hạn được đặt trong YAML rồi nạp qua `Rails.application.config_for`; OAuth token/API key mã hóa khi lưu, secret không hiện trong log/giao diện. OAuth state phải ngẫu nhiên, hết hạn, dùng một lần và gắn với phiên bắt đầu kết nối; dùng PKCE khi hỗ trợ, callback allowlist và scope tối thiểu. Facebook chỉ publish Page; Instagram MVP dùng Instagram API with Facebook Login qua Facebook Login for Business OAuth, liệt kê Page qua `/me/accounts`, cho người dùng chọn Page rồi lưu Page Access Token cùng `instagram_business_account` ID; Facebook Login scopes là `pages_show_list`, `pages_read_engagement`, `instagram_basic`, `instagram_content_publish`; resumable upload trực tiếp và đọc `content_publishing_limit` hiện hành trước publish. TikTok dùng `FILE_UPLOAD`; lưu consent/app-local cap và provider cap signal khi có, coi `spam_risk_too_many_posts` là creator daily cap reached, `reached_active_user_cap` là app-client active creator cap reached, và báo `Chưa thể kiểm tra số bài còn lại` khi response không có số dư; recheck consent trước gửi. Khi TikTok trả `PUBLISH_COMPLETE`, AffiHub ghi `Published`; chỉ lấy permalink nếu response có public post ID và Display API `video/query` với scope `video.list` trả `share_url`. Với `SELF_ONLY`, thiếu ID hoặc thiếu scope/link thì giữ permalink trống, không tự ghép URL. YouTube dùng resumable `videos.insert` cùng privacy/audience/synthetic-media disclosure, upload-terms confirmation và bộ đếm quota riêng cho lệnh AffiHub gọi.

### 5. Tách audit khỏi publish và tính phí

Preflight thu kết quả theo project, source, render version, destination, worker và integration đang bật. Tạo dải frame nguồn/render có timecode theo khoảng 1–2 giây để người dùng so sánh trước khi đăng. Các API check chỉ đọc; audit lưu timestamp, trạng thái, lý do và action, không sửa source, khởi tạo upload, gửi publish hoặc tạo AI job có phí. Readiness được tính riêng cho destination đã chọn; lỗi một connector không biến destination khác thành lỗi. Báo cáo đọc cap Instagram hiện hành và quota YouTube mà AffiHub quan sát được; không tuyên bố biết mức dùng của ứng dụng khác trong cùng project Google.

AI cost estimate có source và timestamp, không coi là giá được giữ chỗ. Với dynamic MuAPI pricing, lấy `estimate-cost` theo prompt/duration/resolution của từng scene; breakdown tách MuAPI, LLM, stock, TTS/fallback và khoản chưa biết trước khi cộng tổng. Job trả phí chỉ gửi sau khi người dùng duyệt input/estimate và đặt trần đáp ứng breakdown. Khi timeout không nhận provider ID, giữ `OutcomeUnknown` và reconcile; không gửi lại chỉ vì task không còn trong memory sau restart.

Azure TTS fallback chỉ được authorize bằng estimate hiện hành và consent đã lưu cho đúng AI generation, narration text và Azure voice. Rails so khớp callback với snapshot đó, không tin giá/consent mà MPT gửi. Callback authentication, durable `OutboundAttempt`, artifact persistence và replay behavior thuộc AI recovery path; không tính `AiGenerations::TtsFallbackService` riêng lẻ là tích hợp fallback hoàn chỉnh. Nếu quote hoặc consent thiếu/hết hạn/không khớp thì không gọi Azure; Edge không được dùng tự động.

### 6. Chạy đồng bộ phụ trợ theo key riêng

Khi người dùng xác nhận đăng tay hoặc lưu một lịch đã xác nhận, xếp Drive/Sheets jobs độc lập với Publication. Người dùng cũng có thể kết nối Google sau đó và chọn project/render version cụ thể để backfill; tuyệt đối không tự đồng bộ toàn thư viện. Tạo subfolder Drive theo project/video với key idempotency riêng; mỗi file export có key riêng theo render version/export. Trước khi tạo lại sau timeout phải tìm object cũ; lookup timeout hoặc không kết luận được vẫn là `OutcomeUnknown`. Sheets có một hàng hiện trạng mới nhất theo project/render version và destination, gồm `platform_post_id`, permalink và `published_at`; mỗi occurrence recurring cập nhật hàng đó sau khi có kết quả, còn Rails giữ lịch sử Publication của mọi occurrence. Serialize các lần upsert để giảm trùng vì Sheets không có unique constraint/transaction. Không bao giờ dùng kết quả Google làm điều kiện gọi lại publisher. Reservation các quota window và giới hạn nội bộ phải nguyên tử dưới cạnh tranh; Schedule lưu và hiển thị timezone (mặc định timezone máy local khi tạo), và mỗi occurrence tạo Publication riêng theo destination. Lượt bị pause hoặc lỡ giờ không được tự catch-up.

Telegram là kênh quan sát và emergency control. Bot command validate `chat_id` allowlist trước khi đọc hoặc đổi cờ pause; Scheduler và AutoResponder đọc cờ trước mỗi claim mới. Bot API lỗi chỉ làm trạng thái alert/command lỗi, không chặn job chính. Token không ghi log.

### 7. Controller gọi Service theo action; service sở hữu xử lý nghiệp vụ

Controller chỉ nhận HTTP input, gọi Service và chuyển kết quả sang HTTP response; không query/update Model hoặc xử lý business rule. Service có tên file/class rõ resource và action trong `app/services/`, ví dụ `VideoProjects::ImportService`. `#call` chỉ điều phối các private `step_*` theo thứ tự, không trả `self`; kết quả controller/view cần đọc được expose qua `attr_reader` sau khi gọi `call`. Query, điều kiện, persistence, mapping và lỗi nằm trong các step riêng. Spec của mỗi Service mirror source path. Không đặt `demo` trong namespace hoặc tên file code. HTML UI dùng ERB/Hotwire theo convention trong `affihub/CLAUDE.md`. Trước khi implement view, task phải chạy skill `ui-ux`. Mọi feature task tách RSpec behavior spec chạy đỏ trước code, sau đó code tối thiểu, chạy xanh và refactor. Mỗi subsystem được triển khai sau Porting Note đọc source tham khảo đã pin và tài liệu API chính thức; Postiz chỉ dùng đối chiếu ranh giới kiến trúc, không làm nguồn contract hoặc runtime dependency.

### 8. Dùng daisyUI làm thư viện component cho giao diện

Giao diện Rails dùng ERB với Tailwind CSS 4 và daisyUI 5.7.47. Cài daisyUI dưới dạng npm dev dependency trong `affihub/package.json`, khóa phiên bản trong `package-lock.json`, rồi nạp plugin bằng `@plugin "daisyui"` tại `app/assets/tailwind/application.css` theo hướng dẫn chính thức của `tailwindcss-rails`. Dùng component `btn`, `card`, `file-input`, `alert`, `badge` và các component tương ứng trong view; Tailwind utility chỉ bổ sung bố cục, khoảng cách và responsive. Không tự dựng lại phần hiển thị mà daisyUI đã có, không thêm JavaScript cho hiệu ứng chỉ để thay component CSS hoặc control HTML gốc. Nghiệp vụ upload, lưu file, preview và export nằm ở Rails Service/model.

### 9. Dùng resourceful routes và view theo controller/action

AffiHub là Rails web app render HTML. `config/rails_hmvc.yml` hiện đang chọn `type: api`; trước khi generate controller/form cho màn hình sản phẩm, phải chuyển cấu hình sang `type: web`. Cấu hình HMVC API gồm năm action (`index`, `show`, `create`, `update`, `destroy`), còn cấu hình web gồm bảy action RESTful chuẩn (`index`, `show`, `new`, `create`, `edit`, `update`, `destroy`). Đây là hai action set cho hai loại ứng dụng khác nhau, không phải giới hạn chung rằng một Rails controller chỉ được có năm method. Mỗi resource chỉ khai báo các action cần dùng bằng `only:`. Xem [Rails Routing](https://guides.rubyonrails.org/v8.1/routing.html).

Controller trang HTML kế thừa `MainController`; `ApiController` chỉ dùng cho JSON endpoint. Mỗi controller phụ trách một resource và chỉ có action RESTful chuẩn. Không thêm method `import`, `render`, `publish`, `connect` hoặc `reconcile` vào controller. Thể hiện command bằng `create`/`update` của resource tương ứng; ví dụ tạo `SourceAsset`, `RenderVersion`, `PreflightReport` hoặc `Publication`. Route lồng tối đa hai resource levels để URL và route helper giữ dễ đọc. `root`, Rails health check `/up`, và OAuth callback theo URL bắt buộc của provider là các ngoại lệ giao thức/hệ thống.

```ruby
root "dashboard#index"

resources :video_projects, only: %i[index show new create edit update destroy] do
  resources :source_discoveries, only: %i[new create show]
  resources :source_assets, only: %i[index show new create]
  resources :project_media_assets, only: %i[create destroy]
  resources :ai_generation_estimates, only: %i[create show]
  resources :ai_generations, only: %i[new create show edit update]
  resources :render_versions, only: %i[index new create show]
  resources :preflight_reports, only: %i[create show]
  resources :publications, only: %i[index show new create edit update]
  resources :schedules, only: %i[index show new create edit update destroy]
  resources :drive_exports, only: %i[index show create]
  resources :sheet_syncs, only: %i[index show create]
end

resources :social_connections, only: %i[index show new create destroy] do
  resources :social_destinations, only: %i[index show create update destroy]
end

resources :ai_provider_connections, only: %i[index show create update destroy]
resources :google_connections, only: %i[index show new create edit update destroy]
resources :auto_reply_rules, only: %i[index show new create edit update destroy]
resources :auto_reply_logs, only: %i[index show]

get "/auth/:provider/callback",
    to: "connection_callbacks#show",
    as: :connection_callback

get "/ai/auth/callback",
    to: "ai_provider_callbacks#show",
    as: :ai_provider_callback
```

Tên controller/file khớp với route resource theo Rails naming: `VideoProjectsController` tại `app/controllers/video_projects_controller.rb`, `SourceAssetsController` tại `app/controllers/source_assets_controller.rb`, và tương tự cho từng resource. Action ghi dữ liệu gọi Service cùng resource/action, chẳng hạn `SourceAssets::CreateService`, `RenderVersions::CreateService`, `PreflightReports::CreateService` và `Publications::CreateService`. Read action lấy dữ liệu qua Service; controller chỉ gán kết quả cho view và trả HTTP response.

Rails tự tìm view theo controller/action; ví dụ `VideoProjectsController#index` render `app/views/video_projects/index.html.erb`. Các trang HTML MVP dùng những template sau; `_form.html.erb` là partial được dùng lại cho trang `new`/`edit`:

| Controller | Template HTML |
|---|---|
| `DashboardController` | `app/views/dashboard/index.html.erb` |
| `VideoProjectsController` | `app/views/video_projects/index.html.erb`, `app/views/video_projects/show.html.erb`, `app/views/video_projects/new.html.erb`, `app/views/video_projects/edit.html.erb`, `app/views/video_projects/_form.html.erb` |
| `SourceDiscoveriesController` | `app/views/source_discoveries/new.html.erb`, `app/views/source_discoveries/show.html.erb` |
| `SourceAssetsController` | `app/views/source_assets/index.html.erb`, `app/views/source_assets/show.html.erb`, `app/views/source_assets/new.html.erb`, `app/views/source_assets/_form.html.erb` |
| `AiGenerationEstimatesController` | `app/views/ai_generation_estimates/show.html.erb` |
| `AiGenerationsController` | `app/views/ai_generations/new.html.erb`, `app/views/ai_generations/show.html.erb`, `app/views/ai_generations/edit.html.erb`, `app/views/ai_generations/_form.html.erb` |
| `RenderVersionsController` | `app/views/render_versions/index.html.erb`, `app/views/render_versions/new.html.erb`, `app/views/render_versions/show.html.erb` |
| `PreflightReportsController` | `app/views/preflight_reports/show.html.erb` |
| `PublicationsController` | `app/views/publications/index.html.erb`, `app/views/publications/show.html.erb`, `app/views/publications/new.html.erb`, `app/views/publications/edit.html.erb`, `app/views/publications/_form.html.erb` |
| `SchedulesController` | `app/views/schedules/index.html.erb`, `app/views/schedules/show.html.erb`, `app/views/schedules/new.html.erb`, `app/views/schedules/edit.html.erb`, `app/views/schedules/_form.html.erb` |
| `SocialConnectionsController` | `app/views/social_connections/index.html.erb`, `app/views/social_connections/show.html.erb`, `app/views/social_connections/new.html.erb` |
| `SocialDestinationsController` | `app/views/social_destinations/index.html.erb`, `app/views/social_destinations/show.html.erb` |
| `AiProviderConnectionsController` | `app/views/ai_provider_connections/index.html.erb`, `app/views/ai_provider_connections/show.html.erb` |
| `GoogleConnectionsController` | `app/views/google_connections/index.html.erb`, `app/views/google_connections/show.html.erb`, `app/views/google_connections/new.html.erb`, `app/views/google_connections/edit.html.erb` |
| `AutoReplyRulesController` | `app/views/auto_reply_rules/index.html.erb`, `app/views/auto_reply_rules/show.html.erb`, `app/views/auto_reply_rules/new.html.erb`, `app/views/auto_reply_rules/edit.html.erb`, `app/views/auto_reply_rules/_form.html.erb` |
| `AutoReplyLogsController` | `app/views/auto_reply_logs/index.html.erb`, `app/views/auto_reply_logs/show.html.erb` |
| `DriveExportsController` | `app/views/drive_exports/index.html.erb`, `app/views/drive_exports/show.html.erb` |
| `SheetSyncsController` | `app/views/sheet_syncs/index.html.erb`, `app/views/sheet_syncs/show.html.erb` |

`create`, `update` và `destroy` thường redirect sau khi thành công; khi validation thất bại, `create` render `new` và `update` render `edit` với lỗi. Không tạo template cho action chỉ redirect. View chỉ trình bày dữ liệu controller/service cung cấp, không query Model hoặc giữ business logic; route helpers được dùng thay URL viết cứng. Shared layout nằm ở `app/views/layouts/application.html.erb`, partial dùng chung ở `app/views/shared/`, còn component giao diện dùng daisyUI theo quyết định 8. Xem [Rails Layouts and Rendering](https://guides.rubyonrails.org/v8.1/layouts_and_rendering.html).

### 10. Ánh xạ wireframe MVP vào resource routes

Không tạo `EditorController` hoặc action tùy chỉnh. Luồng editor là form tạo một `RenderVersion` mới: `RenderVersions#new` nhận nguồn và cấu hình, `#create` lưu cấu hình rồi enqueue render, `#show` trình bày preview và so sánh source/render. `VideoProjects#show` là điểm vào project, liệt kê nguồn/version và dẫn tới resource tương ứng.

Editor dùng bố cục ba vùng trên desktop: thanh đầu trang có breadcrumb, trạng thái source/version và hành động render; preview video dọc 9:16 chiếm vùng chính bên trái; inspector bên phải chứa các điều khiển cho đoạn cắt/tốc độ/audio, canvas/nền, filter, overlay và vùng delogo. Timeline nằm thành một dải riêng bên dưới preview và inspector, cho phép nhận biết thứ tự đoạn, khoảng thời gian và lớp overlay. Các nhóm điều khiển dùng `card`, `input`, `select`, `textarea`, `file-input`, `tabs` và `button` của daisyUI; nhãn luôn nêu rõ đơn vị timecode hoặc tọa độ. Editor chỉ mở source `ready` thuộc project hiện tại. Render là hành động rõ ràng; trạng thái job và lỗi hiển thị cạnh version, còn source và render trước đó vẫn có đường quay lại.

Trang render hoàn tất đặt video source và video render cạnh nhau trên desktop, kèm metadata, trạng thái và nút tải MP4. Bên dưới, frame comparison nhóm từng timecode với ảnh source và render cùng timestamp; người dùng có thể nhập timecode để lấy cặp frame khác. Không mô phỏng kết quả FFmpeg bằng CSS trong editor: preview trước render được ghi nhãn là source/ước lượng, còn video render và frame lấy từ file render là kết quả chuẩn để duyệt.

Trên màn hình hẹp, các vùng xếp theo thứ tự preview → trạng thái/hành động → timeline → inspector; timeline cuộn ngang bên trong vùng riêng và không làm tràn trang. Trang render xếp video source/render thành hai card dọc, giữ timecode và thao tác tải dễ tìm. Tất cả nút có tên truy cập được, input có label, trạng thái job có nội dung chữ và CTA không che nội dung khi cuộn.

| Màn hình | Resource/action | Template | Nội dung và thao tác chính |
|---|---|---|---|
| Danh sách/tạo project | `VideoProjects#index`, `new`, `create`, `edit`, `update`, `destroy` | `video_projects/index.html.erb`, `new.html.erb`, `edit.html.erb`, `_form.html.erb` | Liệt kê theo tên/trạng thái; tạo hoặc đổi tên project; chỉ xóa project chưa có source/render và giữ lỗi validation trên form. |
| Project workspace | `VideoProjects#show` | `video_projects/show.html.erb` | Hiển thị tiến độ, source/version hiện có; dẫn tới tạo `SourceAsset` hoặc `SourceDiscovery`. |
| Tạo video AI | `AiGenerations#new`, `create`, `edit`, `update` | `ai_generations/new.html.erb`, `edit.html.erb`, `_form.html.erb` | Wizard text-to-video theo thứ tự chủ đề/thông số → duyệt script → duyệt từng scene prompt → báo giá/ngân sách/consent. Lưu input và estimate trong `AiGeneration` để tiếp tục an toàn; mọi thay đổi script/prompt phải xóa estimate cũ. |
| Kết nối LLM | `AiProviderConnections#index`, `create`, `show`, `update`, `destroy`; callback giao thức `AiProviderCallbacks#show` | `ai_provider_connections/index.html.erb`, `show.html.erb` | Ba lựa chọn Codex, Gemini, Antigravity. Theo quyết định chủ dự án, không có ChatGPT/SIWC. Codex là connection auth-only theo OAuth flow Authorization Code + PKCE quan sát trong 9Router, chỉ xác minh callback/token và giữ gate inference đóng; Gemini dùng Gemini API OAuth; Antigravity ghi chưa khả dụng và không có OAuth. Xem trạng thái tài khoản/quyền và ngắt kết nối; `update` chỉ lưu model trong danh sách đã xác minh của connection; Codex không có model list; không có ô API key LLM. |
| Theo dõi video AI | `AiGenerations#show` | `ai_generations/show.html.erb` | Hiển thị trạng thái thật của MPT, output, provider/cost TTS fallback và kết quả đối soát. `OutcomeUnknown` không có retry thường; chỉ đưa các lựa chọn reconcile có bằng chứng/audit. Project workspace liệt kê generation gần nhất và trạng thái. |
| Import file hoặc URL | `SourceAssets#new`, `create`, `show` | `source_assets/new.html.erb`, `_form.html.erb`, `show.html.erb` | Hai lựa chọn trong cùng biểu mẫu; `create` enqueue kiểm tra nền; `show` hiển thị provenance, metadata và trạng thái xử lý. |
| Tìm video | `SourceDiscoveries#new`, `create`, `show` | `source_discoveries/new.html.erb`, `show.html.erb` | Dùng endpoint chính thức để tìm metadata, hiển thị nguồn/kết quả và attribution. Khi người dùng chọn kết quả, gửi URL cùng metadata discovery tới `SourceAssets#create`; worker dùng `yt-dlp` best-effort để tải media, kể cả YouTube. Nếu tải lỗi, hiển thị lý do và hướng dẫn import file. Không dùng `yt-dlp` để tìm kiếm hoặc scrape feed. |
| Editor/render | `RenderVersions#index`, `new`, `create`, `show` | `render_versions/index.html.erb`, `new.html.erb`, `show.html.erb` | `new` chọn source `ready` trong đúng project và cấu hình timeline/lớp hình; `create` tạo version bất biến; `show` phát preview và hiển thị dải khung source/render có timecode. |
| Preflight | `PreflightReports#create`, `show` | `preflight_reports/show.html.erb` | Form trên trang render gửi đúng `render_version_id` và tập destination tới `create`; `show` trình bày readiness riêng theo destination và action tiếp tục. |
| Duyệt và publish | `Publications#index`, `new`, `create`, `show`, `edit`, `update` | Các template tương ứng trong `publications/` và `_form.html.erb` | `new` nhận report/version, cho nhập caption từng destination; nút “Lưu bản nháp” tạo một Publication `draft` cho mỗi đích, chưa gọi provider. `show` là bước duyệt cuối với preview/caption/destination; “Xác nhận đăng” gửi `update` và mới bắt đầu provider workflow. `edit/update` chỉ sửa caption khi Publication còn `draft`. |

Preflight report gắn với chính xác một `RenderVersion` và tập destination đã kiểm tra. Liên kết tiếp tục sang `Publications#new` giữ `preflight_report_id` cùng `render_version_id`; destination không có trong report hoặc report thuộc version khác phải chạy preflight mới. Caption được nhập sau preflight, nên không đổi media check. `Publications#create` lưu draft sau khi xác nhận report đúng phạm vi; khi người dùng xác nhận đăng qua `#update`, service kiểm tra lại readiness hiện tại trước khi enqueue. Nếu quyền, worker hoặc điều kiện destination không còn đạt, không gửi request và hướng người dùng chạy preflight lại.

“Duyệt tay” là người dùng xem đúng preview/caption/destination rồi xác nhận từng Publication; lưu draft và sửa caption chưa tạo side effect. Xác nhận trên `Publications#show` gửi update qua `Publications#update`, rồi mới enqueue workflow provider. Khi external attempt bắt đầu, khóa caption, render version và destination của Publication đó. Chỉ phản hồi cuối của provider mới đặt `Published`. Nếu API không thể xác định kết quả, `Publications#show` hiển thị `OutcomeUnknown`, lý do và trạng thái đối soát; không đưa nút gửi lại cho cùng Publication. Khi người dùng xác minh bên ngoài và cung cấp bằng chứng qua `Publications#update`, ghi `ManualOutcomeConfirmed` riêng, không chuyển thành `Published`.

Các màn hình dùng cùng shell tiếng Việt và component daisyUI (`card`, `badge`, `alert`, `button`, `input`, `textarea`, `file-input`, `tabs`, `steps`, `skeleton`, `progress`). Loading dùng skeleton hoặc trạng thái job thực tế; empty state có hành động tiếp theo trong resource đã khai báo; lỗi giữ dữ liệu biểu mẫu và chỉ retry thao tác an toàn. Trên mobile, điều hướng thu vào `drawer`, stepper cuộn ngang, danh sách thành card, caption/destination xếp dọc và CTA chính rộng toàn màn hình. Cấu hình nền tảng/giới hạn đọc từ YAML qua `Rails.application.config_for` chỉ hiển thị dạng thông tin, không có control sửa trong các màn hình MVP.

Wizard video AI dùng bố cục một bước đang làm trong vùng chính và card báo giá/ngân sách cạnh bên trên desktop; mobile xếp card báo giá sau nội dung bước và CTA rộng toàn màn hình. DaisyUI `steps`, `card`, `input`, `textarea`, `select`, `checkbox`, `alert`, `badge`, `progress` và `btn` là component nền; chỉ dùng Tailwind utility cho layout/spacing, không định nghĩa lại component hoặc base style tương đương. Nhãn phân biệt rõ luồng AI text-to-video với stock montage. Trước thao tác tạo script, hiển thị kết nối LLM, tài khoản/model đã chọn và quyền dùng AI; nếu chưa kết nối hoặc hết hạn mức thì dẫn tới `AiProviderConnections#index`. Trước consent, hiển thị riêng MuAPI, LLM, stock và TTS fallback (VieNeu-TTS mặc định, Azure Speech khi fallback), kèm amount/currency/provider/source/thời điểm báo giá hoặc trạng thái `Chưa có báo giá`; không giả định chi phí bằng 0 khi provider chưa xác minh nguồn giá. Không ước đoán giá. Thiếu khoản dịch vụ tính theo lượt bắt buộc, quote hết hạn/không khớp narration hoặc tổng tiền vượt ngân sách thì nêu lý do và chặn submit cả trên UI lẫn Service. Script và từng scene prompt phải được người dùng duyệt; thay đổi input liên quan làm estimate không còn hợp lệ và yêu cầu báo giá lại. Màn hình `OutcomeUnknown` nêu kết quả còn chưa rõ, bằng chứng cần nhập và ba lựa chọn `occurred`, `not_occurred`, `unknown`; không trình bày `ManualOutcomeConfirmed` như generation đã hoàn tất.

### 11. Cấu hình status và migration khởi tạo sạch

Các status và giá trị mặc định của `VideoProject`, `SourceAsset`, `RenderVersion` được khai báo tại `affihub/config/video_workflow.yml`. Model nạp enum map bằng `Rails.application.config_for(:video_workflow)`; không lặp danh sách status trong code model. Chỉ thêm transition khi behavior đó được yêu cầu trong spec. Migration lưu status dưới dạng chuỗi không-null và dùng default ở model lấy từ YAML.

Schema domain của change này được tạo như một ứng dụng mới bằng Rails migration DSL. Không dùng SQL raw, nhánh `table_exists?` hoặc chuyển đổi schema POC cũ trong migration khởi tạo. Dữ liệu local POC cũ được giữ nguyên; migration tương thích chỉ được làm trong task riêng có spec và kế hoạch được duyệt.

### 12. Bản ghi reliability dùng chung cho worker dài

`WorkflowRun` là bản ghi bền vững cho một operation dài trên resource đích; lưu `operation_id`, stage, status, worker giữ lease, `lease_expires_at`, heartbeat, fencing token tăng đơn điệu và checkpoint JSONB. Status/default lấy từ `config/video_workflow.yml` qua `Rails.application.config_for(:video_workflow)`. `WorkflowRuns::ClaimService`, `HeartbeatService`, `CheckpointService` và `SweepService` điều phối từng thao tác.

Lease mặc định 60 giây được đọc từ `video_workflow.yml`; claim/heartbeat cập nhật lease dưới row lock và fencing token. Khi lease hết hạn, sweeper đưa run không có outbound attempt chưa phân giải về hàng đợi, còn run có attempt đang gửi/chưa rõ kết quả sang `reconciliation_required`.

`OutboundAttempt` thuộc một `WorkflowRun`, lưu attempt ID ổn định, stage, status, thời điểm bắt đầu gửi, thời điểm sender dừng, hạn timeout request và provider reference đã lọc an toàn. Một workflow không được tạo attempt mới khi attempt trước còn `Submitting` hoặc `OutcomeUnknown`; chỉ mở retry sau khi reconcile xác định chưa có side effect, sender cũ đã dừng và cửa sổ request tối đa đã hết. `OutboundAttempts::StartService` ghi attempt bền vững trước khi client gửi; `ResolveService` ghi quyết định/evidence và chỉ cho phép retry khi đủ điều kiện. `WorkflowAuditEvent` là lịch sử chỉ thêm, ghi claim, stage, reconcile và quyết định thủ công; không lưu token, authorization header, signed upload/session URI hay provider payload chưa redact. `Security::SensitiveDataRedactor` lọc secret khỏi structured error/log trước khi lưu hoặc phát cảnh báo.

Claim và transition dùng Active Record transaction/row lock cùng fencing token; không ghép trạng thái bằng đọc-rồi-ghi và không dùng SQL raw. Model/migration reliability được viết sau spec đỏ tương ứng.

### 13. Meta OAuth/Page và client Reels

Endpoint, Graph API version, OAuth scope, callback URL allowlist, timeout và status/default của `SocialConnection`/`SocialDestination` nằm trong `affihub/config/meta.yml` và được nạp bằng `Rails.application.config_for(:meta)`. Meta App ID đọc từ `META_APP_ID`; App Secret đọc từ Rails encrypted credentials. Meta Client gom mọi HTTP request vào một private method, không log request URI/body hoặc response thô.

OAuth `state` là giá trị ngẫu nhiên 32 byte; session lưu SHA-256 digest, provider, callback URI, hạn 10 phút và PKCE verifier nếu provider đã được xác minh hỗ trợ. Callback URL phải trùng allowlist cấu hình; state được tiêu thụ trước khi đổi code, nên callback replay/đổi session/hết hạn không thể tạo connection. Token user/Page dùng Active Record Encryption. Profile chỉ liệt kê Page qua `/me/accounts`; AffiHub chỉ lưu Page người dùng chọn và có task `CREATE_CONTENT`. Meta PKCE hiện tắt vì tài liệu được đối chiếu chưa xác nhận contract hỗ trợ; chỉ bật sau khi có nguồn chính thức.

`Meta::Client` dùng version Graph API từ YAML cho OAuth token exchange, profile, Page listing, upload-session start, binary upload, finish/publish và status lookup. Acknowledgement của start/upload/finish không đủ để đặt `Published`; service publication sau này chỉ lưu trạng thái cuối, provider ID, permalink và thời điểm sau khi poll xác nhận. Smoke test cần Page/app-role Meta thật; test WebMock không được mô tả là xác minh API live.

### 14. Đăng nhập tài khoản LLM cho AI generation

`AiProviderConnection` là kết nối LLM của user trên runtime local, tách khỏi `SocialConnection` dùng để đăng bài. Endpoint OAuth, callback URI, scope, timeout, provider gate và status/default đặt trong `affihub/config/ai_providers.yml`, đọc bằng `Rails.application.config_for(:ai_providers)`; OAuth client settings đọc từ process environment, còn `dotenv-rails` chỉ nạp `.env` local trong development/test. Token và ID token lưu mã hóa trong Rails DB local do user kiểm soát, không trả vào HTML/log. `AiProviderConnectionsController` chỉ gọi Service; `AiProviderCallbacksController#show` là ngoại lệ callback giao thức. OAuth attempt là một lần, có state digest gắn session, callback URI chính xác, expiry và PKCE verifier; state được tiêu thụ trước khi đổi authorization code, còn nonce được kiểm tra sau khi đổi code và xác minh ID token. Vì session cookie bị giới hạn theo host, trang khởi tạo OAuth phải dùng cùng origin với callback đã đăng ký; UI hiển thị liên kết sang host localhost phù hợp và Service chặn khi origin không khớp. Ngắt kết nối vô hiệu credential local và khóa bước gọi LLM tiếp theo, không xóa project hoặc nguồn/render đã tạo.

AffiHub không hiển thị lựa chọn hoặc khởi tạo OAuth ChatGPT/SIWC theo quyết định của chủ dự án. Tài liệu SIWC chỉ được giữ trong Porting Note như nghiên cứu đã đối chiếu, không thuộc product flow hay cấu hình runtime.

Nhãn Codex là lựa chọn đăng nhập riêng. Theo provider `codex` của 9Router tại commit đã pin, OAuth dùng Authorization Code + PKCE S256, state dùng một lần, scope `openid profile email offline_access`, callback local cố định `http://localhost:1455/auth/callback`, rồi đổi code tại token endpoint cấu hình. `CODEX_OAUTH_CLIENT_ID` được nạp từ `.env` local; không có client secret. Callback dùng cùng host `localhost`, state/PKCE verifier gắn với attempt Rails và token lưu mã hóa. Đây là flow quan sát trong một client bên thứ ba, không phải contract Codex công khai của OpenAI. Sau callback, connection chỉ đạt `pending_verification`: không gọi model, không lấy danh sách/quota từ backend riêng, không dùng `chatgpt.com/backend-api/codex/*`, không giả mạo CLI User-Agent/originator và không khẳng định tài khoản free/paid có quyền inference. OpenAI Developer Docs hiện mô tả Codex app-server dùng OAuth token được cấp quyền ChatGPT plan và nói không cần Codex sign-in riêng; AffiHub không dùng luồng SIWC đó và không coi token flow 9Router là quyền inference được OpenAI hỗ trợ. Chi tiết và file tham khảo nằm trong `affihub/docs/reference-analysis/ai-account-login.md`.

Gemini là Google OAuth cho **Gemini API** của Google Cloud project AffiHub, tách khỏi Gemini CLI OAuth và kết nối Drive/YouTube. Cho phép hoàn tất OAuth và kiểm tra model list, nhưng connection giữ trạng thái `pending_verification` cho tới khi smoke test cùng project chứng minh token refresh, `generateContent` thật, quyền/quota và nguồn giá. Google OAuth quickstart mới chỉ xác nhận REST `GET /v1/models` bằng Bearer token cùng `x-goog-user-project` và SDK có thể nhận OAuth credentials; trang GenerateContent vẫn minh họa API key nên không coi model list là bằng chứng inference. Không dùng `cloudcode-pa.googleapis.com/v1internal` hoặc client credential của 9Router. Khi gate chưa đạt, UI hiển thị “Chờ cấu hình/xác minh Gemini API” và chặn riêng bước LLM. Billing chưa liên kết nghĩa là cost/quota gate vẫn đóng cho job phụ thuộc Gemini.

Antigravity là lựa chọn UI “Chưa khả dụng”: điều khoản Google hiện cấm phần mềm bên thứ ba truy cập dịch vụ bằng Antigravity OAuth. `AiProviderConnections#create` không khởi tạo OAuth cho lựa chọn này và callback từ nguồn đó bị từ chối. Chỉ đánh giá lại khi Google công bố contract hoặc cấp quyền tích hợp phù hợp cho AffiHub. Repo [9Router](https://github.com/decolua/9router) commit `a99cf57239ff778b61e434c2786009d5ed1c412c` được tham khảo về provider adapter/state/PKCE, không phải nguồn cấp quyền; chi tiết ở `affihub/docs/reference-analysis/ai-account-login.md`.

MPT v1.3.8 dùng LLM provider/config API key cho `/scripts` và `/terms`; Gemini API cũng phải gọi endpoint chính thức trực tiếp nếu OAuth contract được xác minh. Codex hiện auth-only, không phải LLM provider. Không có ChatGPT/SIWC path; không đưa user OAuth token vào MPT OpenAI-compatible endpoint. Không gửi yêu cầu MPT tạo video trước khi cost gate/consent hiện có pass. Gemini cost/quota phải có nguồn project; MuAPI/stock/TTS tính theo lượt vẫn qua cost gate và consent.

## Risks / Trade-offs

- [API review hoặc quyền public thay đổi/được duyệt chậm] → Hiển thị trạng thái connector và nghiệm thu kỹ thuật riêng với public readiness; không đặt deadline bên ngoài làm điều kiện code hoàn tất.
- [Codex OAuth của 9Router không phải contract OpenAI công khai; Gemini API OAuth chưa xác minh; Antigravity chưa có contract cho bên thứ ba] → Codex chỉ được lưu ở `pending_verification` sau callback, không gọi inference/quota/private backend; giữ gate riêng và không suy ra quyền từ đăng nhập danh tính. ChatGPT/SIWC không nằm trong phạm vi.
- [`yt-dlp` extractor hỏng hoặc source từ chối tải] → Pin và cập nhật version có chủ ý, giới hạn request, hiện lỗi và fallback file local; không retry khi bị rate-limit/block.
- [Máy local tắt khi tới lịch] → Không hứa chạy khi máy ngủ; đánh dấu lịch bị lỡ và yêu cầu user chọn lịch lại hoặc đăng tay.
- [Timeout sau external side effect] → Giữ `OutcomeUnknown`, reconcile trước retry, dùng idempotency key/claim guard và lưu `ManualOutcomeConfirmed` riêng.
- [FFmpeg/MPT/TTS tiêu tốn tài nguyên hoặc không sẵn sàng] → Health check từ đúng network namespace, giới hạn worker và báo service lỗi riêng; giữ source/render có sẵn.
- [Google Sheets không có transaction/unique key] → Serialize upsert, dò key trước append, đối soát sau timeout; Rails database giữ authoritative record.
- [Nhiều platform có contract không đồng nhất] → Giữ workflow cụ thể theo connector, kiểm thử smoke riêng trên tài khoản test rồi mới trừu tượng hóa phần thực sự chung.

## Migration Plan

Design baseline không có video model hoặc user data video cần migrate. Thực hiện foundation/domain và luồng video local trước; thử Meta OAuth/Page/upload smoke spike sớm như section 2 để gỡ rủi ro API. Nếu chưa có app-role/Page test credentials, ghi rõ phần chưa xác minh thành cổng nghiệm thu live ở task 13.8 rồi tiếp tục các task local/độc lập; WebMock không thay thế bằng chứng quyền API thật. Tiếp tục local source/edit/render, MPT/TTS, `MetaGraphPublisher`/review flow, URL/discovery, TikTok/Instagram/YouTube, PublisherResolver/Scheduler, comment reply, Google và Telegram; cuối cùng chạy e2e từng nhánh. Spike Meta sớm là bước xác minh riêng, không phải publisher hoàn chỉnh. Schema được thêm cùng feature và RSpec; không ghi đè file source/render cũ.

Nếu cần dừng triển khai sau một phase, pause Scheduler/AutoResponder, disable connector/job mới tương ứng và giữ database, source, render cùng external outcome đã lưu. Không tự xóa bài đã publish hoặc dữ liệu Drive; rollback schema chỉ thực hiện theo migration đã review và không được làm mất record side effect ngoài hệ thống.
