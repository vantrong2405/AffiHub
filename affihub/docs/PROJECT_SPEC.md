# PROJECT_SPEC — AffiHub: tạo, biên tập và tự động đăng video đa nền tảng (Facebook, TikTok, Instagram, YouTube)

## 1. Mục tiêu sản phẩm

AffiHub là ứng dụng Rails chạy local, giao diện tiếng Việt, giúp chủ dự án đi từ nội dung có sẵn/viral hoặc ý tưởng đến một video đã biên tập và đăng tự động lên nhiều nền tảng (Facebook, TikTok, Instagram, YouTube).

```text
Tìm/crawl nội dung viral, import có sẵn, hoặc tạo video bằng AI
→ biên tập trên timeline
→ render và xem trước (hoặc bỏ qua xem trước nếu auto-publish bật)
→ đăng lên Facebook / TikTok / Instagram / YouTube (thủ công hoặc theo lịch tự động)
→ tự trả lời bình luận/tin nhắn theo rule cấu hình (tùy chọn)
→ lưu file lên Google Drive và đồng bộ trạng thái vào Google Sheets
```

Google Drive/Sheets là luồng lưu trữ và theo dõi phụ trợ; lỗi đồng bộ không làm mất bản render hoặc chặn luồng đăng. Database local của AffiHub giữ trạng thái chính.

MVP hỗ trợ nhiều profile/tài khoản trên Facebook, TikTok, Instagram, YouTube, mỗi profile quản lý một hoặc nhiều Page/kênh. Lịch đăng tự động (auto-publish không cần người duyệt từng lần) và tự động trả lời bình luận (không gồm tin nhắn/DM — xem lý do ở mục 4.5.b) theo cấu hình sẵn đều nằm trong MVP khi người dùng bật tính năng này.

**"MVP" ở đây nghĩa là gì, và không nghĩa là gì:** MVP là "code hoàn chỉnh, test được, demo được trên tài khoản test/tài khoản của chính chủ dự án." MVP **không** có nghĩa là "sẵn sàng đăng công khai không giới hạn trên cả 4 nền tảng ngay khi code xong" — TikTok yêu cầu audit riêng (mục 4.1.b, mục 8) có thể mất vài tuần và nằm ngoài kiểm soát của đội code; Facebook/Instagram cần app review của Meta. Điều kiện nghiệm thu (mục 11) tách rõ 2 mức: "hoàn thành kỹ thuật" (code đúng, test pass, chạy được trên tài khoản test/SELF_ONLY) và "sẵn sàng công khai" (phụ thuộc kết quả review của từng nền tảng, không tính vào ngày hoàn thành MVP).

**Rủi ro đã được chủ dự án chấp nhận rõ ràng:** tự động hoá đăng bài hàng loạt, tự trả lời bình luận và crawl nội dung viral đều là hành vi các nền tảng (Facebook/TikTok/Instagram/YouTube) có thể coi là spam/bot và xử lý bằng cách khoá tài khoản, khoá Page hoặc rút quyền API — có thể xảy ra bất kỳ lúc nào, không báo trước, và thường không khôi phục được. AffiHub không có cơ chế né phát hiện; đây là đánh đổi được chủ dự án chủ động chọn, không phải thiếu sót kỹ thuật. Chấp nhận rủi ro không thay thế việc giảm rủi ro bằng số liệu cụ thể — xem giới hạn tốc độ đăng/tải cụ thể ở mục 2 và mục 6.

**Discovery/download phải theo đúng access tier của từng nền tảng.** Instagram có hashtag discovery API cho Professional Account liên kết Page; TikTok Research API chỉ dành cho nhóm nghiên cứu đủ điều kiện và được duyệt. Hai endpoint này không phải quyền crawler mặc định của AffiHub; MVP không tự crawl Instagram/TikTok nếu chưa xác minh account, permission, access tier và mục đích sử dụng. YouTube có `search.list` và `videos.list(chart=mostPopular)` cho discovery chính thức, nhưng YouTube Developer Policies cấm API Client scrape YouTube Applications; nguồn hiện có không xác nhận flow YouTube API → `yt-dlp` phù hợp policy. Tải URL bằng `yt-dlp` vẫn là best-effort theo yêu cầu hiện tại, không phải API tải chính thức; giữ cảnh báo, provenance và fallback file chủ sở hữu tự xuất. Xem [Porting Note](reference-analysis/yt-dlp-youtube-discovery.md).

Các thao tác chỉnh sửa phục vụ dựng video và nhận diện nội dung của Page/kênh. AffiHub không đảm bảo chỉnh sửa sẽ tránh nhận diện nội dung trùng lặp, liên kết Page/tài khoản hoặc cảnh cáo của nền tảng.

MVP dùng text-to-video rời từng cảnh qua MuAPI (mục 4.3): mỗi cảnh sinh độc lập từ scene prompt dạng text, không có ảnh nhân vật tham chiếu, nên nhân vật/bối cảnh có thể đổi giữa các cảnh. Đồng bộ nhân vật/bối cảnh xuyên nhiều cảnh bằng video model hỗ trợ reference-image (ví dụ Kling multi-reference, Seedance bản reference) là hướng mở rộng sau MVP, xem mục 7 và mục 8.

