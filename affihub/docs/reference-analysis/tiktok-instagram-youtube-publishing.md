# TikTok, Instagram Reels và YouTube — Porting Note

Ngày đối chiếu tài liệu: 2026-10-08  
Phạm vi: OAuth, chọn account/channel, consent, media upload, polling, lỗi, quota và review gate cho ba publisher. Đây là contract tham khảo để implement; chưa phải bằng chứng rằng tích hợp AffiHub đã chạy.

## Kết luận theo từng provider

| Provider | OAuth và đích đăng | Transfer và trạng thái cuối | Giới hạn/review cần giữ |
|---|---|---|---|
| TikTok | Login Kit OAuth với `video.publish`; tài khoản creator được nhận diện bằng `open_id` | Direct Post `FILE_UPLOAD`, lưu `publish_id`/upload URL/chunk checkpoint, poll status | App chưa audit: tối đa 5 poster khác nhau/24 giờ, account phải private và bài `SELF_ONLY`. `creator_info` có thể báo cap đã chạm bằng error code, nhưng không trả số lượt còn lại. |
| Instagram Reels | Facebook Login for Business; chọn Page từ `/me/accounts`; lưu Page token và `instagram_business_account` ID | Tạo Reels container resumable, gửi file đến URI `rupload.facebook.com`, poll container, gọi `media_publish` | Đọc `content_publishing_limit` trước publish; không cố định quota. App access/review và chính xác response hiện hành cần xác minh trên app/Page test. |
| YouTube | Google OAuth; xác định channel người dùng sở hữu trước khi upload | Resumable `videos.insert`, lưu session URI/offset/video ID, poll processing | `videos.insert` project chưa qua compliance audit bị giới hạn private. `search.list`, `videos.insert` và các API khác có quota bucket riêng. |

## Thứ bậc nguồn và giới hạn xác minh

1. Tài liệu API/chính sách chính thức của nền tảng là contract cho scope, endpoint, payload, status, quota và review gate.
2. Meta-published Postman collection bổ sung ví dụ request/response cho Instagram Facebook Login và Page selection. Đây là collection thay đổi được, không phải bản API có version pin.
3. Meta Reels sample ở commit cố định bổ sung ví dụ local resumable upload. README của sample còn ghi quota 25 bài/24 giờ; không dùng con số đó làm giới hạn hiện hành.
4. Postiz chỉ là source tham khảo cấu trúc provider/error boundary tại SHA đã pin bên dưới. Không lấy Postiz làm API truth, không thêm làm runtime dependency và không copy license/code.

Ngày 2026-10-08, các trang Instagram Platform chính thức về Facebook Login, Content Publishing và `content_publishing_limit` trả HTTP 429 khi tra cứu. Vì vậy, phần Instagram dùng Meta-published Postman collection và sample đã pin để mô tả flow; response fields/quota runtime và quyền app phải được kiểm tra lại bằng trang Meta hiện hành và Page test ở task 7.5. Không dùng các số 25/24 giờ trong sample cũ hay số quota cố định khác.

## 1. TikTok Direct Post

### OAuth, scope và access tier

- Dùng TikTok Login Kit OAuth 2.0 và xin `video.publish` để gọi Content Posting Direct Post. Scope phải được TikTok duyệt cho app và từng người dùng phải cấp consent; chỉ dùng scope thực tế được trả lại trong OAuth response.
- TikTok yêu cầu client secret và token được giữ server-side. Access token hiện có thời hạn 24 giờ, refresh token 365 ngày; refresh response có thể cấp refresh token mới, phải lưu token mới thay token cũ.
- Redirect URI phụ thuộc loại client. Web flow cần HTTPS và URI đã đăng ký, tĩnh. Desktop Login Kit cho phép `http`/`https` loopback `localhost` hoặc `127.0.0.1` với port và URI tĩnh; flow này yêu cầu PKCE `S256` với verifier 43–128 ký tự. AffiHub hiện chạy local Rails; phải cấu hình app theo đúng loại client trước khi implement, không dùng callback tùy tiện.
- Dùng state ngẫu nhiên, hết hạn, một lần và gắn phiên; callback URI phải nằm trong allowlist. Client secret, token, upload URL có query token và authorization header không được log.

### Creator info, consent và cap

