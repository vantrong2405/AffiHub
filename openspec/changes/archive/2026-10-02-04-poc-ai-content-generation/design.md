# Design

## Context

Model khung `Content` đã có từ change `01`. AI provider contract, Codex adapter và `AIConnection` được định nghĩa ở change `02`. Product thật có trong DB từ change `03`. Xem `proposal.md` cho motivation.

## Goals / Non-Goals

**Goals:**
- Generate/Regenerate dùng provider contract đã được change `02` định nghĩa; không gọi Codex adapter trực tiếp và không tạo client provider thứ hai.
- Đảm bảo affiliate_url/Product facts không bao giờ bị AI ghi đè — tách rõ "nội dung do AI sinh" và "facts do application attach".

**Non-Goals:**
- Không cho phép multi-platform content (chỉ Facebook, theo scope POC).
- Không tự động approve — human review luôn bắt buộc.

## Decisions

### 1. Prompt builder tách khỏi provider I/O
`app/operations/contents/build_prompt.rb` (hoặc method riêng) build prompt text từ Product facts + tone; prompt content là business rule của capability này, còn provider adapter chỉ lo credential và I/O.

### 1b. Generate chỉ được đọc Product thuộc current_user
`GenerateOperation` SHALL load Product qua association/scope của `current_user` (Product có `belongs_to :user` từ change 03). Nếu Product không thuộc user hiện tại thì trả validation error trước khi gọi AI provider, không tạo Content và không đưa facts của Product đó vào request. `Content#user` cũng được gán `current_user` để các bước Publication tiếp tục kiểm tra ownership.

### 2. Lifecycle bằng Rails enum, không thêm gem state machine
`Content` dùng string enum cho `generated`, `review`, `approved`, `rejected` (đã có khung ở change 01). Model có transition method `start_review!`/`approve!`/`reject!`; `RegenerateOperation` cập nhật row cụ thể và chuyển nội dung Rejected trở lại Review sau khi provider thành công. Đủ đơn giản cho 4 trạng thái, không cần gem `aasm`/`state_machines`.

### 3. Lọc URL lạ bằng regex đơn giản trên response text
Sau khi nhận response từ provider, Operation loại URL ngoài `product.affiliate_url` khỏi `Content#body`; `affiliate_url` gốc vẫn được application giữ riêng và tự attach khi publish. Đây chỉ là bảo vệ URL, không phải kiểm tra tính đúng đắn của các câu chữ/claim khác.

### 4. Content lưu 1 cột `body` duy nhất (hook+caption+CTA+hashtags gộp thành 1 text), không tách cột riêng
Quyết định (chốt dứt điểm, không để "tuỳ chọn" nữa): `Content#body` là 1 cột text chứa phần copy do AI sinh (hook+caption+CTA+hashtags viết liền thành 1 đoạn) — KHÔNG chứa `affiliate_url` (field đó nằm ở cột riêng `Content#affiliate_url`, app tự attach, xem Requirement "Generate Content từ Product facts thật"). Lý do gộp hook/caption/cta/hashtags vào 1 cột: tách cột riêng chỉ hữu ích nếu UI cần render/style riêng từng phần, nhưng PROJECT_SPEC UI tối thiểu không yêu cầu điều đó — tách là over-engineering cho nhu cầu thật của POC. Khi publish, `MetaGraphPublisher` (change 06) SHALL tự ghép `content.body` + `content.affiliate_url` thành `message` gửi Facebook (xem change 06 design.md) — Publisher KHÔNG gửi nguyên `content.body` một mình, nếu không bài đăng thật sẽ thiếu link affiliate.

Alternative: 4 cột riêng (`hook`, `caption`, `cta`, `hashtags`) rồi ghép lại lúc publish. Bị loại — thêm độ phức tạp parse/ghép không cần thiết, và buộc prompt Codex phải trả JSON có cấu trúc đáng tin cậy (rủi ro parse lỗi) thay vì nhận text thường.

### 5. Một Product có nhiều Content; Regenerate cập nhật đúng một Content row

