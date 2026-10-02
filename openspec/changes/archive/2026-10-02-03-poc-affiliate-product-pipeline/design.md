# Design

## Context

Model khung `AffiliateConnection`/`Product` đã tồn tại từ change `01`. Xem `proposal.md` cho motivation. Reference bắt buộc: `tunguyendg/aff-pipeline` trước, fallback `Duke0503/shopee-aff` (kiến trúc worker/batch/tracking), rồi `bcat95/shopee-aff` (chi tiết Shopee-specific, phải phân loại Official/Unofficial/Reverse-engineered/Deprecated).

## Goals / Non-Goals

**Goals:**
- Nhập Product facts thật từ CSV Dataminer, filter/score theo behavior của reference, rồi lấy affiliate link thật từ ACCESSTRADE.
- Không giả định ACCESSTRADE có endpoint tìm kiếm/đọc toàn bộ catalog. `product_link/create` nhận URL đã có và tạo tracking link.
- Giữ `original_product_url` từ CSV và `affiliate_url` từ response ACCESSTRADE thành hai field riêng.

**Non-Goals:**
- Không implement multi-affiliate-provider (chỉ ACCESSTRADE).
- Không implement background sync tự động theo lịch (import là action thủ công user bấm trong POC).

## Decisions

### 1. Reference pipeline được port sang Rails
Luồng là CSV Dataminer → normalize/dedupe → categorize/filter → score/rank tự động → ACCESSTRADE batch tạo tracking link cho mọi dòng đủ điều kiện → lưu Product vào Product Library. User không chọn từng sản phẩm trước khi tạo link trong POC. Sau import, user filter/xem Product Library rồi chọn một Product cụ thể để Generate Content; đây là bước chọn riêng, diễn ra sau khi affiliate link đã được tạo. CSV cung cấp `idx`, `name`, `url`, `price`, `rating`, `sold`, `discount`, `is_mall`, `location`, `is_ad`, `image`; `source_keyword` được suy ra từ filename theo behavior đã ghi trong Porting Note. Category được gán theo `match_keywords`/`exclude_keywords` cấu hình, trong đó exclude ưu tiên hơn match. Không copy code Python (repo primary không khai báo license); chỉ port behavior.

CSV là dữ liệu đầu vào do user cung cấp, không phải affiliate provider thứ hai. ACCESSTRADE vẫn là affiliate provider duy nhất và là source of truth cho `affiliate_url`. `commission` cùng field CSV không có SHALL để `nil`, không tự điền. `original_product_url` lấy từ `url` trong CSV.

### 2. Client HTTP dùng config và một transport chung
`app/clients/accesstrade_client.rb` chỉ lo I/O/parse response. Endpoint base URL/path, campaign ID, batch size, timeout, retry count và backoff SHALL lấy từ `config/accesstrade.yml` qua `Rails.application.config_for(:accesstrade)`. Mọi HTTP method trong client SHALL đi qua một private request method chung; không lặp `Net::HTTP` call hoặc hard-code URL/giá trị config tại call site. API dùng `Authorization: Token <token>`; credential lưu trong `AffiliateConnection` (cột `api_key` hiện có, UI gọi rõ là API token), không ghi log.

### 3. Scoring và ranking port từ reference
Vì khối lượng Product trong POC nhỏ, scoring tính trực tiếp trong Operation/query lúc filter. Dùng weighted sum của reference: `sold * 1.0 + rating * 100 + is_mall * 200 + discount * 1`, sau khi normalize kiểu dữ liệu CSV. Giữ field thiếu là `nil` trong Product; scoring dùng 0 cho thành phần thiếu như behavior reference. Weights và category/filter defaults SHALL nằm trong `config/product_catalog.yml`. Không dùng công thức normalize/log trong bản nháp cũ. Tie-breaker SHALL ổn định theo `last_synced_at DESC`, rồi `id DESC` (Rails adaptation để thứ tự DB ổn định).

### 4. Dedupe/upsert theo URL gốc
Reference dedupe product theo `url`, không có `source_product_id` trong CSV schema. Import SHALL dùng bộ `(user_id, affiliate_provider, original_product_url)` làm identity để re-import không tạo trùng nhưng mỗi user giữ tracking link riêng. Thêm unique index tương ứng bằng migration; không parse hoặc bịa `source_product_id` từ URL. `source_product_id` giữ nullable để tương thích domain model nếu provider sau này trả ID thật.

### 5. ACCESSTRADE batch, partial result và retry
Chỉ gửi URL của các dòng đã qua filter/ranking tự động trong import tới `POST /v1/product_link/create`; không có bước user chọn Product trước khi gọi API. Chia batch tối đa 20 URL theo behavior reference. Map response bằng `url_origin` với URL gốc, lấy `aff_link` làm `affiliate_url`. `error_link`/`suspend_url` tính là lỗi từng Product; các Product có link thành công vẫn được lưu, lỗi được báo qua `imported_count`/`failed_count`. Retry HTTP dùng số lần và backoff của reference, nhưng mọi giá trị lấy từ YAML.

CSV parse/validation lỗi toàn file thì không gọi ACCESSTRADE và không ghi Product. Lỗi từng dòng hoặc từng link không làm mất các dòng thành công khác; không bọc toàn bộ batch trong transaction all-or-nothing.

### 6. Upload boundary và ownership
Validate size theo `config/product_catalog.yml`, kiểm tra extension/content có thể parse thành CSV, validate header trước khi gọi API; không dùng filename làm filesystem path. Chỉ nhận `https` URL thuộc Shopee VN cho `url`; không forward URL khác sang ACCESSTRADE. Scope import, list, filter, show và update theo `current_user`; identity là `(user_id, affiliate_provider, original_product_url)` để mỗi user có affiliate link riêng. Dùng Rails HTML escaping mặc định khi render CSV values, không log token/raw credential.

## Risks / Trade-offs

- [CSV đầu vào không đồng nhất hoặc thiếu cột cần thiết] → Mitigation: validate header/schema trước khi tạo Product; hiển thị lỗi theo file/dòng, không đoán mapping.
- [ACCESSTRADE rate limit/quota giới hạn số lần tạo link] → Mitigation: chỉ gửi sản phẩm đã filter/rank, chia batch tối đa 20 URL, có timeout/retry cấu hình được; lưu `raw_source_data` để debug.
- [`bcat95/shopee-aff` có thể chứa phần reverse-engineered không rõ license] → Mitigation: Porting Note phải phân loại rõ Official/Unofficial/Reverse-engineered/Deprecated trước khi quyết định port phần nào; phần Reverse-engineered/Deprecated không port code, chỉ học behavior rồi clean-room reimplement nếu thật sự cần.

## Migration Plan

Model đã có từ change 01. Migration change này thêm `products.user_id` và `is_mall`, đồng thời thay unique index `(affiliate_provider, source_product_id)` bằng `(user_id, affiliate_provider, original_product_url)`; không sửa migration change 01. Scope theo user bảo vệ Product và affiliate link khỏi bị dùng chung giữa các tài khoản.