- Gọi `POST /v2/post/publish/creator_info/query/` bằng scope `video.publish` ngay trước khi dựng màn xác nhận Direct Post; TikTok yêu cầu dùng thông tin mới nhất. API trả nickname, privacy options, comment/duet/stitch disabled flags và `max_video_post_duration_sec`; rate limit hiện ghi là 20 request/phút/user token.
- Người dùng phải xem đúng preview, tự chọn privacy (không có giá trị mặc định) từ `privacy_level_options`, tự chọn interaction settings (không mặc định bật); các interaction bị creator tắt phải bị khóa. Commercial Content tắt mặc định; khi bật phải khai báo brand organic/branded content đúng lựa chọn. `SELF_ONLY` không tương thích với branded content. Gửi `is_aigc=true` chỉ theo khai báo/consent của người dùng.
- TikTok yêu cầu người dùng xác nhận music usage trước khi đăng, hiển thị creator nickname, preview và cho phép sửa nội dung. Không thêm watermark/logo/quảng bá AffiHub lên media; UI phải báo thời gian xử lý không được bảo đảm.
- **Có tín hiệu cap động, không có counter:** `creator_info/query` có thể trả `error.code=spam_risk_too_many_posts` (HTTP 200 intentional) khi creator đã chạm daily posting cap; endpoint Direct Post cũng mô tả lỗi này. Đây là tín hiệu “đã chạm”, không cung cấp số cap, số đã dùng, số còn lại hay thời điểm mở lượt mới. Nếu request thành công và không có error này, UI chỉ có thể ghi `Chưa thể kiểm tra số bài còn lại`; không suy ra số lượt từ mức “thường khoảng 15”.
- Tách cap account với cap app: `reached_active_user_cap` là daily quota active publishing users của app client, dựa trên usage estimate/review; `spam_risk_too_many_posts` là cap đăng của creator trong cửa sổ 24 giờ. Với app chưa audit, AffiHub tự đếm tối đa 5 poster khác nhau/24 giờ; provider yêu cầu các account dùng app phải private và Direct Post ở `SELF_ONLY`.
- Content Sharing Guidelines yêu cầu API client phục vụ creator đăng nội dung gốc và hướng tới người dùng rộng; tài liệu nêu app chỉ giúp đăng nội dung của chính người vận hành/team hoặc sao chép nội dung tùy ý từ nền tảng khác là use case không chấp nhận. Vì AffiHub có discovery/import nguồn ngoài, app review cho Direct Post cần xác minh rõ intended use, quyền sử dụng và trải nghiệm creator; consent bản quyền trong AffiHub không đảm bảo TikTok sẽ duyệt app.

### Upload, poll và lỗi

1. Chỉ sau consent tường minh, gọi `POST /v2/post/publish/video/init/` với `post_info` đã duyệt và `source_info.source=FILE_UPLOAD`. Lưu `publish_id`, upload URL nhạy cảm và checkpoint trước bước tiếp theo. Request init giới hạn 6 lần/phút/user token; upload URL hết hạn sau một giờ.
2. Gửi file binary tuần tự bằng `PUT` tới toàn bộ upload URL, gồm query parameters. Mỗi chunk 5–64 MB; chunk cuối có thể lớn hơn chunk size tối đa 128 MB. File dưới 5 MB gửi một chunk; tối đa 1000 chunks. Gửi `Content-Length` và `Content-Range`; response `206` nghĩa là còn chunk, `201` nghĩa là đã upload hết. Lưu uploaded offset/checkpoint sau từng response. Redact upload URL khỏi log/exception/UI.
3. Poll `POST /v2/post/publish/status/fetch/` theo `publish_id` (tối đa 30 lần/phút/user token), hoặc nhận webhook đã cấu hình. `PROCESSING_UPLOAD` là đang upload; `PUBLISH_COMPLETE` xác nhận Direct Post đã được đăng; `FAILED` là lỗi cuối. Không có SLA cho thời gian xử lý. Public `post_id` chỉ được trả sau moderation; response có thể chưa có ID khi bài đang chờ kiểm duyệt.
4. Không retry tự động các lỗi `auth_removed`, `spam_risk_user_banned_from_posting`, `spam_risk_text` hoặc `spam_risk_too_many_posts`. `rate_limit_exceeded` cần backoff; lỗi 5xx/network chỉ retry sau đối soát checkpoint. Timeout sau init/upload/publish có thể tạo side effect, phải giữ `OutcomeUnknown` và reconcile, không khởi tạo publish mới.

### Review gate

