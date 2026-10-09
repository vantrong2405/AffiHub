# Google Drive và Google Sheets — Porting Note

Ngày đối chiếu: 2026-10-09

## Phạm vi

Tài liệu này ghi lại contract đã kiểm chứng cho task 11 của `affihub-mvp-video-workflow`. Đây là note thiết kế/porting, không phải bằng chứng OAuth, upload hay đồng bộ đã chạy với tài khoản Google thật.

Rails database tiếp tục là nguồn trạng thái chính. Google là tích hợp tùy chọn; lỗi Drive hoặc Sheets không được khởi chạy lại render hay Publication. Theo OpenSpec hiện hành, Drive upload và Sheets sync là hai side job riêng, có trạng thái và retry riêng. Khi người dùng xác nhận đăng thủ công hoặc lưu lịch auto-publish đã xác nhận, hai nhánh được xếp độc lập với Publication; kết nối Google muộn chỉ backfill project/render mà người dùng chọn.

## Repo tham khảo

Đã đối chiếu `googleapis/google-api-ruby-client` tại commit `0402ef3053bd88046a0423f022a12bf2d15ede22` ngày 2026-10-09:

- [`samples/cli/lib/samples/drive.rb`](https://github.com/googleapis/google-api-ruby-client/blob/0402ef3053bd88046a0423f022a12bf2d15ede22/samples/cli/lib/samples/drive.rb) minh họa khởi tạo Drive service với OAuth credentials và thao tác file qua API client, gồm truy vấn danh sách có query/pagination/fields.
- [`samples/cli/lib/samples/sheets.rb`](https://github.com/googleapis/google-api-ruby-client/blob/0402ef3053bd88046a0423f022a12bf2d15ede22/samples/cli/lib/samples/sheets.rb) minh họa khởi tạo Sheets service và gọi Values API.

Đây là nguồn tham khảo cách dùng client, không phải runtime dependency hay contract thay cho tài liệu API. `affihub/Gemfile` hiện có `googleauth`, chưa khai báo Google API Ruby service client cho Drive/Sheets; việc chọn client/gem cụ thể thuộc task implementation.

## Contract đã kiểm chứng

### Chi phí, quota và lựa chọn rclone

- Google ghi rõ sử dụng Drive API tiêu chuẩn không tính thêm phí. Với project mới theo hạn mức từ 2026-05-01, tài liệu hiện ghi mức daily threshold 400,000,000 quota units; usage dưới ngưỡng không tính thêm và tài khoản không bị billing. Google dự kiến công bố chi tiết phí vượt ngưỡng sau trong năm 2026 và báo trước tối thiểu 90 ngày. AffiHub chọn chỉ dùng quota tiêu chuẩn, không bật Cloud Billing, không yêu cầu payment method, không xin quota trả phí; quota hết thì dừng side job và để người dùng thử lại khi quota khả dụng.
- Tài khoản Google cá nhân có tối đa 15 GB dùng chung cho Drive, Gmail và Photos. Đây là hạn mức storage của tài khoản; nếu đầy, Drive từ chối upload. AffiHub không mua thêm Google One và giữ render local.
- App dùng cá nhân dưới 100 người có thể không qua OAuth verification, nhưng Google vẫn có thể hiện cảnh báo ứng dụng chưa xác minh; điều này không loại bỏ bước tạo OAuth project/client và user consent. OAuth Testing có giới hạn test user và refresh token Drive có thể hết hạn sau 7 ngày.
- Google Workspace API project guide mô tả bật Billing là tùy chọn tùy API/tính năng; Drive API tiêu chuẩn được ghi rõ là không tính thêm phí. AffiHub chỉ bật Drive/Sheets API, không link Cloud Billing project và không cấu hình payment method. Trước khi dùng tài khoản thật, chỉ tiếp tục nếu Cloud Console cho tạo OAuth client và bật Drive API khi Billing vẫn tắt; nếu Google thay đổi điều kiện này thì giữ tích hợp disabled, không gắn thẻ.
- `rclone` là CLI miễn phí có thể copy file lên Drive bằng OAuth, nhưng không bỏ qua consent. Tài liệu rclone thông báo shared Google Drive client ID sẽ ngừng trong năm 2026 và khuyến nghị/từ nay yêu cầu client ID riêng. Vì AffiHub cần lưu state, `appProperties`, resumable session và reconcile trong Rails, task implementation dùng Drive API trực tiếp; không chạy rclone như subprocess runtime.

Nguồn: [Drive API limits and pricing](https://developers.google.com/workspace/drive/api/guides/limits), [Google Workspace project setup](https://developers.google.com/workspace/guides/create-project), [Drive API errors](https://developers.google.com/workspace/drive/api/guides/handle-errors), [Google OAuth verification exceptions](https://support.google.com/cloud/answer/13464323?hl=en), [Google account storage](https://support.google.com/drive/answer/9312312?hl=en), [rclone Drive backend](https://rclone.org/drive/).

### OAuth và scope

- Ứng dụng web cần yêu cầu `access_type=offline` để Google có thể cấp refresh token. Không được giả định response nào cũng có refresh token; phải giữ refresh token hiện có khi response refresh không gửi token mới. Token phải được lưu ở nơi bền vững và bảo vệ; AffiHub yêu cầu mã hóa credential trong database và không ghi token vào log.
- OAuth consent screen ở trạng thái `Testing` cho external user làm refresh token hết hạn sau 7 ngày nếu scope không chỉ gồm danh tính cơ bản. Khi token bị thu hồi/hết hạn, đánh dấu cần kết nối lại và giữ nguyên kết quả local.
- Google khuyến nghị scope hẹp `drive.file`; scope này cho phép thao tác trên file người dùng mở/chia sẻ với app hoặc chọn qua Google Picker, không phải liệt kê tùy ý toàn bộ Drive. Sheets Values `append`/`update` cũng chấp nhận `drive.file`; Sheets API liệt kê scope này là lựa chọn được khuyến nghị, còn `spreadsheets` rộng hơn và nhạy cảm. Vì cùng scope có thể phục vụ cả hai API trên các file được chọn, bật/tắt Drive và Sheets vẫn phải điều khiển side job riêng; consent scope không đồng nghĩa người dùng đã bật cả hai luồng. Nếu flow chọn folder/spreadsheet hiện có cần Picker thì task UI phải dùng Picker hoặc giải thích rõ quyền khác; không tự xin scope `drive` rộng.
- OpenSpec yêu cầu chỉ xin quyền cần cho dịch vụ người dùng bật. Khi một scope hẹp dùng chung được cả hai dịch vụ, chỉ yêu cầu scope đó cho file đã chọn và không chạy side job dịch vụ chưa bật.

Nguồn: [OAuth web server flow](https://developers.google.com/identity/protocols/oauth2/web-server), [OAuth token expiry](https://developers.google.com/identity/protocols/oauth2#expiration), [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth), [Sheets scopes](https://developers.google.com/workspace/sheets/api/scopes), [Sheets append authorization scopes](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets.values/append), [Sheets update authorization scopes](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets.values/update).

### Drive folder, metadata và resumable upload

- Tạo folder bằng Drive API metadata; upload render MP4 với `uploadType=resumable`. Google khuyến nghị resumable cho file trên 5 MB hoặc kết nối dễ gián đoạn, và nói phương thức này phù hợp với đa số ứng dụng.
- Request khởi tạo thành công trả `Location` chứa session URI. URI hết hạn sau một tuần. Các chunk phải là bội số 256 KiB, ngoại trừ chunk cuối. Gửi chunk tiếp theo theo `Range` server xác nhận; `308 Resume Incomplete` cho biết còn dữ liệu, `200`/`201` xác nhận upload hoàn tất.
- Nếu request bị ngắt hoặc nhận `503`, hỏi trạng thái bằng PUT rỗng cùng `Content-Range`; tiếp tục từ byte server báo. `404` khi hỏi session có nghĩa session hết hạn. Không khởi tạo upload mới chỉ vì response bị mất; trước tiên reconcile trạng thái upload và tìm file theo metadata.
- `appProperties` là metadata riêng của ứng dụng, có thể tìm bằng query `appProperties has {key=... and value=...}` khi request đã OAuth. Google giới hạn 30 private properties mỗi app trên một file và tối đa 124 byte UTF-8 cho tổng key + value. Giá trị này là khóa dò, không phải unique constraint của Drive; AffiHub vẫn phải serialize tạo folder/file theo khóa ổn định.
- Giữ folder/file private và để quyền kế thừa từ folder cha; không tạo permission public. Drive có thể trả `permissionDetails.inherited` và `inheritedFrom` để xác nhận nguồn quyền.
- Session URI cho phép tiếp tục upload nên theo quyết định bảo mật của AffiHub phải được đối xử như secret: lưu được mã hóa/che chắn, không đưa vào exception, log hay response UI. Đây là biện pháp bảo mật của ứng dụng dựa trên khả năng tiếp tục phiên, không phải tuyên bố Google gọi URI là OAuth token.

Nguồn: [Drive upload protocol](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [Drive custom properties](https://developers.google.com/workspace/drive/api/guides/properties), [Drive search](https://developers.google.com/workspace/drive/api/guides/search-files), [Drive sharing and inherited permissions](https://developers.google.com/workspace/drive/api/guides/manage-sharing).

### Sheets Values API và `RAW`

- `spreadsheets.values.append` tìm logical table trong A1 range rồi thêm sau hàng cuối của table; nó không nhận khóa unique và không tự làm upsert. `spreadsheets.values.update` ghi vào range A1 cụ thể, phù hợp khi đã biết số hàng cần cập nhật.
- Cả hai thao tác yêu cầu `valueInputOption`. OpenSpec chọn `RAW`: giá trị được lưu nguyên dạng, không bị diễn giải thành công thức, ngày hoặc số theo quy tắc nhập liệu của UI.
- Sheets API không cung cấp transaction/unique constraint cho `sheet_row_key`. Đây là kết luận từ ngữ nghĩa `append`/`update`, không phải cam kết riêng của Google về mọi API. Rails phải serialize upsert theo khóa `project + render version + destination`, dò hàng trước khi append, update hàng đã biết, và đọc lại theo khóa sau timeout trước khi quyết định retry. Nếu vẫn không thể kết luận append đã xảy ra hay chưa, giữ `OutcomeUnknown`; không append lại một cách mù quáng.
- Sheets quota/time-based errors nên dùng truncated exponential backoff có giới hạn retry. `429` là quota response đã được tài liệu hóa. Retry policy và ngưỡng nằm trong YAML được đọc bằng `Rails.application.config_for`; không retry lỗi quyền/validation như lỗi transient.

Nguồn: [Sheets append](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets.values/append), [Sheets update](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets.values/update), [`ValueInputOption`](https://developers.google.com/workspace/sheets/api/reference/rest/v4/ValueInputOption), [Sheets usage limits and backoff](https://developers.google.com/workspace/sheets/api/limits).

### Retry và xử lý kết quả chưa rõ

- Với Drive, tài liệu khuyến nghị exponential backoff cho quota/rate limit và các lỗi server `500`, `502`, `503`, `504`. Với resumable upload, resume/query tiến độ trước khi gửi lại phần dữ liệu; không biến mọi lỗi thành retry tạo file mới.
- Với Sheets, áp dụng truncated exponential backoff cho lỗi quota có thời gian như `429`. `append` có side effect nên timeout sau request là `OutcomeUnknown`: đọc lại bằng khóa nghiệp vụ trước retry. `update` đến range đã xác định có thể lặp lại an toàn hơn, nhưng vẫn phải tôn trọng quota và trạng thái kết nối.
- Nếu Google trả lỗi xác thực/refresh token không còn hợp lệ, đánh dấu reconnect thay vì retry vòng lặp. Từng nhánh có retry/status riêng; Sheets retry không được gọi lại Drive hoặc publisher.
- Các số lần retry, backoff, lease/concurrency limit là cấu hình AffiHub, cần YAML/`config_for`; nguồn Google xác nhận chiến lược nhưng không quyết định giá trị vận hành của sản phẩm.

Nguồn: [Drive error handling](https://developers.google.com/workspace/drive/api/guides/handle-errors), [Sheets usage limits](https://developers.google.com/workspace/sheets/api/limits), [OAuth token response and storage](https://developers.google.com/identity/protocols/oauth2/web-server).

## Ánh xạ sang AffiHub

1. **Drive side job:** dùng project/video làm khóa folder ổn định; dùng render version/export làm khóa file. Sau timeout, reconcile `appProperties` và trạng thái resumable trước khi tạo lại. Lưu Drive folder/file ID và URL cùng trạng thái upload trong Rails.
2. **Sheets side job:** upsert một hàng hiện trạng cho project/render/destination, có publication status, `platform_post_id`, permalink, `published_at`, link Drive, lỗi liên quan và thời điểm cập nhật. Các Publication occurrence lặp vẫn được lưu đầy đủ trong Rails; Sheets chỉ phản ánh trạng thái mới nhất của cùng hàng.
3. **Tách lỗi:** Drive success + Sheets failure chỉ retry SheetSync. Drive failure không chặn publish; Sheets failure không gọi publisher. Khi Google chưa kết nối, các workflow video khác tiếp tục.
4. **Concurrency:** thao tác lookup rồi append không nguyên tử ở Google. AffiHub phải khóa/serialize theo `sheet_row_key` trong Rails trước khi lookup/append/update. Cơ chế khóa cụ thể chưa được API Google quyết định.

## Đồng bộ với tài liệu sản phẩm

Mục 4.6 của `affihub/docs/PROJECT_SPEC.md` đã được cập nhật để khớp OpenSpec 08: trigger gồm xác nhận đăng thủ công và lưu lịch auto-publish, row key là project/render/destination, các cột dùng chung `platform_post_id`/permalink và backfill chỉ cho render do người dùng chọn.

Hai side job vẫn độc lập. Nếu SheetSync chạy trước Drive, hàng tạm có thể thiếu link; sau khi Drive upload thành công, AffiHub enqueue SheetSync để cập nhật cùng hàng. Đây là quyết định sản phẩm của AffiHub, không phải bảo đảm thứ tự từ Google API.

## Ranh giới kiểm chứng

Đã kiểm tra nguồn tài liệu chính thức và sample repo nêu trên ngày 2026-10-09. Chưa chạy OAuth, chọn file qua Picker, upload file thật, kiểm tra quyền kế thừa trên Drive hay ghi Sheets bằng tài khoản test. Các bước đó thuộc task implementation/smoke riêng; không đánh dấu hoàn tất chỉ từ note này.
