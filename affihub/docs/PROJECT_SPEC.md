# PROJECT_SPEC — AffiHub: tạo, biên tập và đăng video Facebook

## 1. Mục tiêu sản phẩm

AffiHub là ứng dụng Rails chạy local, giao diện tiếng Việt, giúp chủ dự án đi từ video đầu vào hoặc ý tưởng đến một video đã biên tập, được duyệt và đăng lên Facebook Page.

```text
Video có sẵn / tạo video bằng AI
→ biên tập trên timeline
→ render và xem trước
→ người dùng duyệt
→ đăng lên Facebook Page
→ lưu file lên Google Drive và đồng bộ trạng thái vào Google Sheets
```

Google Drive/Sheets là luồng lưu trữ và theo dõi phụ trợ; lỗi đồng bộ không làm mất bản render hoặc chặn người dùng xem, duyệt và đăng. Database local của AffiHub giữ trạng thái chính.

MVP hỗ trợ một Facebook profile để kết nối và quản lý một hoặc nhiều Page. Mỗi Page có kết quả đăng riêng. Ứng dụng không tự nuôi Page, đăng không cần duyệt, trả lời bình luận hay nhắn tin.

Các thao tác chỉnh sửa phục vụ dựng video và nhận diện nội dung của Page. AffiHub không đảm bảo chỉnh sửa sẽ tránh nhận diện nội dung trùng lặp, liên kết Page/tài khoản hoặc cảnh cáo của nền tảng.

MVP dùng text-to-video rời từng cảnh qua MuAPI (mục 4.3): mỗi cảnh sinh độc lập từ scene prompt dạng text, không có ảnh nhân vật tham chiếu, nên nhân vật/bối cảnh có thể đổi giữa các cảnh. Đồng bộ nhân vật/bối cảnh xuyên nhiều cảnh bằng video model hỗ trợ reference-image (ví dụ Kling multi-reference, Seedance bản reference) là hướng mở rộng sau MVP, xem mục 7 và mục 8.

## 2. Quyết định MVP

| Hạng mục | Chọn cho MVP | Lý do kỹ thuật và trải nghiệm |
|---|---|---|
| Nơi đăng | Facebook Page qua Meta Graph API; không đăng lên profile cá nhân | Có luồng API chính thức cho Page Reels; mỗi lần đăng có thể theo dõi riêng theo Page. |
| Nguồn video | Import file từ máy. Nếu file đang ở nền tảng khác, người dùng tải/xuất bằng công cụ chính thức của nền tảng rồi import file đó. Link nguồn chỉ lưu làm thông tin tham khảo. | Không có một API chính thức dùng chung để tải file video từ YouTube, Facebook, Instagram và TikTok. Extractor có trong repo không chứng minh API hay điều khoản nền tảng cho phép tải tự động. |
| Tạo video AI | MoneyPrinterTurbo (MPT) v1.3.8, pin commit `fafec0fbf3142ad5ad7212c2e17996bf247c360a`; chế độ AI tạo cảnh là luồng chính, stock montage là phương án riêng. | MPT đã có các stage script, scene prompt, TTS, subtitle, render và task status. Không tự dựng lại pipeline từ đầu. |
| AI video | MPT `video_source=muapi`; preset thử đầu tiên là `seedance-lite-t2v` 480p, scene 3–12 giây; lấy báo giá tất cả cảnh trước khi gửi và yêu cầu xác nhận tổng phí. | MPT tạo một clip ngắn cho mỗi scene prompt rồi ghép lại; số cảnh, độ dài, model và độ phân giải làm đổi chi phí. 480p là preset preview tiết kiệm, UI phải hiện độ phân giải nguồn và cho xem báo giá model khác trước khi render final. API MPT không tự chặn chi phí trước khi nhận job. |
| Giọng đọc | Dùng Edge TTS tiếng Việt của MPT cho POC nhanh; cho phép cấu hình Azure Speech TTS v2 khi cần dịch vụ có API/voice catalog chính thức hơn. | Edge TTS có giọng `vi-VN-HoaiMyNeural` và `vi-VN-NamMinhNeural`, nhưng là dịch vụ online không có cam kết ổn định như Azure Speech. |
| Biên tập/render | FFmpeg trong worker riêng; output chuẩn Facebook Reel 9:16 MP4. | FFmpeg đã xử lý tốt trim, crop, scale, blur, brightness, audio, overlay và encode. |
| Đăng | Người dùng xem preview, chọn Page, sửa caption và bấm xác nhận. Không tự đăng. | Tránh nhầm upload xong với đăng thành công; trạng thái cần dựa trên phản hồi và đối soát với Meta. |
| Google | Google Drive + Sheets kết nối tùy chọn; đồng bộ nền và retry riêng. | Không để lỗi Google làm dừng luồng video hoặc làm đăng trùng. |

## 3. Flow tổng quan

### 3.1 Thiết lập lần đầu