- App chưa qua audit Content Posting API chỉ được private visibility/`SELF_ONLY`, account phải private và tối đa 5 poster/24 giờ. Gỡ giới hạn public cần audit riêng; base app review không thay thế audit publish.
- App review/intended use phải phù hợp Creator Sharing Guidelines, scope `video.publish` đã được phê duyệt, public Terms/Privacy/URL verification nếu dùng URL pull, demo UX và consent. Không hứa thời hạn hoặc kết quả audit.
- Direct Post hiện dùng `FILE_UPLOAD` vì AffiHub MVP lưu source/render local trên máy người dùng. Nếu đổi sang hosted server/object storage, phải đánh giá lại hướng dẫn TikTok khuyến nghị `PULL_FROM_URL` cho nội dung đã ở server API client; URL phải do app sở hữu/xác minh, HTTPS và không redirect.

## 2. Instagram Reels qua Facebook Login

### OAuth, scope và Page mapping

- MVP dùng Instagram API with Facebook Login qua Facebook Login for Business; không dùng Instagram Login flow.
- Meta-published Instagram API collection đang liệt kê cho Facebook Login các permission `pages_show_list`, `pages_read_engagement`, `instagram_basic`, `instagram_content_publish`. `instagram_manage_comments` chỉ cần cho comment workflows; không xin chỉ để đăng Reel. Các scope `instagram_business_basic` và `instagram_business_content_publish` thuộc Instagram Login, không đưa vào OAuth của Facebook Login.
- User Access Token gọi `GET /{version}/me/accounts?fields=id,name,access_token,tasks,instagram_business_account`. Hiển thị Page đủ quyền để người dùng chọn rõ ràng; lưu mapping Page ID, Page Access Token và `instagram_business_account.id` cho connection được chọn. Không tự chọn Page đầu tiên, không trả Page token lên UI/log.
- Meta-published collection mô tả Facebook Login cho Instagram Professional Business và Creator accounts. OpenSpec/PROJECT_SPEC giới hạn MVP ở Business account có Page liên kết; đây là product gate hẹp hơn capability chung của collection, không được mô tả Creator account là platform-ineligible.
- Scope list trên là xác minh từ Meta-published collection ngày 2026-10-08. Canonical Meta docs/App Dashboard phải được kiểm tra lại để xác nhận permission dependencies, Standard/Advanced Access, App Review và trạng thái app-role trước khi gửi production requests. OAuth thành công không chứng minh permission đã được duyệt cho người dùng ngoài app roles.
- PKCE cho Facebook Login for Business chưa được xác minh trong tài liệu Meta có thể truy cập ở lượt này; dùng state/session/callback allowlist theo spec và xác minh PKCE support trên flow đã chọn trước khi bật.

### Local resumable upload, poll và publish

1. Gọi create media container cho `media_type=REELS` với `upload_type=resumable`; Meta Reels sample ở SHA pin xác nhận local-file flow trả container ID và upload URI.
2. Gửi binary local trực tiếp tới URI `rupload.facebook.com` theo Resumable Upload Protocol, không cần public `video_url`, CDN hoặc relay. Lưu container ID/upload checkpoint trước bước tiếp; signed/session URI không được log.
3. Poll container `GET /{container-id}?fields=status_code,status` cho tới `FINISHED`, rồi mới gọi `POST /{ig-user-id}/media_publish?creation_id={container-id}`. Lưu media ID trả về. Resolve permalink bằng Graph API theo response/reference hiện hành; không tự ghép URL từ ID.
4. `media_publish` success là acknowledgement của request. Chỉ ghi `Published` khi API xác nhận kết quả cuối theo contract đã kiểm tra. Timeout sau publish giữ `OutcomeUnknown`; truy vấn container/media trước khi quyết định, không gọi `media_publish` lần nữa khi chưa giải quyết kết quả.
5. Trước publish, gọi `GET /{ig-user-id}/content_publishing_limit` theo Graph API version hiện hành và dùng quota/usage response từ API. Không hardcode 25/50/100 hoặc giờ mở quota. Canonical endpoint docs và response fields trả 429 trong lượt tra cứu; kiểm tra lại schema/permissions và response bằng Page test trước khi implement cap guard.

### Lỗi và review gate

