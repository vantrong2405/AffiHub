# Meta Facebook Page OAuth và Reels — Porting Note

Ngày đối chiếu: 2026-10-06
Phạm vi: kết nối Facebook Page và đăng Facebook Reel bằng Page Access Token. Instagram Reels là API/luồng riêng, không nằm trong note này.

## Nguồn đã đọc và cách dùng

### Contract API chính thức của Meta

- [Facebook Login](https://developers.facebook.com/docs/facebook-login/): người dùng đăng nhập/cấp quyền qua authorization code callback; app secret chỉ xử lý ở backend.
- [Graph API access levels](https://developers.facebook.com/docs/graph-api/overview/access-levels/): kiểm tra quyền và access level của app trước khi mở kết nối cho người dùng ngoài app roles.
- [Page Videos reference](https://developers.facebook.com/docs/graph-api/reference/page/videos/), [Video reference](https://developers.facebook.com/docs/graph-api/reference/video/) và [Reels Publishing guide](https://developers.facebook.com/docs/video-api/guides/reels-publishing/): tài liệu contract cần kiểm tra lại theo Graph API version được cấu hình lúc implement.
- [Meta Facebook API Postman collection](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api): collection do Meta publish, được dùng ở đây làm request/response example cho Page token và Facebook Reels; collection không thay thế reference versioned của Graph API.
- [Meta permission reference](https://developers.facebook.com/docs/permissions/reference/): xác nhận scope, dependency, access level và App Review ngay trước khi tạo app configuration.
- [Meta Reels sample repository](https://github.com/fbsamples/reels_publishing_apis/tree/7bf98f94e75d841ecc9612c0061881d1d713c6bd): SHA `7bf98f94e75d841ecc9612c0061881d1d713c6bd`; đã đọc `fb_reels_publishing_api_sample/README.md` và `fb_reels_publishing_api_sample/index.js`. README ghi mẫu đang dùng Graph API v14.0 và license Meta Platform Policy; dùng để hiểu các pha upload/status, không bê nguyên API version hoặc code vào AffiHub.

### Source tham khảo, không phải contract

- [Postiz `FacebookProvider` tại commit `86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6`](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts), đọc ngày 2026-10-06. Đầu `main` khi ghim SHA là `86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6`.
- File này khai báo Graph API `v25.0`, các scope gồm `pages_show_list`, `business_management`, `pages_manage_posts`, `pages_manage_engagement`, `pages_read_engagement`, `read_insights`; có authorization-code exchange, kiểm tra `/me/permissions`, liệt kê Page bằng `/me/accounts` và tìm Page từ Business Manager.
- File **không gọi** `video_reels`. Nó có flow `video_stories` và đăng video/feed thông thường. Chỉ tham khảo ranh giới provider, việc chọn Page và phân loại một số lỗi. Không lấy scope đầy đủ, OAuth security, API version, endpoint, payload hoặc error mapping của Postiz làm contract cho AffiHub.

## OAuth, Page selection và quyền

1. Dùng Facebook Login server-side authorization-code flow: tạo authorization URL với callback đã đăng ký; callback đổi `code` lấy User Access Token ở backend. Không đưa App Secret hoặc token vào UI, exception/log. Lưu và đối chiếu OAuth `state` ngẫu nhiên, dùng một lần, hết hạn và gắn với phiên bắt đầu kết nối; dùng callback allowlist. Chỉ bật PKCE nếu Facebook Login configuration/API contract hiện hành xác nhận hỗ trợ.
2. Xin quyền tối thiểu theo thao tác MVP. Meta sample dùng `pages_show_list`, `pages_read_engagement`, `pages_manage_posts` cho liệt kê/chọn Page và publishing; sample bổ sung `pages_manage_engagement`, `pages_read_user_content` để chạy A/B test — hai scope đó không phải yêu cầu của Facebook Reels MVP. Kiểm tra dependency và Standard/Advanced Access của app trong Permission Reference/App Dashboard trước smoke test và trước production; không suy ra trạng thái duyệt quyền từ việc OAuth thành công.
3. Sau authorization, gọi `GET /{version}/me/accounts?fields=id,name,access_token,tasks` bằng User Access Token; hiển thị Page mà Meta trả về để chủ tài khoản chọn rõ ràng. Token tương ứng trong Page record là Page Access Token dùng cho publish. Không tự chọn Page đầu tiên và không xem việc có Page ID là đủ quyền; kiểm tra Page tasks/permission và xử lý trường hợp không có Page token.

## Facebook Reels: upload → process → publish

Dùng API version được khai báo trong AffiHub config (PROJECT_SPEC hiện chốt đối chiếu v26.0). Các ví dụ Postman dùng biến `{{api_version}}`; Postiz v25.0 và sample cũ v14.0 không được quyết định version runtime.

1. **Khởi tạo upload:** `POST /{page-id}/video_reels?upload_phase=start` cùng Page Access Token. Response chứa `video_id` và `upload_url`. Lưu `video_id`/checkpoint trước khi chuyển bước để worker có thể tiếp tục/reconcile.
2. **Upload file local:** gửi binary tới `https://rupload.facebook.com/video-upload/{version}/{video_id}` với `Authorization: OAuth {page_access_token}`, `offset`, `file_size` theo byte và `Content-Type: application/octet-stream`. Response thành công chỉ xác nhận pha upload; không đồng nghĩa Reel đã publish. MVP truyền Render Version trực tiếp, không cần public URL/CDN.
3. **Hoàn tất và publish:** `POST /{page-id}/video_reels` với `upload_phase=finish`, `video_id`, `video_state=PUBLISHED`, cùng `description`/`title` nếu có. Một response `success: true` là acknowledgement, chưa phải bằng chứng publish cuối.
4. **Poll status:** `GET /{video_id}?fields=status`. Theo Meta sample, `status` chứa `video_status` và trạng thái riêng cho `uploading_phase`, `processing_phase`, `publishing_phase`; các phase có thể kèm `errors`, và processing có `processing_progress`. Poll trong job nền có backoff/timeout hữu hạn. Chỉ chuyển Publication thành `Published` khi trạng thái publish cuối được Meta xác nhận; nếu status thiếu, lạ hoặc request timeout sau mutation thì giữ `OutcomeUnknown` và reconcile trước retry.
5. Khi hoàn tất, lưu Page ID, Meta video ID, permalink lấy từ field/edge được Graph API version đó hỗ trợ, và thời gian xác nhận. Không tự tạo permalink từ ID nếu API contract không xác nhận dạng URL.

## Lỗi và kết quả chưa rõ

- Giữ lại error code/subcode, `is_transient` nếu Meta trả về, `fbtrace_id` và lỗi từng processing/publishing phase; sanitize token, authorization header và URL nhạy cảm trước audit/log. Lỗi người dùng nên hiển thị thông điệp đã chuẩn hóa, không gửi nguyên response/token lên giao diện.
- Phân biệt lỗi input/quyền (không retry tự động), transient có thể retry theo policy, và timeout/mất kết nối sau lệnh start/upload/finish (chưa biết side effect đã xảy ra). Với trường hợp cuối, dò trạng thái/đối chiếu Reel theo `video_id`/Page trước; nếu chưa đủ bằng chứng thì chặn retry và yêu cầu xử lý `OutcomeUnknown` theo reliability workflow.
- API success ở start/upload/finish là acknowledgement từng bước; chỉ status cuối là tín hiệu `Published`. Status/error shape phải được xác nhận lại trên Graph API version đã chọn trong task smoke test.

## Giới hạn của bằng chứng và việc phải xác minh khi implement

- Meta sample README đang ghi giới hạn reel 9:16, tối thiểu 540×960, 23 fps và 4–60 giây, nhưng sample được đọc ở commit cố định và dùng v14.0. Không hardcode các giới hạn này trước khi đối chiếu guide/reference hiện hành của Graph API v26.0; đưa giới hạn đã xác minh vào preflight.
- Meta sample yêu cầu polling vì upload/publish là bất đồng bộ. Sample minh họa error trong `processing_phase.errors` và `publishing_phase.errors`; retryability thực tế phải dựa vào response hiện hành và thử nghiệm Page/app-role test, không chép bảng lỗi từ Postiz.
- Smoke test task 2.3 cần xác minh quyền, Page token, upload binary, status từng phase, permalink cuối, lỗi quyền, timeout/reconcile và trạng thái app access. Không gửi publish lần hai chỉ vì client không nhận được response của lần đầu.

## Contract và tham khảo — phân biệt khi port

| Nội dung | Nguồn được tin cậy | Cách dùng |
|---|---|---|
| OAuth, quyền, endpoint, payload, upload, status và lỗi Meta | Meta Graph API docs/versioned reference; Meta-published Postman collection và sample ở SHA đã ghi chỉ bổ sung ví dụ | Contract cần xác nhận theo version và app access hiện hành |
| Provider boundary, Page discovery, cấu trúc xử lý response của Postiz | `FacebookProvider` ở SHA `86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6` | Tham khảo thiết kế; không copy làm API truth/runtime dependency |
| Facebook Reels endpoint trong Postiz source đã ghim | Không có: file không implement `video_reels` | Không dùng Postiz để suy ra contract Facebook Reels |

## Cập nhật spike ngày 2026-10-07

- Đối chiếu lại [Meta Facebook API Postman collection](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api). Collection xác nhận ví dụ dùng User Access Token cho `/me/accounts`, Page Access Token cho Reels, upload file local qua `rupload.facebook.com`, poll `GET /{video_id}?fields=status`, rồi gửi `upload_phase=finish`. Collection này không mô tả quyền đọc `Video.source`.
- Đường dẫn [Video reference](https://developers.facebook.com/docs/graph-api/reference/video/) và [Page Videos reference](https://developers.facebook.com/docs/graph-api/reference/page/videos/) đã được thử đọc trực tiếp nhưng công cụ tra cứu không tải được nội dung Meta Developers trong lượt này. Vì vậy quyền đọc/tải `source` của video thuộc Page chưa được xác nhận theo contract hiện hành; không suy luận rằng có thể tải mọi video công khai.
- Kiểm tra cấu hình cục bộ chỉ in trạng thái có/không, không đọc giá trị: `META_APP_ID`, `meta.app_secret`, `meta.page_access_token` và `meta.page_id` đều chưa được cấu hình. Chưa có Page/app-role test trong database local; development database legacy được giữ nguyên. Không gửi request Meta thật trong lượt này.
- `Meta::Client#page_video` hiện có thể thăm dò `GET /{video-id}?fields=id,source` khi được cấp token. RSpec chỉ stub HTTP boundary; kết quả đó xác nhận cách ghép request trong code, không xác nhận quyền thật hay khả năng tải file.
- Task 2.3 vẫn cần app-role Page và credential cục bộ để xác minh source/read/download, upload MP4 tối giản, poll trạng thái cuối, rồi ghi lại Page ID, video ID và permalink thật. Không dùng response giả từ RSpec làm bằng chứng smoke test; không ghi token hoặc signed upload/source URL vào log.
