# Meta Facebook/Instagram public-comment auto-reply — Porting Note

Ngày đối chiếu tài liệu: 2026-10-09. API version AffiHub đang cấu hình: `v26.0`.

## Phạm vi

MVP chỉ tự trả lời comment công khai trên Facebook Page và Instagram Business đã liên kết Page. Không xử lý TikTok comments, DM, Messenger hoặc inbox; không dùng LLM. Meta API, quyền và khả năng nhận webhook còn phụ thuộc app mode, access level, Page task và tài khoản được cấp quyền.

## Nguồn chính thức đã đọc

- [Graph API object comments](https://developers.facebook.com/docs/graph-api/reference/object/comments/): comment object hỗ trợ edge `/comments`; phần Publishing cho phép tạo comment trên object, trả comment ID, yêu cầu Page access token có `MODERATE` và permission `pages_manage_engagement`.
- [Page Webhooks](https://developers.facebook.com/docs/graph-api/webhooks/getting-started/webhooks-for-pages/) và [Page webhook reference](https://developers.facebook.com/docs/graph-api/webhooks/reference/page/): Page field `feed` phát thay đổi của Page feed, gồm comment; payload `value` có các trường comment như `comment_id`, `post_id`, `item`, `verb`, `message`, `from` và `parent_id`. App cần `pages_manage_metadata`/`pages_show_list` và Page task phù hợp để cài app subscription qua `/{page-id}/subscribed_apps`.
- [Instagram API with Facebook Login trên Meta Postman](https://www.postman.com/meta/instagram/folder/u4g5a2a/instagram-api-with-facebook-login): flow được AffiHub dùng cho Instagram Business có Page liên kết; collection xác nhận API quản lý/trả lời comments và permission `instagram_manage_comments` cùng các quyền Page cần thiết. Postman là collection do Meta phát hành.
- [Instagram comment moderation](https://developers.facebook.com/docs/instagram-platform/comment-moderation/), [IG Comment Replies](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-comment/replies/), [Instagram Webhooks](https://developers.facebook.com/docs/instagram-platform/webhooks/) và [Instagram webhook reference](https://developers.facebook.com/docs/graph-api/webhooks/reference/instagram/): đã đọc trực tiếp ngày 2026-10-09.

## Contract đã xác minh

### Facebook Page

- Reply công khai bằng `POST /{comment-id}/comments`, gửi `message` và Page access token. Phản hồi thành công chứa comment ID. Page token phải đại diện người có task `MODERATE`; permission tạo reply là `pages_manage_engagement`.
- Theo dõi bằng Page webhook field `feed`. Chỉ nhận change có `item=comment` và `verb=add`; lấy ID từ `comment_id`, nội dung từ `message`, Page ID từ `entry.id`. Change `edited`/`remove`, item khác và comment do chính Page gửi không tạo reply.
- App cần đăng ký field `feed` trong Webhooks product và cài subscription cho từng Page bằng Page access token. Webhook `feed` cần `pages_manage_metadata` cùng `pages_show_list`.

### Instagram Business qua Facebook Login

- Reply công khai bằng `POST /{ig-comment-id}/replies?message={message}` trên Graph API host của flow Facebook Login. Thành công trả `id` của reply. Permission gồm `instagram_basic` và `instagram_manage_comments`, cùng quyền Page được tài liệu yêu cầu. Không reply comment bị ẩn hoặc comment trên live media; thao tác reply vào comment reply được Meta đưa về comment cấp đầu.
- Theo dõi bằng webhook field `comments`; payload có `object=instagram`, `entry[].id`, `changes[].field=comments` và `changes[].value`. Value chứa comment `id`, `text`, `from.id`, `self_ig_scoped_id`, `media.id` và `parent_id` khi là reply. Chỉ comment cấp đầu của media thường được đưa vào AutoResponder; bỏ qua event không phải `comments`, comment do account tự gửi và event không có ID/nội dung cần thiết.
- Webhooks product cần subscribe field `comments`; với Facebook Login, permission field gồm `instagram_basic`, `instagram_manage_comments`, `pages_manage_metadata`, `pages_read_engagement`, `pages_show_list`. Cài app subscription cho Page/account bằng token và endpoint Graph API tương ứng với Facebook Login.

### Callback chung

- Meta gửi GET với `hub.mode=subscribe`, `hub.verify_token`, `hub.challenge`. Chỉ trả lại challenge khi verify token trùng secret cấu hình.
- POST notification có JSON `object`/`entry`/`changes` và header `X-Hub-Signature-256: sha256=...`. Tính HMAC-SHA256 trên raw request body bằng Meta App Secret, so sánh constant-time rồi mới parse/enqueue. Trả HTTP 200 sau khi event hợp lệ đã được ghi bền; Meta có thể retry delivery trong tối đa 36 giờ nên dedupe theo destination + comment ID là bắt buộc.
- App cần ở Live mode để nhận notification; `comments` cần Advanced Access theo cấu hình Meta, Business Verification và tài khoản Instagram Professional công khai. Meta yêu cầu callback HTTPS có chứng thư hợp lệ. App local phải có callback HTTPS công khai (ví dụ tunnel do người vận hành tự cấu hình) thì Meta mới gọi được; code không tạo public tunnel.

## Repo tham khảo kiến trúc

Postiz chỉ dùng để đối chiếu ranh giới provider; không dùng làm nguồn API truth, runtime dependency hoặc code để sao chép. Repo pin tại SHA `86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6`:

- [FacebookProvider](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts) gửi comment qua `/{replyToId}/comments`.
- [InstagramProvider](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/instagram.provider.ts) có interface comment riêng; không dùng method này để suy ra webhook hoặc contract Instagram Graph API.
- Repo Postiz có license AGPL-3.0. Chỉ tham khảo kiến trúc, không vendor/copy/link thư viện này.

## Ánh xạ vào AffiHub

1. Controller chỉ nhận webhook handshake/event và gọi Service; signature verification, payload normalization, event persistence, claim, reply và audit nằm trong Service/Model/Job.
2. Routes theo design: singleton webhook resource `GET` cho handshake, `POST` cho delivery. Không thêm controller action tùy ý.
3. `AutoReplyEvent` dùng unique key destination + provider comment ID. Một replay chỉ trả về event/workflow đã có, không enqueue hoặc gửi reply thứ hai.
4. Trước claim kiểm tra global auto-reply pause. Lưu outbound attempt trước request; timeout/malformed response có thể đã phát sinh side effect thì giữ `OutcomeUnknown`. Không tự retry khi chưa reconcile.
5. YAML qua `Rails.application.config_for` chỉ chứa cấu hình vận hành cần tập trung: API version/base URL và endpoint paths, OAuth scopes, subscription fields, timeout/retry limits, cùng machine statuses/event types/defaults/limits/error-code keys. Payload field mapping, signature header và parsing contract cố định nằm trong provider code. Meta App Secret và webhook verify token là secrets, giữ trong Rails credentials; câu chữ hiển thị/log thân thiện để trực tiếp trong Ruby/ERB.

## Chưa được smoke test

Tài liệu xác nhận request contract, nhưng chưa xác minh bằng Page/Instagram test account của AffiHub: app mode/access tier, quyền thực được cấp, subscription hoạt động, delivery qua HTTPS tunnel, reply thật, timeout/reconcile và hành vi retry. Các yêu cầu này vẫn là production/runtime gates; RSpec/WebMock không thay thế smoke test trên tài khoản Meta thật.