`Product` có thể có nhiều Content độc lập ngay trong schema POC. Mỗi Content đại diện cho một bản copy và lifecycle riêng; Content đã Approved là terminal riêng của row đó, không khóa khả năng tạo Content khác từ Product. Đây giữ đường mở rộng nhiều phiên bản/nội dung cho các chiến dịch về sau mà chưa cần tạo Campaign model hoặc provider framework tổng quát.
- **Generate** luôn tạo một row `Content` mới kể cả khi Product đã có Content ở trạng thái nào. Mỗi row lưu `product_id`, `user_id`, `affiliate_url` snapshot từ Product tại thời điểm generate, body và lifecycle riêng. UI Product Detail/Content Review cần cho user xem các Content đã có và mở từng bản; CTA Generate tạo bản mới.
- **Regenerate** thao tác trên row `Content` đang mở (giữ nguyên `id`), ghi đè `body`, tăng `generation_count`; không tạo row mới cho lần regenerate. Chỉ các row khác nhau mới biểu diễn các bản Content riêng.
- **Reject** kết thúc vòng review hiện tại và chuyển đúng Content row sang `rejected`. User có thể bấm **Regenerate** để cập nhật row Rejected đó (giữ nguyên ID, Product và affiliate URL; tăng `generation_count`; đưa nội dung mới về `review`) hoặc bấm **Generate** từ Product để tạo một Content row độc lập. Hai hành động giữ đúng nghĩa: Generate luôn tạo row mới, Regenerate chỉ sửa row đang thao tác.
- **Edit** chỉ hợp lệ ở `review` (không áp dụng ở `rejected` — muốn sửa sau khi Reject phải Regenerate trước để quay lại Review).
- **Approved** là terminal cho bản Content đó: không thể Edit, Reject hoặc Regenerate. User vẫn có thể tạo một row Content mới cho cùng Product; bản mới có lifecycle độc lập. Publication luôn reference chính xác một Content row nên các bản copy đã publish không bị thay khi user tạo bản mới.

### 6. Generate và Regenerate đi qua provider contract

`GenerateOperation` và `RegenerateOperation` dựng prompt từ business facts rồi gọi provider contract của change `02` để nhận text. Contract/adapter xử lý kiểm tra connection, token freshness, refresh và provider I/O; các Content Operations không gọi `CodexClient` hay quản lý token trực tiếp. Trong POC contract chỉ được nối tới Codex adapter. Task 15.1 của change `02` sẽ đối chiếu interface nhỏ này với provider abstraction trong `decolua/9router` và ghi rõ phần được tham khảo; registry/plugin runtime không được port. Lỗi credential/disconnected được chuyển thành hướng dẫn kết nối lại; lỗi timeout/transport tạm thời thành hướng dẫn thử lại sau. Cả hai dạng lỗi đều không tạo Content mới, còn Regenerate giữ nguyên nội dung hiện tại.

## Risks / Trade-offs

- [AI có thể sinh claim sai dù nhận Product facts thật; không có kiểm tra tự động đáng tin cậy cho mọi câu] → Mitigation: coi output là draft, yêu cầu human review và approval trước publish; không tuyên bố app đã xác minh claim.
- [Lọc URL không chứng minh các facts trong copy đúng] → Mitigation: giới hạn lọc URL cho affiliate link; người duyệt đối chiếu copy với Product facts trước khi approve.

## Migration Plan

Migration tạo bảng `contents` ở change `01` dùng `t.references :product`, nên `contents.product_id` đã có index thường không unique từ đầu. Migration change này chỉ thêm `generation_count` (`integer`, `default: 0`, `null: false`); model dùng quan hệ `Product has_many :contents`. Không thêm hoặc thay index cho `product_id`. Nếu cần điều chỉnh index trong tương lai, sửa đúng migration nguồn trước khi migration đó được áp dụng, thay vì tạo index sai rồi thêm migration để gỡ lại. Không xóa Content/Publication hiện có. Trước migration, prerequisite change `03` phải hoàn thành code gate trong `proposal.md`.
