# `yt-dlp` và YouTube discovery — Porting Note

Ngày đối chiếu: 2026-10-07  
Phạm vi: tải một video từ URL do người dùng đưa/chọn, YouTube Data API discovery, provenance, attribution và fallback import local. Note này không xác nhận quyền tải media hay thay thế platform review.

## Nguồn và phiên bản đã đọc

### `yt-dlp`

- [Release `2026.08.19`](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.08.19), commit `3a08bea`: bản stable mới nhất trên trang release tại ngày đối chiếu. Đây là mốc để chạy thử khi implement, không phải runtime pin đã triển khai trong AffiHub.
- [README tại tag `2026.08.19`](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/README.md): command nhận option và URL; `--no-playlist` tải riêng video khi URL đồng thời tham chiếu playlist; có cấu hình timeout, retry, giới hạn kích thước và định dạng. README mô tả stable có thể chậm hơn nightly khi website đổi và khuyến nghị nightly cho người dùng thường xuyên. AffiHub vẫn phải ghim binary/tag đã kiểm tra, không tự cập nhật runtime.
- [Danh sách extractor tại tag `2026.08.19`](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/supportedsites.md): chỉ là danh sách extractor hiện có; upstream cảnh báo website liên tục thay đổi và danh sách không đảm bảo một URL cụ thể tải được. Có extractor Instagram/tag nhưng đó là extractor của downloader, không phải discovery API chính thức.
- `yt-dlp` là downloader bên thứ ba, không phải API contract hay bằng chứng quyền tải của YouTube/Meta/TikTok. Không dùng extractor, trang Discover/For You, cookie tài khoản hoặc browser automation để tìm video hay né rate limit.

### YouTube Data API và platform policy