- Chuẩn hóa Graph API error code/subcode, transient indicator và `fbtrace_id`; loại token/session URI khỏi log. Lỗi permission/account không retry; transient có backoff; timeout sau lệnh tạo container/upload/publish cần reconcile từ container/media ID trước.
- Page phải liên kết Instagram Business account theo product gate, token/Page tasks phải đủ quyền tạo nội dung, và app cần access tier/App Review phù hợp với nhóm người dùng. Story publishing không thuộc MVP.
- Không dùng quota `25 posts / 24 hours` từ README sample pin: sample cũ không phải nguồn quota hiện hành. Cũng không copy format/limit từ sample vào preflight nếu chưa đối chiếu Meta docs hiện hành.

## 3. YouTube upload

### OAuth, scope và channel

- Dùng Google OAuth authorization-code flow server-side với exact redirect URI, random state gắn phiên, server-side client secret và `access_type=offline` khi cần refresh token. Google khuyến nghị incremental authorization và token encryption at rest. Google hỗ trợ PKCE cho installed/desktop OAuth flow; nếu AffiHub tiếp tục chạy như local desktop app, dùng PKCE `S256`. Nếu đăng ký Web application OAuth client, xác nhận rõ flow/type trước khi implementation.
- `youtube.upload` là scope hẹp cho upload; `youtube.readonly` dùng cho `channels.list(mine=true)` để nhận diện/select channel. Xác minh scope grants thực tế và OAuth consent screen trước khi bật connector. Người dùng chọn đúng channel; không suy ra từ Google account email.
- OAuth app verification (nếu Google yêu cầu theo consent/scope/app distribution) khác với YouTube API Services compliance audit điều khiển giới hạn private-only.

### Consent, upload và processing

- Trước nút gửi `videos.insert`, người dùng xác nhận channel, title/description/tags, privacy status, `selfDeclaredMadeForKids` và `containsSyntheticMedia` theo nội dung thực tế. User agreement/confirmation phải gắn với account, render version và Publication.
- YouTube API Services Terms yêu cầu ngay trên màn hình có nút upload hiển thị cảnh báo upload bằng ngôn ngữ app. Với AffiHub desktop/local, link dùng là `https://www.youtube.com/t/terms`; nội dung tiếng Việt cần giữ đủ nghĩa: “Khi bấm Tải lên, bạn xác nhận nội dung tuân thủ Điều khoản YouTube (bao gồm Nguyên tắc cộng đồng) tại [link]. Hãy không vi phạm bản quyền hoặc quyền riêng tư của người khác.” Terms cũng yêu cầu có lựa chọn upload lên channel của người dùng; AffiHub hiện chỉ chọn channel người dùng nên đáp ứng prominence gate đó.
- Khởi tạo resumable upload qua `POST https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status`. Lưu `Location` session URI và offset trước khi gửi bytes; session URI là secret. Upload media bằng `PUT`; `308 Resume Incomplete`/`Range` cho offset đã nhận. Trước retry upload sau lỗi mạng/5xx, query session status; không tạo `videos.insert` session mới khi session cũ còn reconcile được.
- Lưu video ID khi nhận response. Poll `videos.list` với `processingDetails,status` theo owner token; `processingStatus=processing` là chờ, `succeeded` là xử lý xong, `failed`/`terminated` cần kết luận lỗi. Upload accepted chưa phải `Published`. Timeout mất session response hoặc status chưa rõ phải giữ `OutcomeUnknown` và reconcile trước retry.
- Phân biệt `quotaExceeded` (Google Cloud project/API quota) với `uploadLimitExceeded` (daily upload restriction riêng của channel), và lỗi metadata/auth không retry mù. Cạn quota YouTube chỉ chặn thao tác YouTube phụ thuộc bucket đó.

### Quota và compliance gate

- Tài liệu YouTube hiện liệt kê default 100 `search.list` calls/ngày trong Search Queries bucket, 100 `videos.insert` calls/ngày trong Video Uploads bucket, và 10.000 quota units/ngày cho API methods còn lại. Tài liệu `videos.insert` hiện tính mỗi insert là 1 quota unit trong bucket Video Uploads. Revision history ghi quá trình chuyển sang granular quota bắt đầu 2026-06-01; Google Cloud Console là nguồn authoritative cho quota của project đang dùng và có thể đổi theo project/audit.
- AffiHub chỉ đếm request do chính AffiHub tạo, theo bucket riêng; không thể biết call của app khác dùng chung project. Hiển thị nguồn/link Console và không biến local counter thành quota remaining authoritative.
- Mọi `videos.insert` từ API project chưa audit được tạo sau 2020-07-28 bị giới hạn private viewing. Public upload cần YouTube API Services audit. Audit này không thay thế OAuth consent-screen verification.

