# Meta Facebook/Instagram public-comment auto-reply — Porting Note

Ngày đối chiếu: 2026-10-09

## Phạm vi

Note này chỉ áp dụng cho comment công khai trên bài đăng đã publish của Facebook Page và Instagram Professional account khi destination đã bật auto-reply. Theo OpenSpec, không xử lý TikTok comments, DM, Messenger hoặc inbox; câu trả lời là câu mặc định cố định theo destination, có thể được thay bằng keyword rule tĩnh. Không dùng LLM để sinh reply.

Meta API và quyền truy cập phụ thuộc loại đăng nhập, Graph API version, App Review và quyền của người dùng/Page. Các ví dụ dưới đây không thay thế xác minh trên app-role test account của AffiHub.

## Tài liệu Meta đã đối chiếu

- [Tài liệu Instagram API do Meta phát hành trên Postman](https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api) và [folder Facebook Login](https://www.postman.com/meta/instagram/folder/u4g5a2a/instagram-api-with-facebook-login), đọc ngày 2026-10-09. Tài liệu xác nhận flow Facebook Login dành cho Instagram Professional account (Business hoặc Creator) có Facebook Page liên kết, hỗ trợ quản lý/trả lời comment trên media và liệt kê `instagram_manage_comments` cùng `pages_read_engagement`, `pages_show_list`, `instagram_basic`, `instagram_content_publish`. Tài liệu collection nói các endpoint hỗ trợ cursor-based pagination; đây là contract pagination ở mức collection, chưa xác định tên field/cursor và giới hạn cụ thể của comment edge.
- [Facebook API documentation trong workspace Meta trên Postman](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api), đọc ngày 2026-10-09. Phần truy cập được mô tả cách lấy Page Access Token từ Page người dùng quản lý qua `/me/accounts`; collection này không được dùng làm căn cứ cho endpoint reply hoặc webhook comment.
- [Meta Instagram API with Instagram Login — collection do Meta phát hành trên Postman](https://www.postman.com/meta/instagram/folder/6raa77c/instagram-api-with-instagram-login), đọc ngày 2026-10-09. Đây là luồng đăng nhập khác, không yêu cầu Facebook Page liên kết và dùng permission `instagram_business_manage_comments`. MVP hiện chọn Facebook Login for Business theo spec 05; không trộn permission Instagram Login vào OAuth flow này.
- [Meta Graph API Webhooks](https://developers.facebook.com/docs/graph-api/webhooks/), [Webhooks for Pages](https://developers.facebook.com/docs/graph-api/webhooks/getting-started/webhooks-for-pages/) và [Instagram Platform Webhooks](https://developers.facebook.com/docs/instagram-platform/webhooks/) là nguồn chính thức cần dùng để xác minh subscription, event fields, callback verification và delivery contract.
- [Graph API object comments reference](https://developers.facebook.com/docs/graph-api/reference/object/comments/) và [Meta permissions reference](https://developers.facebook.com/docs/permissions/reference/) là nguồn chính thức cần dùng để xác minh thao tác đọc/reply và quyền Page tương ứng.

Các trang Meta Developers về Webhooks, Graph API comments, Instagram comment moderation và permissions được thử mở trực tiếp ngày 2026-10-09 nhưng trả 429 hoặc không truy cập được trong công cụ tra cứu. Tài liệu Postman chính thức xác nhận khả năng comment của Instagram và permission ở trên, nhưng không cung cấp đủ contract cho subscription/event payload hoặc request đọc/reply cần port. Vì vậy note này chưa khẳng định tên webhook field, cấu trúc payload, URL callback/challenge, retry headers, cursor cụ thể, giới hạn request, permission Page-comment, hay request/response cụ thể của thao tác đọc và reply Facebook/Instagram. Phải đối chiếu các chi tiết đó trên tài liệu Meta theo Graph API version được cấu hình trước khi triển khai Client; không suy ra chúng từ tên đường dẫn hoặc source Postiz.

## Postiz — nguồn tham khảo kiến trúc

Postiz chỉ được tham khảo để nhìn ranh giới provider và cách provider gửi comment; không phải API truth, runtime dependency hay code để sao chép. Repo Postiz được pin tại SHA `86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6`. Đã đọc ngày 2026-10-09:

- [FacebookProvider](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts): method `comment` đăng message lên edge `/{replyToId}/comments`, trong đó `replyToId` là comment cuối nếu có hoặc post ID; trả ID và permalink lấy từ response.
- [InstagramProvider](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/instagram.provider.ts): method `comment` đăng message lên edge `/{postId}/comments`, rồi đọc permalink từ media cha. Tham số `lastCommentId` không được dùng trong request của method này.
- Hai method trên là interface đăng comment gắn với luồng publish/comment của Postiz. Chúng không thể hiện webhook subscription, polling comment đến mới, event dedupe, keyword rule, pause/claim hoặc xử lý `OutcomeUnknown` cho inbound comment; không port chúng thành AutoResponder.
- License của repo được ghi nhận là AGPL-3.0. Chỉ tham khảo kiến trúc và API boundary, không copy hoặc vendor code.

## Ánh xạ vào contract AffiHub

1. Chỉ bắt đầu nhận comment sau khi publication trên Facebook/Instagram được xác nhận cuối cùng và auto-reply đã bật cho destination đó.
2. Dùng webhook Meta hoặc polling chính thức theo contract/spec. OpenSpec cho phép một trong hai; lựa chọn và khả năng API phải được xác minh trước khi chọn cách triển khai. Nếu có cả delivery lặp hoặc hai nguồn cùng quan sát một comment, khóa duy nhất theo destination cùng comment/event ID phải khiến một reply tối đa được tạo.
3. Ghép một câu reply mặc định cố định theo destination; chỉ thay bằng keyword rule tĩnh đang bật. Lưu snapshot rule và message thực tế trong append-only log. Không gọi LLM.
4. Trước mỗi lần claim comment, kiểm tra cờ pause. Event ngoài scope không được đưa vào quy trình reply.
5. Nếu lệnh gửi reply timeout sau khi có thể đã tới Meta, đối soát bằng API chính thức trước khi retry. Nếu không thể xác định kết quả, giữ `OutcomeUnknown` và yêu cầu một trong ba quyết định thủ công đã nêu trong spec; không gửi reply thứ hai một cách tự động.
6. Permission, Graph API version, webhook field, poll path/fields và các giới hạn provider phải được cấu hình theo convention YAML + `Rails.application.config_for` trong task implementation. Nội dung UX/lỗi thông thường tiếp tục viết trực tiếp trong Ruby/ERB theo `affihub/CLAUDE.md`.

## Việc phải xác minh trước task 10.3

- Trên Meta App Dashboard, xác nhận Facebook Login for Business được cấp `instagram_manage_comments` cùng permission/access tier thực tế cần thiết; xác nhận Page và Instagram Professional account liên kết thuộc người dùng test.
- Đọc lại tài liệu Meta Webhooks và comment references theo API version trong config; ghi tên subscription field, payload/event ID, quy tắc xác thực callback, polling pagination/limits, quyền đọc comment và thao tác reply.
- Trên Page/Instagram test destination, nhận một comment công khai và xác nhận event hoặc polling response; sau đó gửi một reply tĩnh duy nhất, lưu provider comment ID và bằng chứng response đã được khử secret.
- Thử timeout/reconcile trên test destination để xác định API có thể tìm reply đã gửi theo dữ liệu nào. Nếu không đủ bằng chứng thì để các lựa chọn `OutcomeUnknown` theo OpenSpec, không tự retry.
- Chỉ dùng WebMock trong RSpec để kiểm tra request boundary đã xác minh; test không thay cho quyền truy cập hoặc smoke test với Meta thật.

Note này ghi nhận giới hạn bằng chứng hiện có; cần cập nhật lại nếu lần xác minh API thật cho thấy contract khác.