```text
Mở AffiHub
  ├─ Dùng thử: mở video mẫu → biên tập → render preview → tải MP4 về máy
  │             (nhãn Demo; không gọi Meta, không tạo bài đăng giả)
  └─ Dùng thật:
       Tạo Facebook Page
       → tạo/configure Meta Developer App và callback local
       → thêm profile dùng app vào app role khi app ở Development mode
       → kết nối Facebook trong AffiHub
       → chọn Page và kiểm tra quyền tạo nội dung
       → (tùy chọn) kết nối Google → chọn Drive folder + spreadsheet/tab
       → (tùy chọn) nhập API key cho LLM/MuAPI/stock footage/Azure TTS
```

### 3.2 Mỗi video

```text
Tạo project
  ├─ Import MP4/MOV từ máy
  │    └─ Nếu video nằm trên nền tảng: mở hướng dẫn tải/xuất chính thức
  │         → tải file về máy → quay lại chọn file
  └─ Tạo bằng AI
       → nhập chủ đề
       → MPT tạo kịch bản tiếng Việt
       → sửa/duyệt kịch bản
       → MPT tạo scene prompts
       → sửa cảnh, số lượng, độ dài
       → xem báo giá MuAPI cho toàn bộ cảnh
       → xác nhận chi phí
       → MPT tạo clip AI, voiceover và phụ đề
                         ↓
                ffprobe kiểm tra file
                         ↓
       Biên tập: cắt / dọc 9:16 / nền khung / sáng / chữ / audio / logo tĩnh
                         ↓
              Render một phiên bản MP4 bất biến
                         ↓
       Kiểm tra thông số Facebook + preview phiên bản sẽ đăng
                         ↓
       Chọn Page(s) + caption riêng từng Page → người dùng xác nhận đăng
                         ↓
       Meta upload → xử lý video → publish → đối soát trạng thái/permalink

       Nhánh phụ không chặn bước chính:
       Render → Drive upload
       Chọn Page → Sheet upsert theo render version + Page
       (nếu lỗi: giữ job để retry; không làm lại render hoặc đăng lại)
```

### 3.3 Ba bước chính trên giao diện

```text
Nguồn video  →  Biên tập & render  →  Duyệt & đăng
                         └────────────→ Drive/Sheets tự đồng bộ nền
```

AI generation là một cách tạo nguồn video và đưa kết quả vào cùng editor, không tạo một quy trình xuất bản riêng. Người dùng chỉ cần theo dõi ba bước chính; trạng thái Drive/Sheets nằm trong panel đồng bộ riêng.

## 4. Flow người dùng chi tiết

### 4.1 Kết nối Facebook Page

1. Nếu chưa có Page, AffiHub mở hướng dẫn tạo Page trên Facebook. Người dùng quay lại AffiHub sau khi tạo xong.
2. Người quản lý tạo Meta Developer App, cấu hình Facebook Login/OAuth callback theo địa chỉ local của app và để app ở Development mode cho POC.
3. Thêm Facebook profile sẽ dùng AffiHub vào app role Developer/Tester. Profile đó cần có quyền quản lý Page và tạo nội dung trên Page.
4. Người dùng bấm **Kết nối Facebook**, đăng nhập và cấp các quyền Page mà Meta yêu cầu cho endpoint đăng Reels.
5. AffiHub liệt kê Page được cấp quyền, hiển thị tên/Page ID/task được trả về, rồi cho chọn Page mặc định.
6. Nút **Kiểm tra kết nối** gọi API đọc lại danh sách Page và xác nhận Page có quyền tạo nội dung. Nếu không đạt, UI nêu rõ profile, Page role hoặc quyền OAuth cần sửa.
7. Trong Development mode, chỉ app role/tester và tài sản được cấp cho họ có thể dùng để thử. Muốn cho người ngoài app role sử dụng, cần kiểm tra access level, Advanced Access và review của Meta theo quyền/API hiện hành.

Một Facebook profile có thể quản lý nhiều Page. MVP chưa hỗ trợ đăng nhập nhiều Facebook profile. Người dùng được chọn một hoặc nhiều Page ở bước duyệt; mỗi Page là một publication riêng.