## Checkpoint và retry contract chung

- Ghi checkpoint remote sau từng side effect đã xác nhận: TikTok `publish_id`/chunk offset, Instagram container/media ID, YouTube resumable session URI/offset/video ID. Signed URI/token/query credential luôn được redact.
- Lỗi chắc chắn trước khi request tới provider có thể retry theo policy. Lỗi timeout sau khi request có thể đã tới provider phải vào `OutcomeUnknown`, reconcile bằng ID/session API trước; không tạo side effect mới để “thử lại cho chắc”. Chỉ provider status cuối mới chuyển `Published`; ghi platform ID/permalink/timestamp khi API trả/đối soát được.
- Request/response success trung gian (init/container/session/upload) không được ánh xạ thành Published. Không gộp ba nền tảng thành một upload contract chung làm mất protocol/checkpoint riêng của provider.

## Source references

### Tài liệu/API chính thức

- TikTok [Login Kit Desktop](https://developers.tiktok.com/docs/en/login-kit-desktop), [User Access Token Management](https://developers.tiktok.com/docs/en/oauth-user-access-token-management?enter_method=left_navigation), [Query Creator Info](https://developers.tiktok.com/docs/en/content-posting-api-reference-query-creator-info), [Direct Post](https://developers.tiktok.com/docs/en/content-posting-api-reference-direct-post), [Media Transfer Guide](https://developers.tiktok.com/docs/en/content-posting-api-media-transfer-guide), [Get Post Status](https://developers.tiktok.com/docs/en/content-posting-api-reference-get-video-status), [Content Sharing Guidelines](https://developers.tiktok.com/docs/en/content-sharing-guidelines), [App Review Guidelines](https://developers.tiktok.com/docs/en/app-review-guidelines).
- Meta [Instagram API with Facebook Login collection](https://www.postman.com/meta/instagram/folder/u4g5a2a/instagram-api-with-facebook-login), [Page token and Instagram Business mapping example](https://www.postman.com/meta/instagram/request/lpx8lul/get-access-tokens-of-pages-you-manage), canonical [Facebook Login path](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-facebook-login/), [Content Publishing](https://developers.facebook.com/docs/instagram-platform/content-publishing/), [`content_publishing_limit`](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/content_publishing_limit), [Graph API access levels](https://developers.facebook.com/docs/graph-api/overview/access-levels/), [Permissions reference](https://developers.facebook.com/docs/permissions/reference/).
- Google [Web Server OAuth](https://developers.google.com/identity/protocols/oauth2/web-server), [OAuth best practices](https://developers.google.com/identity/protocols/oauth2/resources/best-practices), [Installed/desktop OAuth and PKCE](https://developers.google.com/identity/protocols/oauth2/native-app), [`videos.insert`](https://developers.google.com/youtube/v3/docs/videos/insert), [Resumable upload protocol](https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol), [`videos.list`](https://developers.google.com/youtube/v3/docs/videos/list), [quota and compliance audits](https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits), [quota revision history](https://developers.google.com/youtube/v3/revision_history), [API errors](https://developers.google.com/youtube/v3/docs/errors), [YouTube API Services Terms](https://developers.google.com/youtube/terms/api-services-terms-of-service).

### Source đã pin, chỉ dùng làm tham khảo

- [Meta `insta_reels_publishing_api_sample/README.md`](https://github.com/fbsamples/reels_publishing_apis/blob/7bf98f94e75d841ecc9612c0061881d1d713c6bd/insta_reels_publishing_api_sample/README.md), SHA `7bf98f94e75d841ecc9612c0061881d1d713c6bd`, đọc 2026-10-08. Dùng để xác nhận resumable local binary → `rupload.facebook.com` → poll → publish; không dùng API version, numeric limit hoặc media constraints cũ làm runtime config.
- [Postiz `tiktok.provider.ts`](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.ts), [Postiz `instagram.provider.ts`](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/instagram.provider.ts), [Postiz `youtube.provider.ts`](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/youtube.provider.ts), SHA `86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6`, đối chiếu 2026-10-08. Chỉ tham khảo provider boundaries/state/error handling; endpoint/scope/quota/API behavior phải lấy từ nguồn chính thức.