Người dùng muốn bốn lựa chọn kết nối AI: **ChatGPT, Antigravity, Gemini, Codex**, không nhập API key LLM trong UI. Tham khảo [9Router](https://github.com/decolua/9router) ở commit `a99cf57239ff778b61e434c2786009d5ed1c412c` để học cấu trúc provider adapter/OAuth; contract sử dụng vẫn theo tài liệu chính thức. ChatGPT và Codex cùng dùng Sign in with ChatGPT khi được cấp quyền; Gemini dùng Google OAuth cho Gemini API của project AffiHub, không dùng phiên Gemini CLI. Antigravity hiển thị “Chưa khả dụng” vì [điều khoản Google](https://www.antigravity.google/terms) hiện cấm phần mềm bên thứ ba truy cập bằng Antigravity OAuth. Xem [Porting Note xác thực AI](reference-analysis/ai-account-login.md). Credential MPT, MuAPI, stock và TTS vẫn do máy chủ quản lý.

## 2. Quyết định MVP

| Hạng mục | Chọn cho MVP | Lý do kỹ thuật và trải nghiệm |
|---|---|---|
| Nơi đăng | Facebook Page (Meta Graph API) + TikTok (Content Posting API) + Instagram (Graph API, Business account) + YouTube (Data API v3 `videos.insert`); không đăng lên profile cá nhân Facebook/Instagram | Cả 4 nền tảng đều có API chính thức cho việc đăng; mỗi nền tảng có app review/điều kiện riêng (xem mục 8, 9) — không phải đăng được ngay khi code xong, còn phụ thuộc review kết quả. |
| Nguồn video | (a) Dán link video → `yt-dlp` tự tải (best-effort, worker riêng); (b) Import file từ máy; (c) Tìm/crawl nội dung viral theo từ khoá/danh mục (dùng endpoint khám phá chính thức khi nền tảng có, ví dụ YouTube `videos.list(chart=mostPopular)`; nền tảng không có endpoint khám phá chính thức thì không crawl, chỉ nhận link thủ công). Cả 3 nhánh cùng đổ vào 1 pipeline edit. Giới hạn tối đa **10 job tải/giờ** (cấu hình được) cho Download worker, áp dụng chung cho (a) và (c). | Không có API tải file thống nhất cho 4 nền tảng; `yt-dlp` là cách kỹ thuật duy nhất khả thi cho (a). Crawl hàng loạt ở (c) nhân rủi ro bản quyền/ToS theo số lượng, không phải rủi ro từng lần — rủi ro do người dùng/chủ dự án chịu, UI cảnh báo trước khi bật, không có cơ chế né phát hiện. Giới hạn 10 job/giờ là kiểm soát tốc độ cụ thể, giảm khả năng bị chặn IP hàng loạt — không loại bỏ rủi ro ToS/bản quyền của từng lần tải. |
| Giám sát | Telegram bot: báo động (worker down, publish lỗi, dấu hiệu bị giới hạn/khoá) + lệnh `/pause_auto_publish`, `/pause_auto_reply`, `/status` | API chính thức, không cần app review (khác hẳn 4 nền tảng social) — công tắc khẩn cấp đúng cho rủi ro automation đã chấp nhận; chỉ nhận lệnh từ chat_id allowlist để tránh người lạ điều khiển app. |
| Lịch đăng & tự động hoá | Auto-publish theo lịch, giới hạn tối đa **5 lần đăng/24h cho mỗi đích** (cấu hình được, mặc định 5) + jitter ngẫu nhiên 5–30 phút quanh giờ hẹn (không đăng đúng giây y hệt mỗi lần) + tự trả lời MỌI bình luận mới (không gồm tin nhắn/DM) bằng 1 câu mặc định cố định mỗi đích, có thể thêm override theo từ khoá nếu muốn | Người dùng chọn đánh đổi tốc độ lấy rủi ro khoá tài khoản/Page; giới hạn tần suất + jitter là kiểm soát cụ thể, không chỉ là "không gửi dồn dập" chung chung. Mặc định trả lời tất cả bình luận là cấu hình đơn giản nhất; DM/Messenger bị loại khỏi MVP vì có policy riêng về cửa sổ 24 giờ mà AffiHub chưa xử lý (mục 4.5.b) — cắt phạm vi thay vì làm sai policy. Không dùng AI sinh câu trả lời tự do để tránh rủi ro nội dung sai lệch/vi phạm chồng thêm. |
| AI video | MPT `video_source=muapi`; preset thử đầu tiên là `seedance-lite-t2v` 480p, scene 3–12 giây; lấy báo giá tất cả cảnh trước khi gửi và yêu cầu xác nhận tổng phí. | MPT tạo một clip ngắn cho mỗi scene prompt rồi ghép lại; số cảnh, độ dài, model và độ phân giải làm đổi chi phí. 480p là preset preview tiết kiệm, UI phải hiện độ phân giải nguồn và cho xem báo giá model khác trước khi render final. API MPT không tự chặn chi phí trước khi nhận job. |
| Kết nối LLM | Hiển thị ChatGPT, Codex, Gemini, Antigravity; ChatGPT/Codex dùng chung OpenAI OAuth, Gemini dùng OAuth chính thức cho Gemini API, Antigravity chưa khả dụng theo điều khoản Google. Không có ô nhập API key LLM. | Quyền đăng nhập và quyền gọi model là hai bước kiểm tra riêng. Chặn đúng bước script/scene khi chưa đủ quyền, giữ video local hoạt động. |
| Giọng đọc | Dùng [VieNeu-TTS](https://github.com/pnnbao97/VieNeu-TTS) tự host qua slot TTS tự host sẵn có của MPT (`_openai_compatible_tts`, đang dùng cho Chatterbox/Kokoro) trỏ `base_url` sang VieNeu-TTS container; Edge TTS/Azure Speech TTS v2 giữ làm fallback nếu container VieNeu-TTS không khả dụng — **UI phải hiện rõ "đang dùng giọng dự phòng (Edge TTS/Azure)" khi fallback kích hoạt**, không âm thầm đổi giọng vì chất lượng/accent khác hẳn VieNeu-TTS. Khớp request/response `/v1/audio/speech` với `_openai_compatible_tts` của MPT là giả định CHƯA xác minh — phải verify bằng spike thật trước khi khoá kiến trúc này (xem mục 10). | VieNeu-TTS license Apache 2.0, 25 giọng Bắc/Trung/Nam (so với 2 giọng Edge TTS), chạy CPU được (~0.35 RTF int8) nên hợp local-first; endpoint `/v1/audio/speech` cùng dạng OpenAI-compatible mà MPT đã có transport chung, không cần fork code MPT — nhưng đây là giả định, chưa đọc code MPT xác nhận thật. Voice cloning của VieNeu-TTS để ngoài MVP vì rủi ro consent giọng người khác. |
| Biên tập/render | FFmpeg trong worker riêng; output chuẩn Facebook Reel 9:16 MP4. | FFmpeg đã xử lý tốt trim, crop, scale, blur, brightness, audio, overlay và encode. |
| Đăng | Mặc định: người dùng xem preview, chọn Page/kênh, sửa caption và bấm xác nhận. Khi bật auto-publish cho một project/lịch cụ thể: Scheduler tự gọi publisher đúng giờ, không chờ người duyệt. | Chế độ duyệt tay tránh nhầm upload xong với đăng thành công; chế độ auto-publish đánh đổi lấy tốc độ, người dùng tự bật theo từng project/lịch, không phải mặc định toàn hệ thống. Trạng thái `Published` trong cả 2 chế độ đều chỉ ghi sau khi nền tảng xác nhận, không suy từ "job chạy xong". |
| Google | Google Drive + Sheets kết nối tùy chọn; đồng bộ nền và retry riêng. | Không để lỗi Google làm dừng luồng video hoặc làm đăng trùng. |

## 3. Flow tổng quan

### 3.1 Thiết lập lần đầu

```text
Mở AffiHub
  ├─ Dùng thử: mở video mẫu → biên tập → render preview → tải MP4 về máy
  │             (luồng video local; không gọi Meta, không tạo bài đăng giả)
  └─ Dùng thật:
       Kết nối từng nền tảng muốn dùng (độc lập, không bắt buộc đủ cả 4):
       Facebook: tạo Page → Meta Developer App + callback local → app role
                 → kết nối → chọn Page → kiểm tra quyền tạo nội dung
       TikTok:   tạo app TikTok Developer → base review → kết nối →
                 (audit Content Posting API riêng trước khi đăng public)
       Instagram: cần Instagram Business account có Page liên kết → Meta
                 Facebook Login for Business → chọn Page và cấp quyền
                 pages_show_list, pages_read_engagement, instagram_basic,
                 instagram_content_publish
       YouTube:  tạo Google Cloud project → bật YouTube Data API v3 →
                 kết nối OAuth → chọn kênh
       → Nếu dùng AI: chọn ChatGPT/Codex hoặc Gemini → đăng nhập tài khoản
         và kiểm tra quyền model; Antigravity hiển thị chưa khả dụng
       → (tùy chọn) cấu hình rule tự trả lời bình luận/tin nhắn theo nền tảng
       → (tùy chọn) kết nối Google Drive/Sheets → chọn folder + spreadsheet/tab
       → Người vận hành cấu hình credential máy chủ cho MPT/MuAPI/stock/Azure
```

### 3.2 Mỗi video

```text
Tạo project
  ├─ Import MP4/MOV từ máy
  ├─ Dán link (YouTube/Facebook/TikTok/Instagram) → yt-dlp tự tải
  │    └─ lỗi → hướng dẫn tải/xuất chính thức → import file thủ công
  ├─ Tìm/crawl nội dung viral theo từ khoá/danh mục → chọn video từ kết
  │    quả → tự tải như nhánh dán link
  └─ Tạo bằng AI
       → chọn kết nối LLM đã đăng nhập và model được cấp quyền
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
       Chọn nền tảng/Page/kênh đích + caption riêng từng đích
                         ↓
       Duyệt tay (mặc định) → xác nhận đăng ngay
       hoặc Auto-publish (bật riêng cho project/lịch) → Scheduler tự đăng
       đúng giờ, không chờ duyệt
                         ↓
       Publisher đúng nền tảng (Facebook/TikTok/Instagram/YouTube) →
       xử lý → publish → đối soát trạng thái/permalink

       Nhánh phụ không chặn bước chính:
       Duyệt → Drive tạo subfolder riêng cho video + upload MP4
       Duyệt → Sheet upsert theo render version + đích (kèm tóm tắt/caption + link subfolder)
       Đăng xong → AutoResponder bắt đầu theo dõi bình luận/tin nhắn theo
       rule đã cấu hình cho đích đó (nếu bật)
       (nếu lỗi: giữ job để retry; không làm lại render hoặc đăng lại)
```

### 3.3 Ba bước chính trên giao diện

```text
Nguồn (import/link/crawl/AI)  →  Biên tập & render  →  Duyệt & đăng (hoặc auto-publish)
                         └────────────→ Drive/Sheets tự đồng bộ nền
                         └────────────→ AutoResponder (trả lời comment/DM, nếu bật)
```

AI generation là một cách tạo nguồn video và đưa kết quả vào cùng editor, không tạo một quy trình xuất bản riêng. Người dùng chỉ cần theo dõi ba bước chính; trạng thái Drive/Sheets nằm trong panel đồng bộ riêng.

## 4. Flow người dùng chi tiết

### 4.1 Kết nối mạng xã hội (Facebook, TikTok, Instagram, YouTube — nhiều profile)

MVP hỗ trợ kết nối **nhiều profile/tài khoản**, trên cả 4 nền tảng, độc lập với nhau — không bắt buộc đủ cả 4, mỗi nền tảng kết nối xong là dùng được riêng.

**4.1.a Facebook Page**

1. Nếu chưa có Page, AffiHub mở hướng dẫn tạo Page trên Facebook. Người dùng quay lại AffiHub sau khi tạo xong.
2. Người quản lý tạo Meta Developer App, cấu hình Facebook Login/OAuth callback theo địa chỉ local của app và để app ở Development mode cho POC.
3. Thêm Facebook profile sẽ dùng AffiHub vào app role Developer/Tester. Profile đó cần có quyền quản lý Page và tạo nội dung trên Page.
4. Người dùng bấm **Kết nối Facebook**, đăng nhập và cấp các quyền Page mà Meta yêu cầu cho endpoint đăng Reels.
5. AffiHub liệt kê Page được cấp quyền, hiển thị tên/Page ID/task được trả về, rồi cho chọn Page mặc định.
6. Nút **Kiểm tra kết nối** gọi API đọc lại danh sách Page và xác nhận Page có quyền tạo nội dung. Nếu không đạt, UI nêu rõ profile, Page role hoặc quyền OAuth cần sửa.
7. Trong Development mode, chỉ app role/tester và tài sản được cấp cho họ có thể dùng để thử. Muốn cho người ngoài app role sử dụng, cần kiểm tra access level, Advanced Access và review của Meta theo quyền/API hiện hành.

Một Facebook profile có thể quản lý nhiều Page; MVP cho kết nối nhiều Facebook profile cùng lúc. Người dùng chọn một hoặc nhiều Page/profile ở bước duyệt; mỗi Page là một publication riêng.

**4.1.b TikTok**

1. Tạo app trên TikTok Developer Portal, qua base app review (website đầy đủ thông tin, Privacy Policy/Terms truy cập được không cần vào menu).
2. Kết nối OAuth trong AffiHub, cấp quyền `video.publish`. Nếu app/user được TikTok cấp thêm `video.list`, AffiHub dùng scope đó để tra `share_url` của bài công khai; thiếu `video.list` không chặn đăng.
3. **Giới hạn khi chưa qua audit riêng cho Content Posting API:** đã verify qua [TikTok Content Sharing Guidelines](https://developers.tiktok.com/docs/en/content-sharing-guidelines) chính thức — client chưa audit bị ép `privacy_level=SELF_ONLY` (chỉ chủ tài khoản thấy) bất kể chọn gì, tối đa 5 tài khoản đăng/24h, và tài khoản đăng phải đang ở chế độ private tại thời điểm đăng. Đăng công khai cần audit riêng (ngoài base review); thời gian xử lý và tỷ lệ bị từ chối ở lần đầu không có con số chính thức từ TikTok — các ước lượng "vài ngày đến vài tuần" trong cộng đồng dev không phải cam kết của TikTok, không đưa vào điều kiện nghiệm thu như một deadline chắc chắn.
4. UI phải hiện rõ trạng thái audit hiện tại (chưa audit / đang chờ / đã audit) để người dùng biết vì sao đăng công khai chưa dùng được. **TikTok ở chế độ SELF_ONLY (chưa audit) được tính là "kết nối và đăng thành công" cho mục đích nghiệm thu MVP** (mục 11) — đăng công khai hàng loạt là mục tiêu sau khi audit pass, không phải điều kiện bắt buộc để coi MVP hoàn thành.

**4.1.c Instagram**

1. MVP chỉ nhận **Instagram Business account có Facebook Page liên kết**. Meta-published Instagram API collection mô tả publishing cho Business và Creator; Business-only là product gate của AffiHub, không phải giới hạn chung của API. Personal account không đủ điều kiện.
2. Kết nối qua Meta Developer App bằng Facebook Login for Business, chọn Page từ `/me/accounts`, rồi lưu Page Access Token cùng `instagram_business_account` ID. Scope Facebook Login hiện đối chiếu từ Meta collection: `pages_show_list`, `pages_read_engagement`, `instagram_basic`, `instagram_content_publish`. Không dùng `instagram_business_basic`/`instagram_business_content_publish` của Instagram Login trong flow này. Xác minh lại permission dependencies, access level và App Review trên Meta docs/App Dashboard trước production.
3. Không hardcode publishing cap ngày. Gọi `content_publishing_limit` trước publish và dùng quota/usage mà endpoint hiện hành trả về; stories không nằm trong MVP. Canonical Meta docs và response schema cần được xác minh lại lúc implement/runtime.
4. Tạo Reels container với `upload_type=resumable`, tải binary local trực tiếp tới URI `rupload.facebook.com`, poll tới `status_code=FINISHED`, rồi gọi `media_publish`. Không cần public `video_url`, CDN hay relay.

**4.1.d YouTube**

1. Tạo Google Cloud project, bật YouTube Data API v3, cấu hình OAuth consent.
2. Kết nối OAuth, chọn kênh YouTube của profile.
3. Upload qua `videos.insert` — đã verify qua tài liệu/quota calculator chính thức của Google: chi phí quota giảm từ ~1600 unit xuống ~100 unit (4/12/2025), rồi từ 1/6/2026 tách thành bucket riêng (1 unit/call, mặc định 100 call/ngày/project), tách khỏi 10.000 unit/ngày dùng chung cho các endpoint khác — không còn là nút thắt quota như trước đây. Google có thể đổi chính sách này tiếp; kiểm tra lại [Quota Calculator](https://developers.google.com/youtube/v3/determine_quota_cost) chính thức tại thời điểm implement trước khi dựa vào số liệu này.

**Tham khảo:** [Meta Reels Publishing API](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api), [Meta Graph API access levels](https://developers.facebook.com/docs/graph-api/overview/access-levels/), [Postiz Facebook provider](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts), [TikTok Content Posting API](https://developers.tiktok.com/doc/content-posting-api-get-started/), [Instagram Content Publishing](https://developers.facebook.com/docs/instagram-platform/content-publishing/), [YouTube videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert). Postiz dùng để đối chiếu provider boundary và xử lý lỗi; quyền/API version lấy từ tài liệu chính thức từng nền tảng tại thời điểm implement.

### 4.2 Import video có sẵn

1. Người dùng dán link video (YouTube/Facebook/TikTok/Instagram) **hoặc** bấm **Import video** rồi kéo thả file/chọn file từ máy — hai đường vào song song, không bắt buộc đi qua link.
2. **Nhánh dán link:** AffiHub lưu `source_url`, hiện cảnh báo một lần ("video tải về có thể không phải của bạn, bạn tự chịu trách nhiệm quyền sử dụng và tuân thủ Điều khoản dịch vụ của nền tảng nguồn") rồi gửi job cho Download worker (`yt-dlp`, chạy nền, không chặn UI). Thành công → file tự động vào project như nhánh import. Lỗi/timeout → UI báo rõ lý do (site đổi, bị chặn rate-limit, video riêng tư/đã xoá...) và chuyển sang hướng dẫn import thủ công (mở công cụ owner export/download của nền tảng, tải về máy, quay lại import).
3. **Nhánh import file:** chọn file trực tiếp, bỏ qua bước tải — luôn hoạt động kể cả khi Download worker lỗi hoặc `yt-dlp` không hỗ trợ nguồn đó.
4. Worker lưu file nguồn riêng, chạy `ffprobe`, hiển thị thời lượng, kích thước, codec, frame rate và audio track — áp dụng như nhau cho file từ cả hai nhánh.
5. Nếu file không đọc được hoặc vượt giới hạn cấu hình, project vẫn được giữ; UI nêu định dạng/lý do và hướng dẫn chọn lại hoặc chuyển định dạng.

**Download worker (`yt-dlp`) — best-effort, không cam kết ổn định:**

- Chạy trong Solid Queue job riêng, timeout cố định (không chờ vô hạn), không retry quá N lần tự động — lỗi thì báo cho người dùng tự quyết định thử lại hay chuyển sang import thủ công.
- `yt-dlp` không phải API chính thức của nền tảng nào; khi nền tảng đổi cấu trúc nội bộ, extractor có thể gãy tới khi cộng đồng `yt-dlp` vá — AffiHub không tự fix, chỉ pin version và cập nhật định kỳ.
- Rủi ro Điều khoản dịch vụ (ToS) và bản quyền với video không phải của người dùng do người dùng/chủ dự án chịu — AffiHub chỉ cảnh báo, không chặn hay thẩm định quyền sở hữu nội dung.
- Không tự retry khi bị rate-limit/chặn IP từ nền tảng nguồn; báo lỗi rõ ràng thay vì lặp lại request có thể làm nặng thêm việc bị chặn.

**Đường lấy file theo nền tảng (khi Download worker lỗi hoặc không hỗ trợ nguồn):**

| Nguồn | Cách đưa file vào MVP | Giới hạn API hiện biết |
|---|---|---|
| YouTube | Thử tải URL bằng `yt-dlp` trong worker; nếu thất bại hoặc không hỗ trợ, người dùng có thể tải video mình đã upload qua YouTube Studio/Google Takeout rồi import. Ưu tiên file gốc nếu còn vì Studio có thể chỉ xuất 720p/360p. | YouTube Data API có metadata và upload/update/delete; không có endpoint trả file video. [Hướng dẫn tải video đã upload](https://support.google.com/youtube/answer/56100), [Video resource API](https://developers.google.com/youtube/v3/docs/videos) |
| Facebook Page/Reels | Import file gốc hoặc bản người dùng xuất/tải từ phần quản lý Page. [Tải bản sao Page](https://www.facebook.com/help/1206330326045914) | Graph API v26 `/{page-id}/videos` không hỗ trợ đọc danh sách. Video node có trường `source`, nhưng cần xác định video ID qua một đường đọc được hỗ trợ trước; chưa coi đây là connector MVP. [Page Videos v26](https://developers.facebook.com/docs/graph-api/reference/page/videos/), [Video node v26](https://developers.facebook.com/docs/graph-api/reference/video/) |
| Instagram Reels | Import file gốc hoặc bản người dùng xuất từ [Meta Accounts Center](https://about.fb.com/news/2023/10/manage-your-information-across-apps/). | API đọc media có thể trả `media_url` cho tài khoản Professional, nhưng consumer account không được hỗ trợ; cần quyền/review và URL media không bảo đảm cho mọi video. Để ngoài MVP. [Instagram API](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/), [IG User media](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media/) |
| TikTok | Dùng [Save video](https://support.tiktok.com/en/using-tiktok/exploring-videos/video-downloads) hoặc yêu cầu bản dữ liệu từ TikTok, sau đó import file. | Display API trả metadata/embed, không trả file. Data Portability có thể xuất bài nhưng hiện chỉ cho người dùng EEA/UK; app cần Data Portability approval, Login Kit approval và app review nên không dùng cho tài khoản ở Việt Nam. [Display API](https://developers.tiktok.com/docs/en/display-api-overview), [Data Portability availability](https://developers.tiktok.com/products/data-portability-api), [Approval flow](https://developers.tiktok.com/docs/en/data-portability-api-get-started) |

Connector tự động riêng cho video do chính Page người dùng quản lý (tìm attachment/video ID qua route Meta cho phép rồi đọc `Video.source`) vẫn để sau MVP: cần spike chứng minh trọn luồng; Graph API v26 hiện không hỗ trợ đọc Page Videos edge nên không hứa duyệt/tải toàn bộ thư viện Page.

### 4.2.b Tìm/crawl nội dung viral

1. Người dùng nhập từ khoá hoặc chọn danh mục; AffiHub gọi endpoint khám phá/trending **chính thức** của nền tảng khi có (ví dụ YouTube `videos.list(chart=mostPopular, videoCategoryId=...)`), trả danh sách video kèm metadata (tiêu đề, kênh, lượt xem, thumbnail).
2. Instagram có hashtag discovery giới hạn cho Professional Account/Page; TikTok Research API chỉ cấp cho nghiên cứu đủ điều kiện sau khi duyệt. MVP không dùng hai API này nếu access tier và mục đích sử dụng chưa được xác minh; không thay bằng crawler, người dùng có thể tự dán URL cụ thể theo nhánh 4.2 thường.
3. Trong MVP chỉ kết quả YouTube từ API chính thức được đưa vào discovery flow; user chọn một video cụ thể rồi mới tạo yêu cầu download. Playlist không tự mở rộng thành nhiều job. Việc chọn kết quả không cấp quyền tải và flow YouTube API → `yt-dlp` vẫn giữ policy caveat trong [Porting Note](reference-analysis/yt-dlp-youtube-discovery.md). Mọi download cần cảnh báo, worker riêng, timeout, lỗi/fallback và không retry mù khi bị rate-limit/chặn.
4. Tải hàng loạt tăng tốc độ bị nền tảng phát hiện pattern tự động (nhiều request liên tiếp từ cùng nguồn) — không có cơ chế né; giới hạn tốc độ gửi job (rate limit phía AffiHub) chỉ để giảm khả năng bị chặn IP, không loại bỏ rủi ro.

**Rủi ro:** nội dung tìm được không phải của người dùng; tải về dùng lại mang rủi ro bản quyền, nhân theo số lượng khi tải hàng loạt. AffiHub không thẩm định quyền sở hữu nội dung — rủi ro ToS/bản quyền/khoá tài khoản do người dùng/chủ dự án chịu, đã xác nhận chấp nhận ở mục 1.

### 4.3 Tạo video bằng AI

AffiHub tích hợp pipeline có sẵn của MoneyPrinterTurbo (MPT), không tự dựng lại stage script/scene/TTS/subtitle/render.

**Kết nối LLM trước khi tạo script:** UI hiển thị bốn lựa chọn ChatGPT, Codex, Gemini và Antigravity. ChatGPT/Codex dùng chung OpenAI Sign in with ChatGPT khi ứng dụng/tài khoản có quyền dùng gói và model; Codex không có OAuth thứ hai và AffiHub không đọc phiên Codex CLI. Gemini dùng Google OAuth cho Gemini API của Google Cloud project do AffiHub cấu hình, cần xác minh scope, consent, quota/billing và request thật; không mượn phiên Gemini CLI hoặc kết nối Drive/YouTube. Antigravity được ghi “Chưa khả dụng” và không có thao tác OAuth khi điều khoản Google chưa cho phép tích hợp bên thứ ba. Không yêu cầu API key LLM nhập tay. Quyền danh tính không tự chứng minh quyền inference; nếu quyền/hạn mức không đạt thì khóa riêng bước LLM. Trước khi nối pipeline, phải kiểm chứng MPT v1.3.8 gọi LLM ở bước nào; token ChatGPT plan chỉ dùng Responses API được cấp quyền, không tự đưa vào endpoint OpenAI-compatible của MPT.

1. Người dùng chọn **Tạo bằng AI**, nhập chủ đề, ngôn ngữ, tone và thời lượng mục tiêu. Mặc định tạo 5 cảnh, mỗi cảnh 6 giây (khoảng 30 giây tổng); người dùng sửa số cảnh và độ dài trước khi tạo video. Clip tạo bằng preset `seedance-lite-t2v` có độ dài 3–12 giây mỗi cảnh.
2. Trước mỗi yêu cầu script/scene prompts, AffiHub kiểm tra kết nối, quyền sử dụng model và hạn mức nếu provider trả về; hiển thị provider/model cùng trạng thái chi phí hoặc hạn mức. Với lượt dùng thuộc gói ChatGPT, ghi “theo hạn mức gói, không có báo giá tiền từng lượt”, không ghi miễn phí hoặc tự đặt số tiền bằng 0. Chỉ gửi request sau thao tác **Tạo kịch bản** hoặc **Tạo gợi ý cảnh** của người dùng.
3. AffiHub gọi MPT `POST /api/v1/scripts`. Người dùng xem và sửa kịch bản. Không chuyển sang tạo cảnh nếu kịch bản chưa được duyệt.
4. AffiHub gọi MPT `POST /api/v1/terms` để tạo scene prompts. Người dùng chỉnh prompt từng cảnh và số cảnh trước khi gọi dịch vụ video.
5. Chế độ chính là **AI tạo cảnh**: AffiHub lấy báo giá MuAPI cho model, từng prompt, thời lượng và độ phân giải; hiển thị tổng tiền/đơn vị tiền tệ/số clip và độ phân giải nguồn. Chỉ gọi MPT `POST /api/v1/videos` với `video_source=muapi` sau khi người dùng xác nhận.
6. MPT gửi tác vụ bất đồng bộ cho từng cảnh, ghép các clip thành timeline, tạo voiceover và subtitle, rồi render preview MP4. Clip cảnh ngắn được ghép nối; UI không hứa giữ nhân vật hoặc chuyển động liên tục giữa các cảnh, cũng không mô tả upscale thành chi tiết native của video độ phân giải thấp.
7. **AI script + stock montage** là lựa chọn riêng để giảm chi phí video generation; dùng footage stock theo API cấu hình MPT. UI ghi rõ đây là montage bằng footage stock, không gọi là clip text-to-video.
8. MPT task ID và trạng thái được lưu ở AffiHub. Khi timeout sau khi gửi job đến MuAPI, chuyển sang **Chưa rõ kết quả**, kiểm tra task/provider ID trước khi thử lại để không tạo job có thể bị tính phí lần hai.

**Repo/version:** [MoneyPrinterTurbo v1.3.8 release](https://github.com/harry0703/MoneyPrinterTurbo/releases/tag/v1.3.8), pinned commit `fafec0fbf3142ad5ad7212c2e17996bf247c360a`, license MIT ([license file](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/LICENSE)). File để port: [script/terms controller](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/app/controllers/v1/llm.py), [video controller](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/app/controllers/v1/video.py), [request schema](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/app/models/schema.py), [MuAPI service](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/app/services/muapi.py), [config](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/config.example.toml), [voice list](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/docs/voice-list.txt). MPT chạy trong Python worker riêng; không mang WebUI của repo vào Rails. Không dùng tag `latest`.

**Worker an toàn:** MPT config mặc định có thể bind `0.0.0.0` và chạy không cần API key nếu key để trống. AffiHub phải override bind về `127.0.0.1`, đặt API key bắt buộc, dùng thư mục job tách biệt và pin commit/image digest. Không đưa key MPT/MuAPI hay OAuth token LLM ra trình duyệt hoặc log.

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

### 4.5 Duyệt và đăng (đa nền tảng, thủ công hoặc tự động)

Màn hình review hiển thị video preview của đúng `render_version`, caption riêng từng đích (Page/kênh/tài khoản), danh sách đích đã chọn, trạng thái Drive/Sheet và thông số preflight theo từng nền tảng đích. Hai chế độ:

- **Duyệt tay (mặc định):** người dùng bấm **Đăng lên các đích đã chọn** để xác nhận một lần; kết quả theo dõi riêng từng đích.
- **Auto-publish (bật riêng theo project hoặc theo lịch):** người dùng đặt lịch (ngày giờ, hoặc lặp lại) cho một `RenderVersion` + danh sách đích; Scheduler (Solid Queue job chạy định kỳ) tự gọi publisher đúng giờ, không chờ người bấm xác nhận. Vẫn áp dụng toàn bộ preflight/định dạng trước khi gửi — chỉ bỏ bước người duyệt, không bỏ bước kiểm tra kỹ thuật.

Mỗi nền tảng có quy trình publish riêng (`PublisherResolver` chọn publisher theo platform, xem mục 6):

```text
Facebook Reels:  tạo upload session → upload file → hỏi trạng thái xử lý
                 → finish/publish → poll/đối soát trạng thái cuối
TikTok:          upload video → tạo post (PUBLISH_PARAMS) → poll trạng thái
                 qua publish ID → đối soát
Instagram Reels: tạo media container (video_url, media_type=REELS) →
                 poll status_code đến FINISHED → media_publish → đối soát
YouTube:         videos.insert (resumable upload) → trạng thái processing
                 → đối soát video ID/trạng thái cuối
```

Không coi `upload success` hoặc response `success: true` ban đầu là đã đăng, ở bất kỳ nền tảng nào. Chỉ ghi **Đã đăng** khi API nền tảng đó xác nhận trạng thái cuối; nếu request timeout hoặc kết quả không rõ, đánh dấu **Cần kiểm tra**, truy vấn lại trước khi cho retry — áp dụng giống nhau cho cả đăng thủ công và auto-publish.

MVP export profile: MP4, H.264, AAC, 1080×1920 (9:16), 30 fps, mặc định 30 giây — dùng chung cho cả 4 nền tảng (mỗi nền tảng preflight theo giới hạn riêng: Facebook Reels tối thiểu 540×960/23fps/4–60s; Instagram Reels 9:16/5–90s; TikTok/YouTube theo giới hạn hiện hành của từng API). Tại bước cấu hình API, ghi rõ version/API đã chọn cho từng nền tảng và kiểm lại yêu cầu theo version đó; preflight dùng cấu hình versioned theo từng nền tảng, không nhúng giới hạn thay đổi vào nhiều chỗ.

**Không nền tảng nào yêu cầu file Markdown để đăng.** Mỗi API nhận media video và mô tả/caption dạng text. `.md` dùng để viết tài liệu dự án, không phải định dạng upload video.

Luồng video local không cần credential mạng xã hội; người dùng import, biên tập, render và tải MP4 mà không gọi API nền tảng hoặc tạo post ID/permalink giả. Muốn đăng thật phải cấu hình kết nối theo từng nền tảng ở mục 4.1.

**Tham khảo:** [Meta Reels Publishing API collection](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api), [Postiz Facebook provider](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts), [TikTok Content Posting API](https://developers.tiktok.com/doc/content-posting-api-get-started/), [Instagram Content Publishing](https://developers.facebook.com/docs/instagram-platform/content-publishing/), [YouTube videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert). API version/quyền phải được kiểm chứng tại thời điểm implement, theo từng nền tảng.

### 4.5.b Tự động trả lời bình luận/tin nhắn

1. Người dùng cấu hình theo đích (Page/kênh/tài khoản): **1 câu trả lời mặc định cố định**, áp dụng cho MỌI bình luận mới (ví dụ "Chào bạn, chúc bạn một ngày tốt đẹp, nhớ ủng hộ mình nha!") — không cần match từ khoá, mặc định trả lời hết. Có thể thêm override theo từ khoá cụ thể (danh sách cặp từ khoá → câu trả lời riêng, khớp trước thì dùng câu riêng đó thay vì câu mặc định) nếu người dùng muốn, nhưng không bắt buộc cấu hình gì thêm ngoài câu mặc định để dùng được. Không dùng AI sinh câu trả lời tự do trong MVP — tránh chồng thêm rủi ro nội dung sai lệch/phản cảm lên rủi ro automation đã có.
2. AutoResponder worker lắng nghe bình luận/tin nhắn mới qua webhook/poll chính thức của nền tảng (Facebook: Page comments/Messenger webhook; Instagram: Graph API comments/messaging — cả hai cần quyền riêng qua app review; TikTok hiện không có API public ổn định cho việc này, để ngoài MVP cho TikTok).
3. Có override từ khoá khớp → gửi câu trả lời riêng đó. Không khớp override nào → gửi câu trả lời mặc định. Tắt tính năng cho đích đó → không trả lời bất kỳ bình luận nào.
4. Ghi log mọi lần tự trả lời (thời điểm, bình luận/tin nhắn gốc, câu trả lời đã gửi — mặc định hay override) để người dùng xem lại và tắt tính năng nếu cần.

**Rủi ro:** tự động trả lời bình luận/tin nhắn là hành vi nền tảng có thể giám sát và giới hạn (đặc biệt Messenger có policy riêng về automated responses ngoài cửa sổ 24h với người dùng). Không có cơ chế né; bật tính năng này là chấp nhận rủi ro giới hạn/khoá tính năng nhắn tin của Page/tài khoản.

### 4.6 Google Drive và Sheets

Kết nối Google là tùy chọn. Nếu bỏ qua, video vẫn xử lý/duyệt/đăng và được giữ local; Settings có thể kết nối sau. Khi kết nối sau, người dùng chọn project/render cụ thể để đồng bộ, app không tự đẩy toàn bộ thư viện.

1. Người dùng bấm **Kết nối Google** bằng OAuth, chọn Drive folder gốc và spreadsheet/tab hoặc tạo bảng theo mẫu AffiHub.
2. AffiHub tạo mapping cột một lần; cột bắt buộc: `project_id`, `render_version`, `page_id`, `video_title` (tóm tắt/caption đã dùng khi duyệt), `drive_folder_id`, `drive_folder_url`, `drive_file_id`, `drive_url`, `publish_status`, `facebook_post_id`, `facebook_permalink`, `last_error`, `updated_at`.
3. **Trigger khi người dùng duyệt (bấm Đăng), không phải ngay sau render.** Drive worker tạo 1 subfolder riêng cho video đó bên trong Drive folder gốc (tên subfolder theo `project_id` + tiêu đề/caption), rồi upload MP4 resumable vào subfolder đó. Ghi idempotency key trong Drive `appProperties`; timeout thì tìm lại file theo key trước khi upload lần nữa hoặc tạo lại subfolder.
4. Sau khi có `Publication` cho một render/đích, Sheet worker tìm `sheet_row_key`; nếu có thì update hàng đó, nếu chưa có thì append — ghi cả `video_title` (tóm tắt/caption) và link subfolder (`drive_folder_url`) cùng link file. Key gồm `project_id + render_version + page_id`.
5. Mỗi lần render mới có hàng mới và subfolder mới riêng. Không đổi hàng của render cũ để trỏ sang file mới vì sẽ làm sai permalink/trạng thái bài đã đăng.
6. Google job chạy độc lập với publish, nhưng cùng khởi phát tại thời điểm duyệt. Lỗi Drive không chặn việc đăng; lỗi Sheet sau khi Drive thành công chỉ retry Sheet. Chỉ báo đồng bộ xong sau khi API trả xác nhận.
7. Ghi Sheet với `valueInputOption=RAW`; giữ quyền Drive riêng tư theo quyền folder gốc (subfolder kế thừa quyền), không tự chuyển file/folder thành public.

Sheets không cung cấp transaction hay unique constraint trên một cột. Rails database giữ khóa dòng và số hàng; worker serialize upsert theo `sheet_row_key`, dò key trước khi append để giảm trùng khi request timeout. App hiển thị nhãn dễ hiểu như **Drive chưa lưu**, **Sheet chưa đồng bộ**, **Đã đồng bộ**; mã lỗi kỹ thuật để trong log.

Google OAuth consent screen ở Testing có thể làm refresh token hết hạn sau 7 ngày. Bản local POC hiển thị nút kết nối lại và báo trạng thái hết hạn; trước khi chạy dài hạn không giám sát, cần hoàn thiện trạng thái consent/verification phù hợp.

**Tham khảo:** [Google API Ruby Client](https://github.com/googleapis/google-api-ruby-client), [Drive resumable upload](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [Drive `appProperties`](https://developers.google.com/workspace/drive/api/guides/properties), [Google Picker](https://developers.google.com/workspace/drive/picker/guides/web-picker), [Sheets values API](https://developers.google.com/workspace/sheets/api/guides/values), [OAuth best practices](https://developers.google.com/identity/protocols/oauth2/resources/best-practices), [refresh token expiry](https://developers.google.com/identity/protocols/oauth2#expiration).

### 4.7 Giám sát & điều khiển qua Telegram

AffiHub tích hợp 1 Telegram bot (Bot API chính thức, không cần app review — khác hẳn Facebook/TikTok/Instagram) để báo động và cho phép dừng khẩn automation từ xa.

**Thông báo (một chiều, bot → người dùng):**

- Worker down: MPT, VieNeu-TTS, Download worker không phản hồi health-check.
- Publication `Failed` hoặc `OutcomeUnknown` ở bất kỳ nền tảng nào.
- Dấu hiệu bị nền tảng giới hạn: HTTP 429/403 lặp lại, token bị thu hồi, API trả lỗi quyền đột ngột — đúng loại rủi ro đã chấp nhận ở mục 1, Telegram là kênh để biết sớm nhất có thể.
- Drive/Sheet sync `Failed`/`Unknown` sau hết số lần retry cấu hình.
- Auto-reply gửi lỗi (`Failed` trong `AutoReplyLog`).
- Mỗi lần Scheduler tự kích hoạt auto-publish (thành công hay thất bại) — vì không có người bấm tay để biết ngay lúc đó.

**Điều khiển (hai chiều, lệnh từ Telegram):**

- `/status` — tình trạng worker (MPT/VieNeu-TTS/Download còn sống không), số Publication đang `Scheduled`/`OutcomeUnknown`, số lỗi gần nhất.
- `/pause_auto_publish` — dừng Scheduler ngay (không claim thêm Publication nào mới); `/resume_auto_publish` — bật lại.
- `/pause_auto_reply` — dừng AutoResponder ngay (toàn bộ đích); `/resume_auto_reply` — bật lại.
- Đây là công tắc an toàn khẩn cấp cho đúng rủi ro automation đã chấp nhận ở mục 1 — không phải tính năng tiện ích, mà là cách duy nhất để dừng kịp khi phát hiện dấu hiệu sắp bị khoá tài khoản.

**Bảo mật:** bot token cấu hình qua `config/telegram.yml`/credentials, không log; chỉ nhận lệnh từ `chat_id` nằm trong allowlist cấu hình sẵn (không phải ai nhắn bot cũng điều khiển được) — thiếu allowlist này thì bất kỳ ai tìm ra bot đều pause/resume được automation của người khác.

**Tham khảo:** [Telegram Bot API](https://core.telegram.org/bots/api).

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

### 5.2 Publication theo đích (Page/kênh/tài khoản, mọi nền tảng)

```text
Draft → Approved ──────────────┐
  └→ Scheduled (auto-publish) ─┴→ Uploading → Processing → Published
                                       ↘ Failed (đã biết chắc)
                                       ↘ OutcomeUnknown (cần đối soát)
```

`Approved` là do người duyệt tay xác nhận; `Scheduled` là do Scheduler claim đúng giờ hẹn (atomic, theo pattern mục 6) khi auto-publish được bật — cả hai đều phải qua preflight trước khi vào `Uploading`, chỉ khác nguồn gốc chuyển trạng thái. `Publication` tham chiếu duy nhất một `RenderVersion` bất biến và một đích (Page/kênh/tài khoản) trên một nền tảng. Sheet retry không gọi lại publisher. Publish retry không upload lại hay tạo post mới trước khi tra trạng thái lần trước.

### 5.3 Tự động trả lời (AutoReply log)

```text
Nhận bình luận/tin nhắn mới (webhook/poll)
  → Tính năng có bật cho đích này không?
       ├─ Không → Skipped (tắt tính năng, không trả lời)
       └─ Có → Khớp override từ khoá?
                 ├─ Có → Sending (câu trả lời override) → Sent / Failed
                 └─ Không → Sending (câu trả lời mặc định) → Sent / Failed
```

Mỗi lần xử lý ghi 1 bản ghi `AutoReplyLog` (nguồn, override khớp hay mặc định, nội dung đã gửi, kết quả) — không sửa/xoá log cũ, chỉ thêm mới, để người dùng audit lại được.

### 5.4 Đồng bộ Google

```text
Drive: Pending → Uploading → Saved
                    ↘ Failed/Unknown → tìm appProperties rồi retry

Sheet: Pending → Synced
                   ↘ Failed/Unknown → tìm sheet_row_key rồi update cùng hàng
```

## 6. Thiết kế kỹ thuật

```text
Rails UI/API (tiếng Việt)
  ├─ OAuth + discovery/permission preflight cho 4 nền tảng
  │  (Facebook, TikTok, Instagram, YouTube), nhiều profile/tài khoản
  ├─ Models: VideoProject, SourceAsset, RenderVersion, SocialConnection,
  │          SocialDestination (Page/kênh/tài khoản, mọi nền tảng),
  │          Publication, AutoReplyRule, AutoReplyLog, Schedule,
  │          DriveExport, SheetSync
  └─ Solid Queue
       ├─ Import worker: local file → ffprobe
       ├─ Download worker: yt-dlp (dán link hoặc chọn từ crawl)
       ├─ Discovery worker: gọi endpoint trending chính thức (khi có)
       ├─ AI worker: MPT pinned release → LLM / MuAPI / TTS / subtitle
       ├─ Media worker: FFmpeg filters + encode
       ├─ Scheduler: claim Publication đến hạn auto-publish (atomic)
       ├─ Publisher (PublisherResolver → platform + type):
       │     MetaGraphPublisher, TikTokPublisher, InstagramPublisher,
       │     YoutubePublisher — mỗi cái: create → upload → process →
       │     publish → reconcile theo API riêng
       ├─ AutoResponder worker: webhook/poll bình luận/tin nhắn → khớp
       │     rule → gửi trả lời → ghi AutoReplyLog
       ├─ Google sync workers: Drive resumable upload + Sheets upsert
       └─ Telegram bot: gửi cảnh báo (worker down, publish lỗi, dấu hiệu
             bị giới hạn) + nhận lệnh /status, /pause_*, /resume_* (chỉ
             từ chat_id trong allowlist)
```

- Rails database là nguồn sự thật; Google Sheets chỉ là bản theo dõi.
- Video, tải file, AI generation và render không chạy trong request web. Worker có giới hạn dung lượng, thời gian, CPU/RAM, cancellation và thư mục theo job.
- File media là input không tin cậy: xác minh magic bytes/MIME, dùng `ffprobe`, không đưa path người dùng vào shell string; worker nhận arguments tách biệt.
- OAuth dùng `state`, PKCE khi provider hỗ trợ, callback allowlist và quyền tối thiểu cần cho từng nền tảng (Facebook/TikTok/Instagram/YouTube/Drive/Sheets/ChatGPT/Gemini API); Antigravity không khởi tạo OAuth. Không ghi access token, refresh token hoặc upload URL có chữ ký vào log. Mỗi `SocialConnection` lưu token riêng theo profile, không dùng chung token giữa các profile/nền tảng.
- Lưu source và render riêng. `RenderVersion` không sửa sau khi tạo; mọi Publication và Drive export giữ đúng ID/version.
- Access/refresh token Meta/Google/OpenAI được phép và API keys kỹ thuật MPT/MuAPI/stock/TTS mã hóa khi lưu; không log token, URL upload có chữ ký hoặc nội dung secret. Không sao chép token từ Codex CLI, Gemini CLI hoặc Antigravity sang AffiHub.
- MPT là dịch vụ local riêng, bind loopback, API key bắt buộc, version/image digest được pin. Không công khai port ra LAN/Internet. Chạy MPT như một Docker service riêng (khớp Kamal/Docker đã dùng để deploy AffiHub), image digest pin trong `docker-compose.yml`; dev khởi động bằng `docker compose up -d mpt` trước `bin/dev`. AffiHub kiểm tra health-check của port loopback khi boot và hiện banner nếu worker chưa chạy, không chỉ báo lỗi khi gọi job thất bại.
- MPT cần Python 3.11+; README upstream ghi tối thiểu 4 CPU core/4 GB RAM và khuyến nghị 6–8 core/8 GB. Tạo clip qua cloud API không cần GPU; local Whisper/batch render có thể cần thêm tài nguyên. Gói MPT trong worker/runtime riêng, không cài dependency Python vào Rails.
- VieNeu-TTS chạy như Docker service tự host riêng, cùng kỷ luật với MPT: bind loopback, pin image digest, không công khai port ra LAN/Internet. MPT gọi sang qua `base_url` cấu hình trong `config.toml` ở slot TTS tự host có sẵn (ví dụ `[kokoro]`/`[chatterbox]`), không sửa code MPT.
- App local phải báo khi worker chưa chạy hoặc bị dừng; giữ task ID/trạng thái qua lần restart và reconcile job provider trước retry. Không xóa thư mục job đang xử lý khi app khởi động lại.
- Mọi thao tác retry/claim trạng thái (VideoProject stage, Publication, DriveExport/SheetSync, Scheduler claim auto-publish đến hạn) dùng cùng một pattern: `update_all` có điều kiện `WHERE status = <trạng thái nguồn>` và kiểm tra số dòng bị ảnh hưởng trước khi submit job mới, không đọc-rồi-ghi. Áp dụng thống nhất cho mọi state machine để tránh double-submit khi người dùng bấm Retry nhiều lần, hai worker nhận cùng job, hoặc Scheduler chạy trùng giờ với thao tác duyệt tay.
- Auto-reply không dùng AI sinh nội dung tự do; mặc định là 1 câu trả lời cố định cho mọi bình luận mới mỗi đích, override theo từ khoá là tuỳ chọn thêm — để tránh thêm một nguồn lỗi/nội dung không kiểm soát được chồng lên rủi ro automation đã chấp nhận.
- Scheduler và AutoResponder đều đọc 1 cờ pause chung (`SystemSetting` hoặc tương đương) trước mỗi lần claim job mới; `/pause_auto_publish`/`/pause_auto_reply` từ Telegram chỉ cần set cờ này, có hiệu lực ngay từ job tiếp theo, không cần restart worker.
- Meta API version, MPT commit, provider/model ID, FFmpeg build và preset encode được ghi trong cấu hình/deployment để tái hiện lỗi.
- Caption và metadata platform là text thuần. Markdown chỉ dùng cho tài liệu dự án.

## 7. Ranh giới MVP và việc để sau

### Có trong MVP

- Local app và hướng dẫn tiếng Việt.
- Import video file, lưu link nguồn tùy chọn, ffprobe và hiển thị lỗi đọc file.
- Tự động tải video từ link YouTube/Facebook/TikTok/Instagram bằng `yt-dlp` (best-effort, có cảnh báo ToS/bản quyền, fallback về import thủ công khi lỗi).
- Tìm/crawl nội dung viral qua endpoint khám phá chính thức khi nền tảng có, chọn 1 hoặc nhiều video (kể cả playlist) để tải bằng `yt-dlp`.
- MPT pipeline tạo script, scene prompts và clip AI; có báo giá + xác nhận trước tác vụ trả phí.
- Có bốn lựa chọn AI: ChatGPT/Codex dùng chung kết nối OpenAI đủ quyền, Gemini dùng Gemini API OAuth đủ quyền, Antigravity hiển thị chưa khả dụng theo điều khoản hiện hành. Không có ô nhập API key LLM.
- TTS tiếng Việt, subtitle, editor FFmpeg, preview và render MP4 dọc.
- Cắt, crop/fit, nền mờ/nền khung, brightness, audio, text/overlay và gỡ logo cố định có preview/undo.
- Kết nối nhiều profile/tài khoản trên Facebook, TikTok, Instagram, YouTube; chọn một hoặc nhiều đích và đăng — thủ công (duyệt tay) hoặc tự động theo lịch (auto-publish).
- Tự động trả lời MỌI bình luận/tin nhắn mới bằng câu mặc định cố định, override từ khoá tuỳ chọn (Facebook, Instagram) — TikTok để ngoài MVP vì chưa có API public ổn định cho việc này.
- Kết nối Drive/Sheets và đồng bộ bất đồng bộ, có retry theo từng dịch vụ.
- Telegram bot báo động lỗi/dấu hiệu bị giới hạn và cho dừng khẩn auto-publish/auto-reply qua lệnh từ chat_id allowlist.
- Luồng video local không cần credential và một lần publish thật lên Page/kênh của tài khoản test để hoàn tất POC.

### Chưa có trong MVP

- Scraping bằng Playwright/browser automation để thay thế `yt-dlp` — không chọn hướng này ở bất kỳ nhánh nào (dán link hay crawl).
- Tự trả lời bình luận/tin nhắn trên TikTok (chưa có API public ổn định cho việc này).
- AI tự sinh nội dung trả lời bình luận/tin nhắn (chỉ dùng câu mặc định cố định + override từ khoá tĩnh trong MVP).
- Tách mọi loại vật thể/thay phông gốc, video inpainting logo chuyển động, cam kết xóa logo sạch ở mọi khung hình.
- Cơ chế né nhận diện nội dung, né liên kết Page hoặc đảm bảo tránh cảnh cáo.
- Đồng bộ nhân vật/bối cảnh xuyên nhiều cảnh bằng video model có reference-image (Kling multi-reference, Seedance bản reference). MVP chỉ dùng text-to-video rời từng cảnh; tính năng này cần spike riêng vì đổi schema request (thêm character reference asset) và chưa xác nhận MPT `muapi.py` hiện tại có hỗ trợ tham số reference-image hay không.

## 8. Repo và tài liệu tham khảo trước khi code

| Subsystem | Repo/tài liệu | Cách dùng | Gate kỹ thuật |
|---|---|---|---|
| AI video pipeline | [MoneyPrinterTurbo v1.3.8](https://github.com/harry0703/MoneyPrinterTurbo/tree/v1.3.8), commit `fafec0fbf3142ad5ad7212c2e17996bf247c360a`, MIT | Dùng API script/terms/video, async task, TTS/subtitle/render; chạy Python worker tách Rails | Port đúng API schema/status/error; khóa API vào loopback; test MuAPI quote và trạng thái timeout trước khi bật paid scenes |
| AI scene generation | [MPT MuAPI adapter](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/app/services/muapi.py), [MuAPI pricing](https://muapi.ai/docs/pricing) | Tạo từng clip theo scene prompt; AffiHub lấy tổng estimate trước rồi mới gọi MPT | Giá/model/thời lượng/độ phân giải có thể đổi; không retry mù sau timeout; nếu MuAPI/MPT không trả breakdown giá đủ rõ cho estimate, AffiHub tự tính từ bảng giá MuAPI public thay vì phụ thuộc response của MPT |
| AI scene generation (mở rộng sau MVP) | [MuAPI model catalog](https://muapi.ai/docs/pricing), Kling/Seedance reference-image docs trên MuAPI | Đồng bộ nhân vật/bối cảnh xuyên cảnh bằng model hỗ trợ reference-image, thay cho text-to-video thuần | Xác nhận MPT `muapi.py` có hỗ trợ tham số reference-image trước khi hứa tính năng này ở bất kỳ change nào; đổi schema request nếu cần thêm character reference asset |
| Giọng đọc (TTS) | [VieNeu-TTS](https://github.com/pnnbao97/VieNeu-TTS), Apache-2.0 | Self-host Docker server, trỏ MPT `[kokoro]`/`[chatterbox]` `base_url` sang container này qua transport OpenAI-compatible `_openai_compatible_tts` có sẵn trong MPT | Xác nhận request/response contract `/v1/audio/speech` của VieNeu-TTS khớp đúng với `_openai_compatible_tts` của MPT (model/voice/input/response_format) trước khi wiring, không giả định chỉ vì cùng gắn mác OpenAI-compatible; chốt image digest và giọng mặc định |
| Social URL downloader | [yt-dlp](https://github.com/yt-dlp/yt-dlp), [supported sites](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md) | Download worker riêng (Solid Queue job) gọi `yt-dlp` khi người dùng dán link; best-effort, không phải API chính thức | Pin version `yt-dlp`, cập nhật định kỳ khi site đổi; timeout + giới hạn retry rõ ràng, không retry mù khi bị rate-limit; UI cảnh báo ToS/bản quyền trước khi dùng; không dùng Playwright/browser automation thay thế hoặc bổ sung |
| Edit/render | [FFmpeg](https://github.com/FFmpeg/FFmpeg), [filter docs](https://ffmpeg.org/ffmpeg-filters.html) | Dùng FFmpeg filters cho crop/blur/brightness/audio/delogo/encode | Chốt FFmpeg build/license và kiểm tra chất lượng file mẫu; delogo chỉ hợp vùng tĩnh |
| Facebook Page publish | [Meta Reels API collection](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api), [Postiz provider](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts) | API Meta chính thức là NGUỒN SỰ THẬT duy nhất cho request/response/status/error — Postiz chỉ đối chiếu cách tách method/interface (create/upload/status/publish thành các bước riêng), không dùng để suy ra hành vi API hay error code thật | Ghi Graph API version, Page role/permissions, app role/review và thử trên Page thật |
| TikTok publish | [Content Posting API](https://developers.tiktok.com/docs/en/content-posting-api-get-started), [Display API query video](https://developers.tiktok.com/docs/en/tiktok-api-v2-video-query), [Postiz `tiktok.provider.ts` pinned](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/tiktok.provider.ts) | Tài liệu TikTok chính thức là nguồn sự thật cho contract/status/error; Postiz chỉ tham khảo provider boundary, không dùng error-mapping làm chuẩn | Base review + audit riêng trước public. App chưa audit: `SELF_ONLY`, account private, 5 poster/24h. Creator cap có error signal `spam_risk_too_many_posts`; app active creator cap có `reached_active_user_cap`; API không trả counter/reset time. `PUBLISH_COMPLETE` xác nhận đã đăng; public ID/share URL có thể không có với `SELF_ONLY`. |
| Instagram publish | [Meta Instagram API collection](https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api), [Meta local resumable sample pinned](https://github.com/fbsamples/reels_publishing_apis/blob/7bf98f94e75d841ecc9612c0061881d1d713c6bd/insta_reels_publishing_api_sample/README.md), [Postiz `instagram.provider.ts` pinned](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/instagram.provider.ts) | Chọn Page qua Facebook Login; `/me/accounts` trả Page token + `instagram_business_account`; resumable local upload theo Meta sample; Postiz chỉ tham khảo boundary, không là API truth | MVP chỉ nhận Business account có Page liên kết; scope Facebook Login `pages_show_list`, `pages_read_engagement`, `instagram_basic`, `instagram_content_publish`; đọc `content_publishing_limit` runtime, không hardcode quota. |
| YouTube publish | [YouTube Data API `videos.insert`](https://developers.google.com/youtube/v3/docs/videos/insert), [Postiz `youtube.provider.ts` pinned](https://github.com/gitroomhq/postiz-app/blob/86b3c3dd55d38fbed77fdbf82a21bfc1a169cac6/libraries/nestjs-libraries/src/integrations/social/youtube.provider.ts) | Resumable upload qua API chính thức; Postiz chỉ tham khảo provider boundary, không dùng làm API/error truth | Quota mặc định tách `search.list`, `videos.insert` và other API buckets; Console authoritative. API compliance audit giới hạn public riêng OAuth verification. |
| Nội dung khám phá/trending | YouTube [`search.list`](https://developers.google.com/youtube/v3/docs/search/list) và [`videos.list(chart=mostPopular)`](https://developers.google.com/youtube/v3/docs/videos/list); Instagram Hashtag Search; TikTok Research API | MVP bật YouTube keyword search/chart với nhãn đúng; Instagram API cần Professional Account/Page và quyền phù hợp; TikTok Research API cần hồ sơ nghiên cứu đủ điều kiện/được duyệt | Không scrape discover/for-you; không bật Instagram/TikTok nếu chưa xác minh access tier; tuân thủ YouTube attribution, quota, retention 30 ngày và policy cấm API-client scraping |
| Lịch đăng tự động (Scheduler) | [Postiz `apps/cron`](https://github.com/gitroomhq/postiz-app/tree/main/apps/cron), [`autopost.service.ts`](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/database/prisma/autopost/autopost.service.ts) | Đối chiếu cách Postiz claim bài đến hạn + tránh double-fire; chuyển sang Solid Queue job + `update_all` atomic theo convention Rails của AffiHub, không copy code Postiz | Chỉ đọc logic tham khảo (Postiz AGPL-3.0, không vendor/link trực tiếp); tự viết lại bằng Ruby/Solid Queue |
| Tự động trả lời bình luận | Postiz interface `comment()` trên mọi provider (ví dụ [`facebook.provider.ts`](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts), [`instagram.provider.ts`](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/integrations/social/instagram.provider.ts)) | Đối chiếu cách Postiz gọi API trả lời comment theo từng provider, dùng làm contract cho `AutoResponder` | Chỉ đọc logic tham khảo (AGPL-3.0, không vendor); webhook/poll thật theo tài liệu Facebook/Instagram Graph API hiện hành, không suy từ Postiz |
| Drive/Sheets | [Google API Ruby Client](https://github.com/googleapis/google-api-ruby-client), [Drive uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [Sheets values](https://developers.google.com/workspace/sheets/api/guides/values) | Dùng client/API chính thức, resumable upload, update theo khóa | OAuth consent/scope, refresh expiry, Drive idempotency, Sheets concurrent upsert |
| Giám sát/điều khiển | [Telegram Bot API](https://core.telegram.org/bots/api), [telegram-bot-ruby](https://github.com/atipugin/telegram-bot-ruby) gem (1.4k star, MIT), [Postiz `telegram.provider.ts`](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/integrations/social/telegram.provider.ts) | Dùng gem `telegram-bot-ruby` làm client gửi tin nhắn + nhận update (webhook/long-polling) thay vì tự viết HTTP wrapper; đối chiếu Postiz cho cách gửi tin qua bot token | Allowlist `chat_id` bắt buộc trước khi nhận lệnh điều khiển; bot token mã hoá khi lưu, không log; chốt version gem trong Gemfile.lock |

Trước khi implement subsystem, tạo `docs/reference-analysis/<subsystem>.md` với commit/version, file source đã đọc, API contract, status/error/retry, license, phần tái sử dụng, phần loại bỏ và cách kiểm chứng trong AffiHub. Không chọn repo chỉ dựa trên lượt star hoặc README.

**Postiz là AGPL-3.0, và chỉ có giá trị tham khảo cho KIẾN TRÚC, không phải HÀNH VI API.** Dùng Postiz để đối chiếu: (1) cách tách method/interface cho mỗi publisher (bao nhiêu bước, bước nào async); (2) cách Scheduler claim bài đến hạn (atomic, tránh double-fire); (3) shape của interface `comment()` dùng cho auto-reply. KHÔNG dùng Postiz làm nguồn sự thật cho: request/response schema thật, mã lỗi thật, giới hạn rate limit thật, hay quota thật của bất kỳ nền tảng nào — những thứ đó bắt buộc lấy từ tài liệu chính thức của nền tảng, Postiz là code TypeScript/NestJS của một sản phẩm khác, có thể có bug hoặc cách xử lý lỗi mang tính chủ quan riêng của họ. Không vendor code, không copy nguyên file, không link thư viện Postiz vào AffiHub — mọi publisher/worker trong AffiHub viết lại bằng Ruby theo convention HMVC của repo.

## 9. Điểm mắc cần khóa trước khi triển khai

| Rủi ro/stuck point | Cách xử lý trong spec |
|---|---|
| Nền tảng không có API tải video thống nhất | Dán link → `yt-dlp` tải best-effort trong worker riêng; lỗi/timeout thì fallback về import file thủ công (owner export/download). Người dùng tự chịu rủi ro ToS/bản quyền, UI cảnh báo trước khi dùng. Connector chính thức riêng (Page video do Meta cho phép) chỉ thêm sau proof bằng API/permission chính thức. |
| Meta app chưa được duyệt hoặc profile chưa có Page task | Dùng app role/tester + Page test để POC; checklist setup và nút kiểm tra quyền; người ngoài app role cần access/review phù hợp. |
| Luồng local không dùng credential nên không chọn Page thật | Import/edit/render và tải MP4 hoạt động độc lập; đăng thật chỉ bật khi Meta connection preflight pass. |
| MPT dùng stock footage theo mặc định | UI tách rõ AI tạo cảnh bằng `muapi` và AI script + stock montage; không ghi stock montage là text-to-video. |
| Scene AI có phí theo prompt | Estimate đầy đủ trước video job; người dùng xác nhận; lưu model/cost/job ID; timeout thì reconcile trước retry. |
| MPT endpoint mở mạng hoặc không có auth mặc định | Override loopback + API key; pin release/commit/image; secrets không gửi client. |
| Google/Sheet lỗi | Lưu trạng thái local; đồng bộ sau; retry riêng Drive hoặc Sheet theo idempotency key. |
| Render mới làm sai trạng thái post cũ | Publication gắn với render version bất biến; mỗi version/Page có row key riêng. |
| Nhiều Page hoặc video biến thể dễ lẫn | Mỗi Page có Publication, caption, lỗi và permalink riêng; review hiển thị danh sách trước khi xác nhận. |
| Reels bị từ chối do format | Preflight file và API version trước review; output profile rõ ràng, lỗi có hành động sửa. |
| Google Testing token hết hạn | Báo kết nối lại; không báo đồng bộ thành công giả. |
| Automation (auto-publish, auto-reply, crawl hàng loạt) bị nền tảng coi là spam/bot | Chấp nhận rủi ro khoá tài khoản/Page/kênh bất kỳ lúc nào, không có cơ chế né (đã xác nhận ở mục 1). Giảm thiểu bằng rate-limit phía AffiHub (không gửi dồn dập), log đầy đủ để biết hành động nào gây khoá nếu xảy ra. |
| TikTok Content Posting API cần audit riêng ngoài base review | Chưa audit chỉ đăng `SELF_ONLY` tối đa 5 user/24h; UI hiện rõ trạng thái audit, không hứa đăng công khai trước khi audit pass. |
| Instagram chỉ hỗ trợ Business account, không hỗ trợ Creator/Personal | Preflight kiểm tra account type trước khi cho kết nối; báo rõ cần chuyển sang Business account nếu chưa đúng loại. |
| Auto-reply gửi nhầm/phản cảm do cấu hình sai | Chỉ dùng câu mặc định cố định + override từ khoá tĩnh (không AI sinh tự do); log đầy đủ mọi lần trả lời để người dùng tự rà soát và sửa/tắt. |
| Crawl/tải hàng loạt vi phạm bản quyền ở quy mô lớn hơn 1 link đơn lẻ | Người dùng/chủ dự án tự chịu trách nhiệm quyền sử dụng nội dung tải về, đã xác nhận ở mục 1; AffiHub không thẩm định quyền sở hữu, chỉ cảnh báo trước khi dùng tính năng. |
| Bot token/chat_id lộ → người lạ điều khiển được automation của người khác | Token mã hoá khi lưu, không log; mọi lệnh điều khiển (`/pause_*`, `/resume_*`) chỉ chấp nhận từ `chat_id` trong allowlist cấu hình sẵn, từ chối im lặng (không phản hồi) với chat_id lạ để tránh lộ cấu trúc lệnh. |

## 10. Thứ tự triển khai

1. Đọc Rails code và domain hiện có; viết Porting Note (`docs/reference-analysis/<subsystem>.md`) cho **từng subsystem trong bảng mục 8** trước khi code subsystem đó — không chỉ 4 cái đầu (MPT, Meta Reels, FFmpeg, Google), mà cả TikTok/Instagram/YouTube publish, yt-dlp, VieNeu-TTS, Scheduler, AutoResponder, Telegram khi tới lượt subsystem đó.
2. Làm spike Meta sớm: cấu hình app role/Page test, upload một MP4 tối giản, poll processing, publish thật, lưu post ID/permalink; xác định API version và quyền thực tế. Trong cùng spike, thử route lấy `Video.source` cho một video thuộc Page được quản lý; chỉ thêm connector nếu đọc được ID, lấy file và kiểm chứng quyền theo tài liệu hiện hành.
3. Làm local video slice: import file → ffprobe → FFmpeg crop/blur/brightness/delogo → render/preview/tải file.
4. Spike VieNeu-TTS: xác nhận thật request/response `/v1/audio/speech` khớp với `_openai_compatible_tts` của MPT trước khi coi đây là kiến trúc khoá — nếu không khớp, quyết định lại giữa patch nhỏ cho MPT hoặc chuyển fallback (Edge TTS/Azure) thành lựa chọn chính.
5. Tích hợp MPT pinned commit: chọn kết nối LLM đã đăng nhập và model được cấp quyền → script → user review → terms → MuAPI quote → confirm → generation → poll → preview. Xác minh ChatGPT/Codex qua Responses API, Gemini qua Gemini API OAuth và đường thay thế LLM API key của MPT; Antigravity chỉ bật khi Google có contract cho bên thứ ba. Chạy ít nhất một file tiếng Việt và ghi chi phí/thời gian.
6. Viết `MetaGraphPublisher` cụ thể theo API contract đã spike ở bước 2 — **chưa trừu tượng hoá `PublisherResolver`** ở bước này, chỉ 1 publisher cụ thể; chặn publish nếu Page preflight hoặc file preflight chưa đạt.
7. Thêm Download worker (`yt-dlp`) + Discovery worker (trending chính thức); ghép vào nhánh nguồn video, test cả thành công và lỗi/fallback; áp giới hạn tần suất job/giờ (mục 2).
8. Spike TikTok/Instagram/YouTube publish: kết nối OAuth, thử đăng 1 video tối giản mỗi nền tảng, xác nhận review/audit cần gì thực tế. TikTok: xác nhận rõ giới hạn SELF_ONLY khi chưa audit (tính là pass MVP, mục 4.1.b).
9. **Chỉ sau khi có đủ 4 publisher cụ thể (bước 6 + 8), mới trừu tượng hoá thành `PublisherResolver`** — tránh thiết kế interface chung khi mới thấy 1 case. Thêm Scheduler cho auto-publish: claim atomic, giới hạn tần suất + jitter (mục 2), test trường hợp trùng giờ với duyệt tay.
10. Thêm AutoResponder cho Facebook/Instagram (chỉ bình luận, không DM — mục 4.5.b): webhook/poll, gửi câu mặc định/override, ghi log; không làm cho TikTok.
11. Thêm Drive/Sheets side jobs (trigger lúc duyệt, tạo subfolder riêng — mục 4.6); kiểm tra retry riêng, timeout reconciliation và khóa chống tạo hàng/file trùng.
12. Thêm Telegram bot: cảnh báo + lệnh `/pause_*`/`/resume_*`/`/status`, allowlist chat_id; nối vào mọi điểm lỗi/cảnh báo đã có ở các bước trên (worker down, publish Failed/Unknown, token hết hạn).
13. Ghép e2e: source (import/link/crawl/AI) → edit → render → preflight → review/auto-publish → publish đa nền tảng; xác minh Drive/Sheet, AutoResponder và Telegram đều hoạt động độc lập.

## 11. Điều kiện nghiệm thu MVP

- Từ giao diện tiếng Việt, người dùng có thể import video, chỉnh, render preview và tải MP4 mà không cần credential ngoài.
- Có thể tạo project từ file, từ link (tự tải bằng `yt-dlp`), hoặc từ kết quả tìm/crawl nội dung viral (qua endpoint khám phá chính thức khi nền tảng có); lỗi tải fallback về import thủ công.
- Có thể tạo video AI bằng MPT v1.3.8 pinned commit: script và scene prompts sửa được; trước khi tạo clip AI hiển thị báo giá đầy đủ và cần xác nhận.
- Có thể kết nối ChatGPT/Codex đủ quyền hoặc Gemini API OAuth đã xác minh, chọn model và tạo script/scene không nhập API key LLM; khóa bước này khi quyền/hạn mức hết hoặc bị thu hồi. Antigravity hiển thị chưa khả dụng và không được nghiệm thu như kết nối hoạt động khi Google chưa cho phép.
- Job MPT lưu external task ID, trạng thái, model và lỗi; timeout không tự gửi lại tác vụ có thể đã tính tiền.
- Editor có trim, vertical crop/fit, nền khung, brightness, text/audio và logo vùng tĩnh preview/undo; file nguồn không bị ghi đè.
- Gỡ logo cố định được nghiệm thu bằng bộ 3 clip mẫu nền tĩnh, review thủ công theo checklist pass/fail (vùng xoá không để lại artifact rõ ở preview); không dùng metric tự động, không cam kết cho nền động/phức tạp.
- Render tạo version mới bất biến; preflight hiển thị thông số và kiểm tra trước khi mở nút publish — theo giới hạn riêng từng nền tảng đích.
- Kết nối được ít nhất: Facebook Page (app role/tester), TikTok (base review, đăng SELF_ONLY nếu chưa audit), Instagram (Business account), YouTube (OAuth kênh); mỗi nền tảng kiểm tra quyền trước khi cho publish.
- Một video thật được đăng thành công (API xác nhận trạng thái cuối, không suy từ "job chạy xong") lên ít nhất 1 đích mỗi nền tảng đã kết nối; DB lưu trạng thái cuối, đích, render version, provider ID, permalink/video ID và thời điểm cho từng Publication.
- Auto-publish: đặt lịch cho 1 Publication, Scheduler tự đăng đúng giờ không cần người bấm xác nhận; trạng thái cuối vẫn chỉ ghi khi nền tảng xác nhận.
- Auto-reply: cấu hình câu trả lời mặc định cho ít nhất 1 đích Facebook hoặc Instagram, mọi bình luận/tin nhắn mới nhận được trả lời tự động, có log lại đầy đủ.
- Telegram bot: nhận được cảnh báo thật khi 1 Publication rơi vào `Failed`/`OutcomeUnknown` hoặc worker down; lệnh `/pause_auto_publish` và `/pause_auto_reply` có hiệu lực thật (Scheduler/AutoResponder dừng claim job mới ngay sau lệnh); chat_id ngoài allowlist bị từ chối.
- `Published` chỉ xuất hiện khi nền tảng xác nhận trạng thái cuối, ở mọi nền tảng; trường hợp chưa rõ được đối soát trước retry.
- Khi người dùng duyệt (bấm Đăng), Drive tự tạo 1 subfolder riêng cho video đó và upload MP4 theo `asset_export_key`; Sheets có một hàng cho mỗi render version/đích theo `sheet_row_key`, ghi cả tóm tắt/caption (`video_title`) và link subfolder; timeout/retry không tạo bản trùng trong các kịch bản đã xác định.
- Lỗi Google sync không làm mất project, không chặn review/publish và không gọi lại publisher của bất kỳ nền tảng nào.
- Luồng video local không cần credential, không gọi API thật của nền tảng nào và không tạo ID/permalink giả.

## 12. Tài liệu nguồn chính

- **YouTube:** [Owner download trong YouTube Studio/Takeout](https://support.google.com/youtube/answer/56100), [YouTube Data API Videos](https://developers.google.com/youtube/v3/docs/videos), [videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert), [videos.list (trending)](https://developers.google.com/youtube/v3/docs/videos/list), [YouTube API policies](https://developers.google.com/youtube/terms/developer-policies).
- **Facebook/Meta:** [Page Videos v26](https://developers.facebook.com/docs/graph-api/reference/page/videos/), [Video node v26](https://developers.facebook.com/docs/graph-api/reference/video/), [Graph API access levels](https://developers.facebook.com/docs/graph-api/overview/access-levels/), [Meta Reels collection](https://www.postman.com/meta/facebook/documentation/r56bjfd/facebook-api).
- **Instagram:** [Instagram Platform API](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/), [IG User media](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media/), [Instagram Content Publishing](https://developers.facebook.com/docs/instagram-platform/content-publishing/).
- **TikTok:** [Display API](https://developers.tiktok.com/docs/en/display-api-overview), [Data Portability regional support](https://developers.tiktok.com/products/data-portability-api), [Data Portability application](https://developers.tiktok.com/docs/en/data-portability-api-get-started), [TikTok video download help](https://support.tiktok.com/en/using-tiktok/exploring-videos/video-downloads), [Content Posting API](https://developers.tiktok.com/doc/content-posting-api-get-started/).
- **AI video:** [MoneyPrinterTurbo v1.3.8](https://github.com/harry0703/MoneyPrinterTurbo/tree/v1.3.8), [MPT README](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/README-en.md), [MPT voice list](https://github.com/harry0703/MoneyPrinterTurbo/blob/v1.3.8/docs/voice-list.txt), [MuAPI pricing](https://muapi.ai/docs/pricing), [Azure Vietnamese voices](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=stt).
- **TTS:** [VieNeu-TTS](https://github.com/pnnbao97/VieNeu-TTS) (Apache-2.0, OpenAI-compatible `/v1/audio/speech`, self-host Docker).
- **Media:** [FFmpeg filters](https://ffmpeg.org/ffmpeg-filters.html), [FFmpeg licensing](https://ffmpeg.org/legal.html), [RobustVideoMatting](https://github.com/PeterL1n/RobustVideoMatting), [ProPainter](https://github.com/sczhou/ProPainter).
- **Google:** [Drive upload](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [Drive `appProperties`](https://developers.google.com/workspace/drive/api/guides/properties), [Sheets values API](https://developers.google.com/workspace/sheets/api/guides/values), [OAuth best practices](https://developers.google.com/identity/protocols/oauth2/resources/best-practices), [Google API Ruby Client](https://github.com/googleapis/google-api-ruby-client).
- **Giám sát:** [Telegram Bot API](https://core.telegram.org/bots/api), [telegram-bot-ruby](https://github.com/atipugin/telegram-bot-ruby).
- **Đa nền tảng (đối chiếu provider/scheduler/comment reply):** [Postiz](https://github.com/gitroomhq/postiz-app) — AGPL-3.0, chỉ đọc tham khảo, không vendor.

## 13. Cập nhật bổ sung: luồng editor, audit một lần và giới hạn tích hợp (2026-10-05)

Phần này bổ sung cách hiểu và điều kiện nghiệm thu cho các luồng đã mô tả ở mục 1–12. Toàn bộ nội dung cũ được giữ nguyên. Khi chi tiết triển khai hoặc điều kiện sẵn sàng trong phần cũ chưa rõ hay mâu thuẫn với phần bổ sung này, dùng mục 13 làm căn cứ triển khai. Mỗi connector được implement theo luồng API chính thức của nền tảng và dùng cấu hình production tương ứng.

### 13.1. Nguồn video: tải về và import đều đi vào cùng editor

- Giữ cả hai cách bắt đầu: dán URL từ nguồn đã cấu hình để tạo job tải nền, hoặc chọn MP4/MOV từ máy. Cả hai tạo Source Asset trong cùng project, chạy `ffprobe`, rồi mở trong editor. Video đã có sẵn từ source file gốc đi thẳng vào import local.
- Mỗi Source Asset giữ provenance của nền tảng nguồn. URL từ nguồn được cấu hình, kể cả YouTube, được thử tải bằng `yt-dlp` trong worker sau khi người dùng thấy cảnh báo quyền sử dụng/Điều khoản dịch vụ; nếu tải lỗi thì hiển thị nguyên nhân và hướng dẫn import file. Discovery chỉ dùng endpoint chính thức để lấy metadata/preview có attribution; kết quả YouTube chỉ được đưa sang job `yt-dlp` sau khi người dùng chọn. File người dùng đã xuất qua YouTube Studio/Takeout được import trực tiếp và giữ provenance, không gọi downloader cho file đó. [YouTube Developer Policies](https://developers.google.com/youtube/terms/developer-policies).

### 13.2. UI editor và so sánh với video nguồn

- Sau khi chọn Source Asset, người dùng chọn Page/kênh đích cho từng Publication. Editor luôn phân biệt preview video nguồn và preview Render Version sẽ xuất/đăng; mọi thay đổi tạo version mới, không ghi đè file nguồn hay version đã đăng.
- Timeline hỗ trợ trim/chia đoạn theo timecode và frame, đặt điểm đầu/cuối trong video nguồn, xem trước đoạn đã chọn và tạo clip ngắn. Nghiệm thu phải dựng được đoạn dài đúng 1 giây và 2 giây từ một video nguồn dài hơn, đồng thời giữ đúng điểm cắt và âm thanh tương ứng.
- Có chế độ đối chiếu video nguồn với bản render bằng các khung hình lấy mẫu mỗi 1 giây hoặc 2 giây. Hiển thị timecode và hai khung cạnh nhau để người dùng rà soát crop, nền, chữ và logo; đây là bằng chứng hỗ trợ kiểm tra hình ảnh, không phải phán quyết tự động về bản quyền hay chính sách nền tảng.
- Có điều khiển **tốc độ clip đầu ra** riêng với tốc độ phát để xem preview. Chọn 2× là retime clip xuất ra, không chỉ tua preview. Nghiệm thu tối thiểu ở 1× và 2×; preview và file render phải cùng áp dụng tốc độ clip. Mặc định audio đi cùng clip được time-stretch để khớp thời lượng và giữ cao độ; người dùng có thể tắt audio nếu không muốn giữ.
- UI cho phép chọn nền khung màu, ảnh, video hoặc nền làm mờ từ video nguồn như phạm vi đã nêu ở mục 4.4; thêm logo overlay. Preview phải thể hiện vị trí, kích thước và độ trong suốt của logo cũng như nền; render phải khớp preview. Đây là thêm lớp đồ họa/nền, không phải cam kết xóa watermark/logo của bên khác.

### 13.3. Nút “Kiểm tra toàn bộ” (audit/preflight)

Nút này chạy một lượt kiểm tra không phá huỷ trên toàn bộ project hiện tại: mọi Source Asset, Render Version được các Publication tham chiếu, mọi Publication/đích đã chọn và các dịch vụ đang bật. Nó không đăng/tải bài, không tạo tác vụ AI có phí, không sửa nội dung và không coi thao tác kiểm tra là xác nhận đăng. Có thể gọi các API đọc trạng thái connector/tài khoản cần thiết; kết quả phải ghi thời điểm kiểm tra để người dùng biết trạng thái có thể đã đổi. Một đích chưa được chọn không được tính là đã audit; các integration chưa bật hiện riêng là “Chưa cấu hình”.

Một lượt audit hiển thị từng mục theo trạng thái **Đạt / Cảnh báo / Chặn / Chưa thể kiểm tra**, kèm đích liên quan, lý do cụ thể và hành động khắc phục. Phạm vi tối thiểu:

- **Nguồn và timeline:** file còn đọc được; stream video/audio, thời lượng, kích thước và metadata; điểm cắt nằm trong phạm vi nguồn; asset nền/logo/phụ đề được tham chiếu còn tồn tại.
- **Render:** version được chọn tồn tại; codec/container, tỷ lệ khung hình, kích thước, thời lượng, frame rate và audio được đo từ file đầu ra; đối chiếu điều kiện hiện hành riêng cho từng đích; tạo dải khung hình so sánh nguồn/bản render ở bước 13.2. Nếu có Publication TikTok, kiểm tra version đó không có logo/watermark/promotional overlay do AffiHub thêm.
- **Connector và đích đăng:** kiểm tra kết nối OAuth, tài khoản/Page/kênh được chọn, token, app configuration và trạng thái API bằng request đọc tương ứng.
- **Đường truyền media:** xác nhận publisher chuyển đúng Render Version qua protocol của từng API. Instagram Reels và TikTok dùng direct file upload; YouTube và Facebook dùng resumable/session upload.
- **Dịch vụ và lịch:** trạng thái FFmpeg/worker và dịch vụ AI được chọn; báo giá AI phải kèm nguồn/thời điểm và được xem là estimate, không phải quote được giữ chỗ. Nếu app/worker local đang tắt thì lịch local không thể chạy; lịch quá hạn khi máy/worker ngừng cần được đánh dấu bỏ lỡ và báo người dùng để xử lý, không tự đăng bù âm thầm.
- **Tích hợp phụ:** Drive, Sheets và Telegram được kiểm tra riêng nếu người dùng đã bật; lỗi các dịch vụ này không đổi trạng thái publisher hoặc gọi đăng lại.

Audit tổng thể chỉ báo **Sẵn sàng cho các đích đã chọn** khi mọi điều kiện bắt buộc của từng đích đều là **Đạt**; lỗi cấu hình hoặc lỗi API chỉ ảnh hưởng trạng thái của connector tương ứng. Đích khác, editor và local export vẫn hoạt động độc lập. Nếu chưa chọn đích, báo rõ audit chỉ xác nhận khả năng xử lý/xuất local, không xác nhận khả năng đăng. Audit không thay thế việc nền tảng xét duyệt nội dung sau khi nhận bài.

### 13.4. Hành vi khi connector hoặc dịch vụ ngoài lỗi

| Sự kiện | Hành vi bắt buộc của sản phẩm |
|---|---|
| API trả lỗi cho một connector | Hiển thị lỗi và bước khắc phục trên đúng connector; không ghi nhận publish thành công. Import, edit, render, export local và các connector khác tiếp tục độc lập. |
| URL source không tải được | Hiển thị nguyên nhân và mở nút import file; editor vẫn hoạt động. |
| MuAPI/LLM/TTS trả lỗi | Dừng riêng job tạo nội dung phụ thuộc provider đó; video import sẵn vẫn edit/render/export được nếu worker local chạy. |
| Google Drive/Sheets trả lỗi | Giữ dữ liệu authoritative trong Rails DB, hiển thị lỗi sync và không gọi lại publisher. |
| Telegram Bot API trả lỗi | Hiển thị lỗi thông báo Telegram; dashboard và điều khiển local vẫn hoạt động. |
| FFmpeg hoặc worker render local dừng | Chặn render với lỗi chẩn đoán cụ thể; giữ nguyên project, source và các render version đã có. |
| Máy/app/worker local tắt vào giờ đăng | Không hứa lịch vẫn chạy. Khi khởi động lại, ghi nhận publication bị lỡ để người dùng quyết định lên lịch lại hoặc đăng tay; không tự đăng muộn ngoài ý muốn. |
| Instagram upload | Dùng resumable file upload tới URI Meta (`rupload.facebook.com`); không cần public media URL, relay hay Drive public link. |

### 13.5. Các điều kiện API cần thể hiện trong audit và nghiệm thu

- **TikTok — Direct Post:** connector dùng Content Posting API theo flow chuẩn: OAuth → gọi `creator_info` ngay trước đăng → người dùng chọn privacy/caption/interaction settings và xác nhận đúng video → khởi tạo Direct Post → tải file bằng `FILE_UPLOAD` theo chunk → poll trạng thái tới kết quả cuối. Unaudited app giới hạn 5 poster khác nhau/24 giờ, yêu cầu poster account ở chế độ private và ép bài `SELF_ONLY`; production app review/setup là hạng mục riêng. TikTok không trả số cap/số bài còn lại: `creator_info/query` báo `spam_risk_too_many_posts` khi cap creator đã chạm, còn `reached_active_user_cap` báo quota active creator của app đã chạm. Response thường không có usage/cap/reset time; nếu không có error cap thì hiển thị `Chưa thể kiểm tra số bài còn lại`, không ước lượng từ mức “thường khoảng 15”. AffiHub vẫn đếm local 5 poster chưa audit. Privacy không có mặc định; interaction bị creator tắt phải khóa; Commercial Content mặc định tắt; branded content không dùng được với `SELF_ONLY`; AI-generated gửi `is_aigc=true` theo consent; không thêm logo/watermark/promotional overlay. TikTok review cũng yêu cầu use case phục vụ creator đăng nội dung gốc, không phải công cụ nội bộ đăng chéo nội dung tùy ý. [Content Sharing Guidelines](https://developers.tiktok.com/docs/en/content-sharing-guidelines), [App Review Guidelines](https://developers.tiktok.com/docs/en/app-review-guidelines), [Creator Info](https://developers.tiktok.com/docs/en/content-posting-api-reference-query-creator-info), [Direct Post](https://developers.tiktok.com/docs/en/content-posting-api-reference-direct-post), [Media Transfer Guide](https://developers.tiktok.com/docs/en/content-posting-api-media-transfer-guide).
- **Instagram Reels:** chốt MVP trên Instagram API with Facebook Login: Facebook Login for Business OAuth với `pages_show_list`, `pages_read_engagement`, `instagram_basic`, `instagram_content_publish`; lấy Pages qua `/me/accounts`, người dùng chọn Page và connector lưu Page Access Token cùng `instagram_business_account` ID. Product chỉ nhận Business account có Page liên kết dù Meta collection mô tả publishing cho Professional Business và Creator. Upload flow là tạo container `upload_type=resumable` → tải binary tới `rupload.facebook.com` → poll upload status → gọi `media_publish` → lưu media ID/permalink. Trước khi publish, gọi `content_publishing_limit` và dùng quota runtime, không hardcode số cũ. Các trang Meta canonical về endpoint/schema và access tier cần được xác minh lại vì lượt tra cứu 2026-10-08 trả HTTP 429. Direct file upload không cần `video_url` public hay relay; Stories không nằm trong MVP. [Meta official Instagram API collection](https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api), [Meta Reels resumable upload sample pinned at `7bf98f94e75d841ecc9612c0061881d1d713c6bd`](https://github.com/fbsamples/reels_publishing_apis/blob/7bf98f94e75d841ecc9612c0061881d1d713c6bd/insta_reels_publishing_api_sample/README.md).
- **YouTube:** dùng Google OAuth để chọn channel rồi `videos.insert` với resumable upload, title/description/tags, `privacyStatus` do người dùng chọn (`private`/`unlisted`/`public`), audience (`selfDeclaredMadeForKids`) và `containsSyntheticMedia` khi phù hợp. Giao diện khai báo audience/synthetic media và hiển thị upload warning theo Terms ngay cạnh nút gửi. API project qua compliance audit là cấu hình production để upload public. `search.list` là keyword search; `videos.list(chart=mostPopular)` là chart theo region/category. Quota default hiện tách bucket: 100 `search.list` calls/ngày, 100 `videos.insert` calls/ngày (1 unit/call trong bucket Video Uploads), và 10.000 units/ngày cho methods khác; Google Cloud Console mới là nguồn usage authoritative. AffiHub chỉ đếm call của chính nó và không biết usage của app khác dùng chung project. OAuth app verification và API compliance audit là hai gate riêng. [videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert), [search.list](https://developers.google.com/youtube/v3/docs/search/list), [quota audit](https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits), [quota revision history](https://developers.google.com/youtube/v3/revision_history), [YouTube API Terms](https://developers.google.com/youtube/terms/api-services-terms-of-service).
- **Facebook Pages/Reels:** OAuth Page selection; render version local được đưa bằng Pages/Reels publishing API file-upload session, poll tới processing-complete, publish đúng Page rồi lưu video ID/permalink. [Meta Reels publishing API sample](https://github.com/fbsamples/reels_publishing_apis).
- **Chi phí AI:** lấy model catalog; với MuAPI model có dynamic pricing, gọi `estimate-cost` bằng chính input/duration/resolution sẽ gửi để ra USD estimate. Cộng estimate từng scene/provider, hiển thị currency, model, source và timestamp; trước job trả phí vẫn cần người dùng xác nhận như mục 2 và 4.3. Estimate không giữ giá/job; lưu cost thực tế trả về sau mỗi request. Timeout không rõ provider đã nhận job phải tiếp tục đối soát, không tự gửi lại. [MuAPI Pricing](https://muapi.ai/docs/pricing).

### 13.6. Bổ sung điều kiện nghiệm thu UI và audit

- Link tải thành công và file import local đều mở được trong cùng editor; lỗi link hiện fallback rõ ràng và không chặn file local.
- Có thể trim/render đoạn 1 giây và 2 giây; retime clip xuất ra 1×/2× (khác với tua preview); nền màu/ảnh/video/blur và logo hiển thị nhất quán giữa preview và MP4 tải xuống. Khung so sánh lấy mẫu nguồn/render ở nhịp 1 giây hoặc 2 giây và hiển thị timecode.
- Một lần bấm “Kiểm tra toàn bộ” tạo báo cáo cho project, render version và các đích đã chọn; báo connector/API error, media-transfer, thông số video và trạng thái worker. Lượt audit không publish và không tạo job tính phí.
- Lỗi API của một connector chỉ ảnh hưởng connector đó; import, edit, render, export local và các connector khác tiếp tục độc lập.
- Local export và publish từng nền tảng là các trạng thái nghiệm thu riêng; local export không được hiển thị như một post đã đăng.
- Mỗi platform connector có một publish smoke flow riêng trên tài khoản test: OAuth/channel selection → media upload → processing status → publish → lưu các ID/permalink mà provider trả cùng thời điểm xác nhận; UI chỉ hiện `Published` sau xác nhận cuối từ API. Ngoại lệ TikTok: `PUBLISH_COMPLETE` đủ xác nhận đã đăng; `publicaly_available_post_id` chỉ có cho bài công khai đã qua moderation. Khi có public ID và scope `video.list`, lấy `share_url` qua `video/query`; với `SELF_ONLY` hoặc khi API không trả liên kết, giữ ID/permalink trống và không tự ghép URL.
- TikTok preview/consent kiểm tra trên đúng Render Version và creator settings; Instagram publish smoke dùng local resumable upload; YouTube smoke xác nhận privacy/audience selection và resumable upload; Facebook smoke xác nhận upload processing và Page đích.
- TikTok acceptance phải exercise `PUBLIC_TO_EVERYONE` qua production configuration; `SELF_ONLY`-only development run không thay thế kiểm tra Direct Post public.

### 13.7. Làm rõ số liệu và phạm vi nghiệm thu

- **Tải video:** giới hạn hiện có là tối đa 10 lần bắt đầu tải trong cửa sổ trượt 60 phút cho mỗi cài đặt AffiHub local, tính gộp job link và discovery. Khi chạm ngưỡng, job mới ở trạng thái chờ giới hạn và tự đủ điều kiện chạy khi cửa sổ trượt cho phép; không mất yêu cầu và không ảnh hưởng import file. Lượt retry có gọi downloader cũng tính là một lần bắt đầu tải.
- **Đăng bài:** giới hạn nội bộ hiện có là tối đa 5 Publication mới trong cửa sổ trượt 24 giờ cho mỗi Page/kênh đích, gộp đăng tay và theo lịch. Một Publication được tính một lần khi request publish đầu tiên được gửi; upload chunks, poll trạng thái, reconciliation và retry cùng một Publication ID không tạo thêm lượt. Publication mới do người dùng tạo là lượt mới. Publication ở `OutcomeUnknown` vẫn chiếm lượt và bị chặn retry cho tới khi được giải quyết. Hiển thị số lượt đã dùng và thời điểm mở lượt kế tiếp. Đây là giới hạn AffiHub, không phải hạn mức nền tảng cam kết.
- **Jitter và múi giờ:** lịch không được đăng trước thời điểm người dùng chọn; jitter hiện tại là độ trễ ngẫu nhiên từ 5 đến 30 phút sau giờ hẹn. Mỗi lịch hiển thị múi giờ đang dùng; mặc định lấy múi giờ máy local khi tạo lịch và lưu thời điểm chuẩn hoá để xử lý nhất quán sau restart.
- **Auto-reply:** trong MVP, “bình luận” nghĩa là comment công khai trên Facebook/Instagram. DM, Messenger và inbox không nằm trong điều kiện nghiệm thu MVP. Luồng comment dùng webhook/poll và API reply chính thức của từng connector.
- **Google:** Drive/Sheets là tùy chọn. Các điều kiện upload/upsert chỉ áp dụng khi người dùng bật và kết nối Google; nếu chưa cấu hình, kết quả là “Bỏ qua — chưa bật”, không phải lỗi toàn MVP.
- **Connector:** mỗi nền tảng được nghiệm thu riêng theo luồng OAuth, chọn đích và publish xác nhận cuối. Connector chưa được dùng không chặn import/edit/render/export local; không tính trạng thái local export là publish platform.
- **Giá trị cho khách hàng:** spec hiện chưa có persona đã xác nhận, baseline thời gian/chi phí trước khi dùng, hay mục tiêu ROI do khách hàng cung cấp. Không tự điền số tiết kiệm hoặc cam kết năng suất. Trong pilot ghi cho từng video: nguồn, thời gian từ import đến export, thời gian render, số lần sửa thủ công, chi phí dịch vụ ngoài và trạng thái publish từng đích; chủ dự án dùng số liệu đó để chốt ngưỡng lợi ích trước khi coi hiệu quả kinh doanh là nghiệm thu.
- **Bộ mẫu tải link:** tiêu chí “link tải thành công” dùng URL mẫu ghi rõ nguồn/nền tảng/định dạng. URL YouTube và URL từ kết quả YouTube đã được người dùng chọn đều chạy qua `yt-dlp`; discovery vẫn lấy metadata từ API chính thức và giữ attribution. Kiểm tra cả lỗi extractor/rate limit, fallback import thủ công và không retry mù khi bị chặn.
- **Ngân sách AI:** trước job trả phí, breakdown phải phân biệt khoản MuAPI, LLM, stock asset, TTS/fallback và khoản nào không lấy được giá; ghi currency, nguồn và thời điểm estimate. Với LLM dùng quyền gói ChatGPT, hiển thị “theo hạn mức gói, không có báo giá tiền từng lượt”, tách khỏi tổng tiền dịch vụ tính theo lượt và không ghi số 0 giả. Chỉ cho gọi LLM khi quyền đang hợp lệ; thiếu giá của khoản dịch vụ bắt buộc tính theo lượt vẫn chặn job trả phí. Người dùng đặt trần tiền cho job. Nếu tổng estimate vượt trần hoặc còn khoản phí bắt buộc chưa xác định, chặn gửi job cho tới khi người dùng cập nhật trần/giá và xác nhận lại; estimate không bảo đảm giá cuối nếu provider thay đổi giá.
- **Pilot go/no-go:** trước khi bắt đầu pilot với khách hàng, ghi persona, cách làm hiện tại để so sánh và ít nhất một mục tiêu đo được (ví dụ thời gian đến MP4 sẵn sàng hoặc tổng chi phí/video) cùng ngưỡng đạt do khách hàng chốt. Trước khi có mục tiêu này chỉ nghiệm thu kỹ thuật, không tuyên bố pilot chứng minh lợi ích kinh doanh.

### 13.8. Gate kỹ thuật để không mắc kẹt hoặc tạo tác vụ trùng

- **Docker và loopback:** `127.0.0.1` chỉ dùng cho dịch vụ chạy cùng network namespace. Khi Rails, MPT hoặc TTS ở container riêng, cấu hình dùng DNS/service name trong Docker network riêng và không publish cổng dịch vụ ra LAN/Internet; môi trường chạy native có thể dùng loopback. Health check phải kiểm tra đúng địa chỉ từ nơi Rails/worker gọi tới.
- **MPT state:** trước khi dùng AI job trả phí, xác minh task state/queue của MPT còn tồn tại qua restart bằng cấu hình persistence đã chọn. Nếu upstream đang dùng state in-memory hoặc chưa thể đối soát sau restart, audit báo blocker cho độ tin cậy của nhánh AI; không tự gửi lại job chỉ vì không thấy task trong bộ nhớ.
- **Timeout không có provider ID:** nếu request đã có thể tới nhà cung cấp nhưng AffiHub chưa nhận/lưu ID, giữ trạng thái `OutcomeUnknown`, thử đối soát bằng API/correlation dữ liệu được provider hỗ trợ; nếu không có lookup, giao diện cho người dùng mở đích kiểm tra và xác nhận một trong ba kết quả: “đã xảy ra” (lưu URL/reference và bằng chứng kiểm tra), “chắc chắn chưa xảy ra” (cho phép retry có audit log và xác nhận rủi ro), hoặc “vẫn chưa rõ” (tiếp tục chặn retry). Xác nhận thủ công được lưu thành `ManualOutcomeConfirmed`, không tự đổi thành `Published`; `Published` vẫn chỉ ghi khi API/nền tảng xác nhận cuối. Áp dụng tương tự khi auto-reply timeout; xác nhận thủ công không có bằng chứng API vẫn giữ trạng thái riêng và không gửi lại tự động.
- **Worker bị dừng:** job đang chạy cần lease/heartbeat, fencing/claim token và sweeper. Worker phải gia hạn lease khi làm việc và xác minh vẫn sở hữu claim ngay trước mỗi side effect; worker cũ mất claim không được tiếp tục bước publish/upload/reply tiếp theo. Nếu request ngoài đã được gửi trước khi lease mất hiệu lực, worker mới phải đợi cửa sổ timeout rồi đối soát; không gửi song song chỉ vì lease hết hạn. Audit báo worker/lease quá hạn thay vì để job ở `Rendering`/`Uploading`/`Generating` vô thời hạn.
- **Auto-reply dedupe:** tạo khóa idempotency duy nhất theo tài khoản đích và comment/event ID. Webhook/poll lặp không tạo reply thứ hai; nếu API gửi reply nhưng response timeout, giữ trạng thái chưa rõ và đối soát trước khi gửi lại.
- **Drive folder sau timeout:** folder cần khóa idempotency riêng theo video/project và được tìm lại bằng metadata trước khi tạo lại. Việc API tạo folder thành công nhưng response mất không được làm sinh folder thứ hai khi retry; lỗi Drive vẫn không gọi lại publisher.
- **Repo tham khảo:** repo ngoài là nguồn đọc để port, không phải dependency runtime (ngoại trừ service upstream được chốt rõ như MPT). Với tài liệu/repo dùng branch di động như Postiz `main`, Porting Note phải ghi SHA/commit, ngày đọc và file đã đối chiếu để lần implement sau biết chính xác luồng tham khảo nào đã được review.
- **Mô hình chạy MVP:** AffiHub cài và chạy trên một máy tính local do chủ dự án vận hành; lịch chạy khi máy thức, có mạng, app và worker hoạt động. Docker Compose dùng service DNS nội bộ như trên. OAuth callback local và platform file-upload sessions được smoke test trong triển khai. Instagram resumable upload và TikTok `FILE_UPLOAD` không cần media relay public. Nếu chuyển sang hosted, cần rà soát lưu trữ video/token, chi phí và SLA.

### 13.9. Kết quả xác minh tài liệu và phạm vi chưa thể chạy thử

Các luồng dưới đây đã được đối chiếu với tài liệu API chính thức và repository tham khảo được pin; đây là contract để implement, không phải tuyên bố rằng code tích hợp đã chạy. `affihub/docs/architecture/OVERVIEW.md` ghi nhận Rails scaffold cùng các luồng project, source, editor/render và Meta OAuth/Page selection đã có trong code. Nhiều tích hợp ngoài vẫn đang được triển khai; tài liệu này và OpenSpec là contract sản phẩm, không phải tuyên bố các luồng tích hợp đã chạy.

- **Đã xác minh trên docs:** TikTok Direct Post có `FILE_UPLOAD` local, chunk transfer, creator-info/consent UX và status polling; Instagram Reels sample của Meta xác nhận resumable local-file upload qua `rupload.facebook.com`; YouTube có resumable `videos.insert`, public upload dùng API project đã audit và source-media policy áp dụng với bản sao audiovisual YouTube; Google Drive hỗ trợ resumable `files.create`; Telegram Bot API cung cấp `sendMessage`; FFmpeg có filter cho trim/retime/audio tempo. [Google Drive upload](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [Telegram `sendMessage`](https://core.telegram.org/bots/api#sendmessage), [FFmpeg filters](https://ffmpeg.org/ffmpeg-filters.html).
- **Repo tham khảo và dependency:** [MoneyPrinterTurbo pinned source](https://github.com/harry0703/MoneyPrinterTurbo/tree/fafec0fbf3142ad5ad7212c2e17996bf247c360a) là service/reference riêng cho nhánh AI video; Rails DB vẫn authoritative và MPT task/state persistence phải cấu hình/kiểm tra. [Postiz provider](https://github.com/gitroomhq/postiz-app/blob/main/libraries/nestjs-libraries/src/integrations/social/facebook.provider.ts) chỉ dùng tham khảo provider boundary, không thêm làm runtime dependency. Rails DB là state core; FFmpeg là dependency render local; MPT và các provider AI chỉ dùng cho nhánh tạo video; platform API chỉ tham gia publish tới đích tương ứng; Google Drive/Sheets và Telegram là side integrations tùy chọn.
- **Cần kiểm chứng lúc implement:** chạy local import → `ffprobe` → cut/retime/render → frame comparison; chạy mỗi OAuth callback; tải file test qua từng upload protocol rồi poll tới trạng thái cuối; xác minh ID/permalink được lưu nếu provider trả; kiểm tra TikTok `SELF_ONLY` hoàn tất không có public ID/permalink mà không bị đánh dấu `OutcomeUnknown`; restart worker/MPT giữa job để kiểm tra recovery; và chạy callback đúng Docker/native topology. Kết quả cần ghi trong Porting Note/implementation evidence. Tài liệu xác nhận contract API; các kiểm tra này xác nhận runtime của AffiHub.