**Tham khảo:** [Meta Reels Publishing API](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api), [Meta Graph API access levels](https://developers.facebook.com/docs/graph-api/overview/access-levels/), [Postiz Facebook provider](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts). Postiz dùng để đối chiếu provider boundary và xử lý lỗi; quyền/API version lấy từ tài liệu Meta hiện hành.

### 4.2 Import video có sẵn

1. Người dùng bấm **Import video** rồi kéo thả file hoặc chọn file từ máy.
2. Có thể nhập link bài/video gốc để lưu `source_url`, nhưng link không tự tải media.
3. Nếu file ở nền tảng khác, AffiHub hiển thị hướng dẫn mở đúng công cụ owner export/download của nền tảng, lưu file về máy rồi quay lại import.
4. Worker lưu file nguồn riêng, chạy `ffprobe`, hiển thị thời lượng, kích thước, codec, frame rate và audio track.
5. Nếu file không đọc được hoặc vượt giới hạn cấu hình, project vẫn được giữ; UI nêu định dạng/lý do và hướng dẫn chọn lại hoặc chuyển định dạng.

**Đường lấy file theo nền tảng:**

| Nguồn | Cách đưa file vào MVP | Giới hạn API hiện biết |
|---|---|---|
| YouTube | Tải video do chính người dùng upload qua YouTube Studio hoặc Google Takeout, sau đó import. Ưu tiên file gốc nếu còn vì Studio có thể chỉ xuất 720p/360p. | YouTube Data API có metadata và upload/update/delete; không có endpoint trả file video. [Hướng dẫn tải video đã upload](https://support.google.com/youtube/answer/56100), [Video resource API](https://developers.google.com/youtube/v3/docs/videos) |
| Facebook Page/Reels | Import file gốc hoặc bản người dùng xuất/tải từ phần quản lý Page. [Tải bản sao Page](https://www.facebook.com/help/1206330326045914) | Graph API v26 `/{page-id}/videos` không hỗ trợ đọc danh sách. Video node có trường `source`, nhưng cần xác định video ID qua một đường đọc được hỗ trợ trước; chưa coi đây là connector MVP. [Page Videos v26](https://developers.facebook.com/docs/graph-api/reference/page/videos/), [Video node v26](https://developers.facebook.com/docs/graph-api/reference/video/) |
| Instagram Reels | Import file gốc hoặc bản người dùng xuất từ [Meta Accounts Center](https://about.fb.com/news/2023/10/manage-your-information-across-apps/). | API đọc media có thể trả `media_url` cho tài khoản Professional, nhưng consumer account không được hỗ trợ; cần quyền/review và URL media không bảo đảm cho mọi video. Để ngoài MVP. [Instagram API](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/), [IG User media](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media/) |
| TikTok | Dùng [Save video](https://support.tiktok.com/en/using-tiktok/exploring-videos/video-downloads) hoặc yêu cầu bản dữ liệu từ TikTok, sau đó import file. | Display API trả metadata/embed, không trả file. Data Portability có thể xuất bài nhưng hiện chỉ cho người dùng EEA/UK; app cần Data Portability approval, Login Kit approval và app review nên không dùng cho tài khoản ở Việt Nam. [Display API](https://developers.tiktok.com/docs/en/display-api-overview), [Data Portability availability](https://developers.tiktok.com/products/data-portability-api), [Approval flow](https://developers.tiktok.com/docs/en/data-portability-api-get-started) |

**Quyết định downloader:** không dùng `yt-dlp`, Playwright hay fork downloader để tải trực tiếp URL mạng xã hội trong MVP. Các repo có extractor không tạo quyền/API ổn định; một lần chạy thành công không bảo đảm lần sau hoặc nguồn khác chạy được. `yt-dlp` được giữ trong danh sách đánh giá, không nằm trong kiến trúc chạy. Connector tự động đầu tiên có thể thử sau MVP là video do Page người dùng quản lý: tìm attachment/video ID qua route được Meta cho phép rồi đọc `Video.source`. Không triển khai trước khi spike chứng minh trọn luồng; Graph API v26 hiện không hỗ trợ đọc Page Videos edge nên không hứa duyệt/tải toàn bộ thư viện Page.

### 4.3 Tạo video bằng AI

AffiHub tích hợp pipeline có sẵn của MoneyPrinterTurbo (MPT), không tự dựng lại stage script/scene/TTS/subtitle/render.

1. Người dùng chọn **Tạo bằng AI**, nhập chủ đề, ngôn ngữ, tone và thời lượng mục tiêu. Mặc định tạo 5 cảnh, mỗi cảnh 6 giây (khoảng 30 giây tổng); người dùng sửa số cảnh và độ dài trước khi tạo video. Clip tạo bằng preset `seedance-lite-t2v` có độ dài 3–12 giây mỗi cảnh.
2. Trước mỗi yêu cầu script/scene prompts, AffiHub hiển thị provider/model LLM đã cấu hình và mức phí ước tính nếu provider cung cấp; chỉ gửi request sau thao tác **Tạo kịch bản** hoặc **Tạo gợi ý cảnh** của người dùng.
3. AffiHub gọi MPT `POST /api/v1/scripts`. Người dùng xem và sửa kịch bản. Không chuyển sang tạo cảnh nếu kịch bản chưa được duyệt.
4. AffiHub gọi MPT `POST /api/v1/terms` để tạo scene prompts. Người dùng chỉnh prompt từng cảnh và số cảnh trước khi gọi dịch vụ video.
5. Chế độ chính là **AI tạo cảnh**: AffiHub lấy báo giá MuAPI cho model, từng prompt, thời lượng và độ phân giải; hiển thị tổng tiền/đơn vị tiền tệ/số clip và độ phân giải nguồn. Chỉ gọi MPT `POST /api/v1/videos` với `video_source=muapi` sau khi người dùng xác nhận.
6. MPT gửi tác vụ bất đồng bộ cho từng cảnh, ghép các clip thành timeline, tạo voiceover và subtitle, rồi render preview MP4. Clip cảnh ngắn được ghép nối; UI không hứa giữ nhân vật hoặc chuyển động liên tục giữa các cảnh, cũng không mô tả upscale thành chi tiết native của video độ phân giải thấp.
7. **AI script + stock montage** là lựa chọn riêng để giảm chi phí video generation; dùng footage stock theo API cấu hình MPT. UI ghi rõ đây là montage bằng footage stock, không gọi là clip text-to-video.
8. MPT task ID và trạng thái được lưu ở AffiHub. Khi timeout sau khi gửi job đến MuAPI, chuyển sang **Chưa rõ kết quả**, kiểm tra task/provider ID trước khi thử lại để không tạo job có thể bị tính phí lần hai.

**Repo/version:** [MoneyPrinterTurbo v1.3.8 release](https://github.com/harry0703/MoneyPrinterTurbo/releases/tag/v1.3.8), pinned commit `fafec0fbf3142ad5ad7212c2e17996bf247c360a`, license MIT ([license file](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/LICENSE)). File để port: [script/terms controller](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/app/controllers/v1/llm.py), [video controller](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/app/controllers/v1/video.py), [request schema](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/app/models/schema.py), [MuAPI service](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/app/services/muapi.py), [config](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/config.example.toml), [voice list](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/docs/voice-list.txt). MPT chạy trong Python worker riêng; không mang WebUI của repo vào Rails. Không dùng tag `latest`.

**Worker an toàn:** MPT config mặc định có thể bind `0.0.0.0` và chạy không cần API key nếu key để trống. AffiHub phải override bind về `127.0.0.1`, đặt API key bắt buộc, dùng thư mục job tách biệt và pin commit/image digest. Không đưa key MPT/MuAPI/LLM ra trình duyệt.

### 4.4 Biên tập và render

Editor dùng cùng một timeline cho file import và video AI:

- Cắt điểm đầu/cuối; đổi tỷ lệ/khung hình; fit hoặc crop dọc 9:16.
- **Nền khung dọc:** phóng to và làm mờ một bản sao video phía sau, hoặc chọn màu/ảnh/video làm nền phía sau toàn khung nguồn.
- Chỉnh brightness/contrast; chỉnh âm lượng, tắt audio nguồn hoặc thêm voiceover/subtitle.
- Thêm text, caption, logo overlay, intro/outro.
- **Gỡ logo cố định:** người dùng chọn một vùng hình chữ nhật và xem preview. Dùng FFmpeg `delogo` trước; vùng nội suy có thể để lại dấu. Lưu source nguyên bản để hoàn tác.
- Logo chuyển động hoặc cần tái tạo nền hoàn hảo không được cam kết trong MVP. Không nhầm “nền khung dọc” với tách người khỏi phông quay ban đầu; thay phông gốc cần model video matting và để sau benchmark.

Render tạo `RenderVersion` bất biến. Thay filter hoặc render lại tạo version mới; không ghi đè file đã được đăng hoặc đang được đồng bộ.

**Tham khảo:** [FFmpeg source](https://github.com/FFmpeg/FFmpeg), [FFmpeg filters](https://ffmpeg.org/ffmpeg-filters.html), [RobustVideoMatting](https://github.com/PeterL1n/RobustVideoMatting) chỉ để benchmark tách người về sau. [ProPainter](https://github.com/sczhou/ProPainter) có license non-commercial nên không chọn làm dependency của sản phẩm.

### 4.5 Duyệt và đăng Facebook Reel

Màn hình review hiển thị video preview của đúng `render_version`, caption từng Page, danh sách Page đích, trạng thái Drive/Sheet và thông số preflight. Người dùng bấm **Đăng lên các Page đã chọn** để xác nhận một lần; kết quả vẫn được theo dõi riêng từng Page.

Quy trình Meta Reels:

```text
Tạo upload session
→ upload file local theo giao thức Meta
→ hỏi trạng thái xử lý khi cần
→ gọi finish/publish
→ poll/đối soát trạng thái cuối
→ lưu video/post ID, permalink, published_at
```

Không coi `upload success` hoặc response `success: true` ban đầu là đã đăng. Chỉ ghi **Đã đăng** khi API xác nhận trạng thái cuối; nếu request timeout hoặc kết quả không rõ, đánh dấu **Cần kiểm tra**, truy vấn Meta/Page trước khi cho retry.

MVP export profile: MP4, H.264, AAC, 1080×1920 (9:16), 30 fps, mặc định 30 giây. Meta collection đang mô tả Reels 9:16, tối thiểu 540×960, 23 fps và duration 4–60 giây. Tại bước cấu hình API, ghi rõ Graph API version đã chọn và kiểm lại yêu cầu theo version đó; preflight phải dùng cấu hình versioned, không nhúng giới hạn thay đổi vào nhiều chỗ.

**Facebook không yêu cầu file Markdown để đăng Reel.** API nhận media video và mô tả/caption dạng text. `.md` dùng để viết tài liệu dự án, không phải định dạng upload video.

Trong Demo không có credential, dùng video/Page mẫu được gắn nhãn **Demo**, không gọi Meta và không tạo post ID giả. Demo vẫn cho import/biên tập/render/tải MP4. Muốn kiểm chứng đăng thật phải cấu hình Meta app role và Page thật theo mục 4.1.

**Tham khảo:** [Meta Reels Publishing API collection](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api), [Postiz Facebook provider](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts). Collection minh họa create/upload/status/publish; API version và quyền phải được kiểm chứng tại thời điểm implement.

### 4.6 Google Drive và Sheets

Kết nối Google là tùy chọn. Nếu bỏ qua, video vẫn xử lý/duyệt/đăng và được giữ local; Settings có thể kết nối sau. Khi kết nối sau, người dùng chọn project/render cụ thể để đồng bộ, app không tự đẩy toàn bộ thư viện.

1. Người dùng bấm **Kết nối Google** bằng OAuth, chọn Drive folder và spreadsheet/tab hoặc tạo bảng theo mẫu AffiHub.
2. AffiHub tạo mapping cột một lần; cột bắt buộc: `project_id`, `render_version`, `page_id`, `drive_file_id`, `drive_url`, `publish_status`, `facebook_post_id`, `facebook_permalink`, `last_error`, `updated_at`.
3. Sau render, Drive worker upload MP4 resumable. Ghi idempotency key trong Drive `appProperties`; timeout thì tìm lại file theo key trước khi upload lần nữa.
4. Sau khi có `Publication` cho một render/Page, Sheet worker tìm `sheet_row_key`; nếu có thì update hàng đó, nếu chưa có thì append. Key gồm `project_id + render_version + page_id`.
5. Mỗi lần render mới có hàng mới. Không đổi hàng của render cũ để trỏ sang file mới vì sẽ làm sai permalink/trạng thái bài đã đăng.
6. Google job chạy độc lập. Lỗi Drive không ngăn review; lỗi Sheet sau khi Drive thành công chỉ retry Sheet. Chỉ báo đồng bộ xong sau khi API trả xác nhận.
7. Ghi Sheet với `valueInputOption=RAW`; giữ quyền Drive riêng tư theo quyền folder, không tự chuyển file thành public.

Sheets không cung cấp transaction hay unique constraint trên một cột. Rails database giữ khóa dòng và số hàng; worker serialize upsert theo `sheet_row_key`, dò key trước khi append để giảm trùng khi request timeout. App hiển thị nhãn dễ hiểu như **Drive chưa lưu**, **Sheet chưa đồng bộ**, **Đã đồng bộ**; mã lỗi kỹ thuật để trong log.

Google OAuth consent screen ở Testing có thể làm refresh token hết hạn sau 7 ngày. Bản local POC hiển thị nút kết nối lại và báo trạng thái hết hạn; trước khi chạy dài hạn không giám sát, cần hoàn thiện trạng thái consent/verification phù hợp.

**Tham khảo:** [Google API Ruby Client](https://github.com/googleapis/google-api-ruby-client), [Drive resumable upload](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [Drive `appProperties`](https://developers.google.com/workspace/drive/api/guides/properties), [Google Picker](https://developers.google.com/workspace/drive/picker/guides/web-picker), [Sheets values API](https://developers.google.com/workspace/sheets/api/guides/values), [OAuth best practices](https://developers.google.com/identity/protocols/oauth2/resources/best-practices), [refresh token expiry](https://developers.google.com/identity/protocols/oauth2#expiration).

## 5. Trạng thái và xử lý lỗi

### 5.1 Video project

```text
Draft
  ├─ Importing → Editing
  └─ GeneratingScript → ScriptReview → GeneratingScenePrompts
       ├─ CostReview → GeneratingScenes → Assembling
       └─ FetchingStockFootage → Assembling
                                  ↓
Editing → Rendering → Preflight → ReadyForReview
```

Lỗi ở mỗi bước lưu provider, stage, thông báo và external task ID. Retry chỉ stage đó. Với paid API có thể đã nhận job, chuyển `OutcomeUnknown`, reconcile theo provider task ID rồi mới retry.

### 5.2 Publication theo Page

```text
Draft → Approved → Uploading → Processing → Published
                                  ↘ Failed (đã biết chắc)
                                  ↘ OutcomeUnknown (cần đối soát)
```

`Publication` tham chiếu duy nhất một `RenderVersion` bất biến và một Page. Sheet retry không gọi lại publisher. Publish retry không upload lại hay tạo post mới trước khi tra trạng thái lần trước.

### 5.3 Đồng bộ Google

```text
Drive: Pending → Uploading → Saved
                    ↘ Failed/Unknown → tìm appProperties rồi retry

Sheet: Pending → Synced
                   ↘ Failed/Unknown → tìm sheet_row_key rồi update cùng hàng
```

## 6. Thiết kế kỹ thuật

```text
Rails UI/API (tiếng Việt)
  ├─ Meta OAuth + Page discovery/permission preflight
  ├─ Models: VideoProject, SourceAsset, RenderVersion, TargetPage,
  │          Publication, DriveExport, SheetSync
  └─ Solid Queue
       ├─ Import worker: local file → ffprobe
       ├─ AI worker: MPT pinned release → LLM / MuAPI / TTS / subtitle
       ├─ Media worker: FFmpeg filters + encode
       ├─ Meta publisher: create → upload → process → publish → reconcile
       └─ Google sync workers: Drive resumable upload + Sheets upsert
```

- Rails database là nguồn sự thật; Google Sheets chỉ là bản theo dõi.
- Video, tải file, AI generation và render không chạy trong request web. Worker có giới hạn dung lượng, thời gian, CPU/RAM, cancellation và thư mục theo job.
- File media là input không tin cậy: xác minh magic bytes/MIME, dùng `ffprobe`, không đưa path người dùng vào shell string; worker nhận arguments tách biệt.
- OAuth dùng `state`, PKCE khi provider hỗ trợ, callback allowlist và quyền tối thiểu cần cho Page/Drive/Sheets; không ghi access token, refresh token hoặc upload URL có chữ ký vào log.
- Lưu source và render riêng. `RenderVersion` không sửa sau khi tạo; mọi Publication và Drive export giữ đúng ID/version.
- Access/refresh token Meta/Google và API keys LLM/MuAPI/TTS mã hóa khi lưu; không log token, URL upload có chữ ký hoặc nội dung secret.
- MPT là dịch vụ local riêng, bind loopback, API key bắt buộc, version/image digest được pin. Không công khai port ra LAN/Internet. Chạy MPT như một Docker service riêng (khớp Kamal/Docker đã dùng để deploy AffiHub), image digest pin trong `docker-compose.yml`; dev khởi động bằng `docker compose up -d mpt` trước `bin/dev`. AffiHub kiểm tra health-check của port loopback khi boot và hiện banner nếu worker chưa chạy, không chỉ báo lỗi khi gọi job thất bại.
- MPT cần Python 3.11+; README upstream ghi tối thiểu 4 CPU core/4 GB RAM và khuyến nghị 6–8 core/8 GB. Tạo clip qua cloud API không cần GPU; local Whisper/batch render có thể cần thêm tài nguyên. Gói MPT trong worker/runtime riêng, không cài dependency Python vào Rails.
- App local phải báo khi worker chưa chạy hoặc bị dừng; giữ task ID/trạng thái qua lần restart và reconcile job provider trước retry. Không xóa thư mục job đang xử lý khi app khởi động lại.
- Mọi thao tác retry/claim trạng thái (VideoProject stage, Publication, DriveExport/SheetSync) dùng cùng một pattern: `update_all` có điều kiện `WHERE status = <trạng thái nguồn>` và kiểm tra số dòng bị ảnh hưởng trước khi submit job mới, không đọc-rồi-ghi. Áp dụng thống nhất cho cả ba state machine để tránh double-submit khi người dùng bấm Retry nhiều lần hoặc hai worker nhận cùng job.
- Meta API version, MPT commit, provider/model ID, FFmpeg build và preset encode được ghi trong cấu hình/deployment để tái hiện lỗi.
- Caption và metadata platform là text thuần. Markdown chỉ dùng cho tài liệu dự án.

## 7. Ranh giới MVP và việc để sau

### Có trong MVP

- Local app và hướng dẫn tiếng Việt.
- Import video file, lưu link nguồn tùy chọn, ffprobe và hiển thị lỗi đọc file.
- MPT pipeline tạo script, scene prompts và clip AI; có báo giá + xác nhận trước tác vụ trả phí.
- TTS tiếng Việt, subtitle, editor FFmpeg, preview và render MP4 dọc.
- Cắt, crop/fit, nền mờ/nền khung, brightness, audio, text/overlay và gỡ logo cố định có preview/undo.
- Kết nối một Facebook profile, chọn một hoặc nhiều Page và đăng sau xác nhận.
- Kết nối Drive/Sheets và đồng bộ bất đồng bộ, có retry theo từng dịch vụ.
- Demo không credential và một lần publish thật lên Page của app-role user để hoàn tất POC.

### Chưa có trong MVP

- Tải tự động trực tiếp từ link social bằng `yt-dlp`, scraping hay browser automation.
- Tìm/crawl video viral, playlist/hàng loạt hoặc tự chọn nội dung.
- Nhiều Facebook profile, tự nuôi Page, tự trả lời comment/nhắn tin, lịch đăng tự chạy hoặc auto-publish.
- Đăng lên TikTok, Instagram hoặc YouTube.
- Tách mọi loại vật thể/thay phông gốc, video inpainting logo chuyển động, cam kết xóa logo sạch ở mọi khung hình.
- Cơ chế né nhận diện nội dung, né liên kết Page hoặc đảm bảo tránh cảnh cáo.
- Đồng bộ nhân vật/bối cảnh xuyên nhiều cảnh bằng video model có reference-image (Kling multi-reference, Seedance bản reference). MVP chỉ dùng text-to-video rời từng cảnh; tính năng này cần spike riêng vì đổi schema request (thêm character reference asset) và chưa xác nhận MPT `muapi.py` hiện tại có hỗ trợ tham số reference-image hay không.

## 8. Repo và tài liệu tham khảo trước khi code

| Subsystem | Repo/tài liệu | Cách dùng | Gate kỹ thuật |
|---|---|---|---|
| AI video pipeline | [MoneyPrinterTurbo v1.3.8](https://github.com/harry0703/MoneyPrinterTurbo/tree/v1.3.8), commit `fafec0fbf3142ad5ad7212c2e17996bf247c360a`, MIT | Dùng API script/terms/video, async task, TTS/subtitle/render; chạy Python worker tách Rails | Port đúng API schema/status/error; khóa API vào loopback; test MuAPI quote và trạng thái timeout trước khi bật paid scenes |
| AI scene generation | [MPT MuAPI adapter](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/app/services/muapi.py), [MuAPI pricing](https://muapi.ai/docs/pricing) | Tạo từng clip theo scene prompt; AffiHub lấy tổng estimate trước rồi mới gọi MPT | Giá/model/thời lượng/độ phân giải có thể đổi; không retry mù sau timeout; nếu MuAPI/MPT không trả breakdown giá đủ rõ cho estimate, AffiHub tự tính từ bảng giá MuAPI public thay vì phụ thuộc response của MPT |
| AI scene generation (mở rộng sau MVP) | [MuAPI model catalog](https://muapi.ai/docs/pricing), Kling/Seedance reference-image docs trên MuAPI | Đồng bộ nhân vật/bối cảnh xuyên cảnh bằng model hỗ trợ reference-image, thay cho text-to-video thuần | Xác nhận MPT `muapi.py` có hỗ trợ tham số reference-image trước khi hứa tính năng này ở bất kỳ change nào; đổi schema request nếu cần thêm character reference asset |
| Social URL extractors | [yt-dlp](https://github.com/yt-dlp/yt-dlp), [supported sites](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md) | Đánh giá khả năng kỹ thuật và độ biến động; không tích hợp thành downloader social của MVP | Site extractor đổi liên tục; không thay thế API permission hoặc owner export; không chọn Playwright để mô phỏng tải trên web |
| Edit/render | [FFmpeg](https://github.com/FFmpeg/FFmpeg), [filter docs](https://ffmpeg.org/ffmpeg-filters.html) | Dùng FFmpeg filters cho crop/blur/brightness/audio/delogo/encode | Chốt FFmpeg build/license và kiểm tra chất lượng file mẫu; delogo chỉ hợp vùng tĩnh |
| Facebook Page publish | [Meta Reels API collection](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api), [Postiz provider](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts) | Dùng API Meta làm contract; đối chiếu Postiz về tách provider, status và error mapping | Ghi Graph API version, Page role/permissions, app role/review và thử trên Page thật |
| Drive/Sheets | [Google API Ruby Client](https://github.com/googleapis/google-api-ruby-client), [Drive uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [Sheets values](https://developers.google.com/workspace/sheets/api/guides/values) | Dùng client/API chính thức, resumable upload, update theo khóa | OAuth consent/scope, refresh expiry, Drive idempotency, Sheets concurrent upsert |

Trước khi implement subsystem, tạo `docs/reference-analysis/<subsystem>.md` với commit/version, file source đã đọc, API contract, status/error/retry, license, phần tái sử dụng, phần loại bỏ và cách kiểm chứng trong AffiHub. Không chọn repo chỉ dựa trên lượt star hoặc README.

## 9. Điểm mắc cần khóa trước khi triển khai

| Rủi ro/stuck point | Cách xử lý trong spec |
|---|---|
| Nền tảng không có API tải video thống nhất | Local file là đường vào MVP; URL lưu làm nguồn tham khảo; dùng owner export/download rồi import. Social connector riêng chỉ thêm sau proof bằng API/permission chính thức. |
| Meta app chưa được duyệt hoặc profile chưa có Page task | Dùng app role/tester + Page test để POC; checklist setup và nút kiểm tra quyền; người ngoài app role cần access/review phù hợp. |
| Không có credential nên demo không thể chọn Page thật | Demo tập trung import/edit/render và tải MP4; đăng thật tách riêng, chỉ bật khi Meta connection preflight pass. |
| MPT dùng stock footage theo mặc định | UI tách rõ AI tạo cảnh bằng `muapi` và AI script + stock montage; không ghi stock montage là text-to-video. |
| Scene AI có phí theo prompt | Estimate đầy đủ trước video job; người dùng xác nhận; lưu model/cost/job ID; timeout thì reconcile trước retry. |
| MPT endpoint mở mạng hoặc không có auth mặc định | Override loopback + API key; pin release/commit/image; secrets không gửi client. |
| Google/Sheet lỗi | Lưu trạng thái local; đồng bộ sau; retry riêng Drive hoặc Sheet theo idempotency key. |
| Render mới làm sai trạng thái post cũ | Publication gắn với render version bất biến; mỗi version/Page có row key riêng. |
| Nhiều Page hoặc video biến thể dễ lẫn | Mỗi Page có Publication, caption, lỗi và permalink riêng; review hiển thị danh sách trước khi xác nhận. |
| Reels bị từ chối do format | Preflight file và API version trước review; output profile rõ ràng, lỗi có hành động sửa. |
| Google Testing token hết hạn | Báo kết nối lại; không báo đồng bộ thành công giả. |

## 10. Thứ tự triển khai

1. Đọc Rails code và domain hiện có; viết Porting Note cho MPT, Meta Reels, FFmpeg và Google APIs trước khi làm subsystem.
2. Làm spike Meta sớm: cấu hình app role/Page test, upload một MP4 tối giản, poll processing, publish thật, lưu post ID/permalink; xác định API version và quyền thực tế. Trong cùng spike, thử route lấy `Video.source` cho một video thuộc Page được quản lý; chỉ thêm connector nếu đọc được ID, lấy file và kiểm chứng quyền theo tài liệu hiện hành.
3. Làm local video slice: import file → ffprobe → FFmpeg crop/blur/brightness/delogo → render/preview/tải file.
4. Tích hợp MPT pinned commit: script → user review → terms → MuAPI quote → confirm → generation → poll → preview. Chạy ít nhất một file tiếng Việt và ghi chi phí/thời gian.
5. Hoàn thiện Meta publisher trong Rails theo API contract đã spike; chặn publish nếu Page preflight hoặc file preflight chưa đạt.
6. Thêm Drive/Sheets side jobs; kiểm tra retry riêng, timeout reconciliation và khóa chống tạo hàng/file trùng.
7. Ghép e2e: source/AI → edit → render → preflight → review → Facebook publish; xác minh Drive/Sheet được sync độc lập.

## 11. Điều kiện nghiệm thu MVP

- Từ giao diện tiếng Việt, người dùng có thể dùng Demo để import video, chỉnh, render preview và tải MP4 mà không cần credential ngoài.
- Có thể tạo project từ file; có thể lưu source URL nhưng paste link không tự kích hoạt downloader social.
- Có thể tạo video AI bằng MPT v1.3.8 pinned commit: script và scene prompts sửa được; trước khi tạo clip AI hiển thị báo giá đầy đủ và cần xác nhận.
- Job MPT lưu external task ID, trạng thái, model và lỗi; timeout không tự gửi lại tác vụ có thể đã tính tiền.
- Editor có trim, vertical crop/fit, nền khung, brightness, text/audio và logo vùng tĩnh preview/undo; file nguồn không bị ghi đè.
- Gỡ logo cố định được nghiệm thu bằng bộ 3 clip mẫu nền tĩnh, review thủ công theo checklist pass/fail (vùng xoá không để lại artifact rõ ở preview); không dùng metric tự động, không cam kết cho nền động/phức tạp.
- Render tạo version mới bất biến; preflight hiển thị thông số và kiểm tra trước khi mở nút publish.
- Meta connection tìm Page người dùng quản lý và kiểm tra task/quyền. Một Page test của app-role user nhận một Reel thật; DB lưu trạng thái cuối, Page, render version, provider ID, permalink và thời điểm.
- `Published` chỉ xuất hiện khi Meta xác nhận trạng thái cuối; trường hợp chưa rõ được đối soát trước retry.
- Google Drive lưu MP4 theo `asset_export_key`; Sheets có một hàng cho mỗi render version/Page theo `sheet_row_key`; timeout/retry không tạo bản trùng trong các kịch bản đã xác định.
- Lỗi Google sync không làm mất project, không chặn review/publish và không gọi lại Facebook publisher.
- Demo không credential luôn được đánh dấu Demo, không gọi Meta và không tạo ID/permalink giả.

## 12. Tài liệu nguồn chính

- **YouTube:** [Owner download trong YouTube Studio/Takeout](https://support.google.com/youtube/answer/56100), [YouTube Data API Videos](https://developers.google.com/youtube/v3/docs/videos), [YouTube API policies](https://developers.google.com/youtube/terms/developer-policies).
- **Facebook/Meta:** [Page Videos v26](https://developers.facebook.com/docs/graph-api/reference/page/videos/), [Video node v26](https://developers.facebook.com/docs/graph-api/reference/video/), [Graph API access levels](https://developers.facebook.com/docs/graph-api/overview/access-levels/), [Meta Reels collection](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api).
- **Instagram:** [Instagram Platform API](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/), [IG User media](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media/).
- **TikTok:** [Display API](https://developers.tiktok.com/docs/en/display-api-overview), [Data Portability regional support](https://developers.tiktok.com/products/data-portability-api), [Data Portability application](https://developers.tiktok.com/docs/en/data-portability-api-get-started), [TikTok video download help](https://support.tiktok.com/en/using-tiktok/exploring-videos/video-downloads).
- **AI video:** [MoneyPrinterTurbo v1.3.8](https://github.com/harry0703/MoneyPrinterTurbo/tree/v1.3.8), [MPT README](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/README-en.md), [MPT voice list](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/docs/voice-list.txt), [MuAPI pricing](https://muapi.ai/docs/pricing), [Azure Vietnamese voices](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=stt).
- **Media:** [FFmpeg filters](https://ffmpeg.org/ffmpeg-filters.html), [FFmpeg licensing](https://ffmpeg.org/legal.html), [RobustVideoMatting](https://github.com/PeterL1n/RobustVideoMatting), [ProPainter](https://github.com/sczhou/ProPainter).
- **Google:** [Drive upload](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [Drive `appProperties`](https://developers.google.com/workspace/drive/api/guides/properties), [Sheets values API](https://developers.google.com/workspace/sheets/api/guides/values), [OAuth best practices](https://developers.google.com/identity/protocols/oauth2/resources/best-practices), [Google API Ruby Client](https://github.com/googleapis/google-api-ruby-client).