- [YouTube `search.list`](https://developers.google.com/youtube/v3/docs/search/list) là endpoint tìm metadata theo truy vấn. `q` là từ khóa; cần đặt `type=video` để không lẫn channel/playlist. `regionCode` giới hạn video có thể xem ở vùng, còn `nextPageToken` dùng để xin trang kế tiếp.
- [YouTube `videos.list`](https://developers.google.com/youtube/v3/docs/videos/list) với `chart=mostPopular` trả video phổ biến theo `regionCode` và `videoCategoryId`. Đây là chart theo vùng/category, không phải keyword search hay một bảng “viral/trending” chung.
- [Quota overview](https://developers.google.com/youtube/v3/getting-started#quota): mặc định `search.list` có bucket 100 calls/ngày; `videos.list` tính 1 quota unit/call trong bucket quota khác dùng chung với các endpoint còn lại. Google có thể đổi hạn mức; API Console là nguồn authoritative.
- [Developer Policies](https://developers.google.com/youtube/terms/developer-policies): API data không được giữ vô thời hạn; non-authorized data phải được refresh hoặc xóa trong tối đa 30 ngày. Policy cũng cấm API Client scrape YouTube/Google Applications hoặc lấy dữ liệu/nội dung đã scrape.
- [Branding Guidelines](https://developers.google.com/youtube/terms/branding-guidelines) và [Terms of Service, attribution](https://developers.google.com/youtube/terms/api-services-terms-of-service/#attribution): dữ liệu hiển thị cần giữ attribution thích hợp; logo YouTube khi dùng phải link tới nội dung YouTube và không được sửa/che thương hiệu.

### Giới hạn discovery của Instagram và TikTok

- [Instagram API collection do Meta publish](https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api): Facebook Login API dành cho Instagram Professional (Business/Creator), yêu cầu Instagram Professional Account liên kết Facebook Page và có chức năng tìm media theo hashtag. Đây là hashtag discovery có quyền/điều kiện account; không phải tìm kiếm văn bản tổng quát hay chart “viral”. Reference: [IG Hashtag Search](https://developers.facebook.com/documentation/instagram-platform/instagram-graph-api/reference/ig-hashtag-search), [IG Hashtag](https://developers.facebook.com/documentation/instagram-platform/instagram-graph-api/reference/ig-hashtag).
- [TikTok Research API eligibility](https://developers.tiktok.com/products/research-api/) và [Query Videos](https://developers.tiktok.com/docs/en/research-api-specs-query-videos): endpoint tìm public video tồn tại, nhưng access yêu cầu nhà nghiên cứu đủ điều kiện, độc lập/phi thương mại, nộp hồ sơ và được duyệt. Đây không phải quyền discovery mặc định cho AffiHub.
- Kết luận phạm vi: không tuyên bố Instagram/TikTok “không có API”. MVP hiện chỉ bật YouTube discovery; không dùng Instagram/TikTok API discovery cho tới khi xác minh được đúng account, quyền, access tier và mục đích được phép. Không thay các điều kiện đó bằng crawler hoặc extractor `yt-dlp`.

## Contract YouTube discovery

### Keyword search

Ví dụ request shape, không chứa API key:

```text
GET https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&q=<keyword>&regionCode=VN&maxResults=25
```

`search.list` có cost 1 unit/call trong bucket riêng mặc định 100 calls/ngày; gọi trang kế tiếp bằng `pageToken` là một API call mới. Search result chứa `videoId` và snippet cơ bản như title, channel, `publishedAt`, description và thumbnail. Chỉ dùng `videoId` khi tạo canonical URL sau khi người dùng chọn kết quả:

```text
https://www.youtube.com/watch?v=<video_id>
```

Không tự tải kết quả search, không mở playlist/channel URL từ metadata, và không dùng `pageInfo.totalResults` làm số trang; phân trang theo token của API.

### Popular chart

Ví dụ request shape:

```text
GET https://www.googleapis.com/youtube/v3/videos?part=snippet,statistics&chart=mostPopular&regionCode=VN&videoCategoryId=<category_id>
```

UI phải ghi rõ “Phổ biến trên YouTube · Việt Nam · <category>”. `videoCategoryId` cần lấy/hiển thị theo danh mục API trả; không đặt nhãn “tìm theo từ khóa” hoặc “viral toàn YouTube”. Mỗi call `videos.list` có cost 1 unit trong bucket quota dùng chung.

### Attribution, provenance và thời hạn API data

- Hiển thị title, channel title, thumbnail và link video với attribution YouTube phù hợp; không làm người xem hiểu YouTube chứng thực AffiHub. Nếu dùng YouTube logo, link logo tới nội dung YouTube theo Branding Guidelines.
- Lưu provenance phân biệt `source_platform`, canonical URL, thời điểm discovery, loại truy vấn (`keyword` hoặc `popular_chart`), region/category, video ID và hành động người dùng đã chọn. API metadata dùng để render lựa chọn là cache tạm; trước khi đủ 30 ngày phải refresh từ API hoặc xóa các trường API-derived. Không dùng cleanup này để xóa provenance do người dùng tự cung cấp hay metadata `ffprobe` của file local.
- Chọn video chỉ tạo yêu cầu nguồn sau một thao tác rõ ràng của người dùng. Cảnh báo quyền sử dụng/Điều khoản vẫn phải hiện trước khi enqueue downloader; lựa chọn hoặc attribution không phải giấy phép tải/nội dung.

## Download contract và lỗi

- URL dạng mẫu: `https://www.youtube.com/watch?v=<video_id>`. Giá trị thật chỉ lấy từ URL do user nhập hoặc video đã được user chọn. Truyền URL thành argument riêng, không ghép vào shell string; buộc tải một video với `--no-playlist`.
- `yt-dlp` có retry mặc định lớn (hiện README ghi 10 lượt download, 10 lượt fragment, 3 lượt extractor) và có option `--socket-timeout`. Implementation phải đặt timeout tổng của job, timeout socket, filesize cap và retry hữu hạn một cách tường minh; phản hồi rate-limit/block phải dừng, không enqueue retry mù.
- Kết quả “không hỗ trợ”, private/deleted, no formats, geo/permission denied, HTTP 429/block, timeout, file quá lớn và invalid output cần ánh xạ thành reason code ổn định. Không hiển thị hoặc ghi nguyên stderr/provider URL vào audit nếu có thể chứa cookie, token hay signed URL. Hướng dẫn user tải file qua YouTube Studio/Google Takeout nếu họ là chủ sở hữu, rồi import file local.
- `--no-playlist` chỉ xử lý playlist expansion; nó không tạo network sandbox. Input host allowlist một mình không đủ: extractor có thể gọi host/redirect/manifest/CDN khác. Worker cần egress proxy hoặc network control kiểm tra và ghim DNS/IP ở mọi hop, gồm playlist manifest và media segment; từ chối file/local/private/metadata endpoints. Nếu chưa đảm bảo được egress, không chạy downloader.

## Policy conflict cần giữ hiển thị

YouTube Developer Policies cấm API Client scrape YouTube Applications hoặc lấy scraped data/content; `yt-dlp` là extractor bên thứ ba, không phải YouTube Data API. Các nguồn đã đọc không xác nhận rằng thao tác “tìm bằng YouTube Data API → user chọn → tải cùng URL bằng `yt-dlp`” được policy cho phép. Project hiện chấp nhận rủi ro tải URL theo yêu cầu; vì vậy UI/Porting Note không được gọi flow này là API download chính thức hay bảo đảm tuân thủ. Giữ import file do chủ sở hữu xuất làm fallback; cần compliance review riêng trước khi mở tính năng này cho người dùng khác.

## Checklist khi implement

1. Ghim tag và checksum `yt-dlp` trong runtime; ghi version vào log an toàn khi bắt đầu job.
2. Worker độc lập với web request, gọi subprocess bằng argv, đặt wall-clock timeout, socket timeout, output size cap và retry policy tường minh.
3. Reserve một lượt trong giới hạn chung 10 lần bắt đầu tải/60 phút ngay trước mỗi lần chạy downloader; retry nào gọi downloader cũng tiêu thụ một lượt.
4. Không tự động tải search result/playlist. Chỉ URL video được user đưa/chọn; lưu consent/provenance và hiện cảnh báo trước enqueue.
5. Bảo vệ mọi request/redirect/DNS/manifest/segment bằng egress control; WebMock/spec chỉ kiểm tra code path, không thay chứng minh mạng runtime an toàn.
6. Cache YouTube API metadata tối đa 30 ngày nếu không refresh; giữ attribution; tách dữ liệu discovery khỏi provenance/metadata file local.
7. Lỗi downloader có hướng dẫn import local; file YouTube Studio/Takeout đi qua local import và không gọi downloader.
