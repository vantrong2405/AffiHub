# Spec Delta

## Purpose

Đưa Product facts thật từ CSV Dataminer vào Product Library, dùng ACCESSTRADE để tạo affiliate URL thật, rồi filter/score theo behavior của repo tham khảo cho các bước sau trong vertical slice.

## ADDED Requirements

### Requirement: Connect ACCESSTRADE bằng API token
Hệ thống SHALL cho phép user nhập API token ACCESSTRADE thật để tạo `AffiliateConnection`, lưu credential mã hoá at rest trong cột `api_key` hiện có. ACCESSTRADE là API server-to-server, không phải OAuth — user nhập token đã có từ tài khoản ACCESSTRADE, không qua consent screen.

#### Scenario: Connect ACCESSTRADE thành công
- **WHEN** user nhập API token ACCESSTRADE hợp lệ và submit
- **THEN** hệ thống tạo `AffiliateConnection` (provider=accesstrade) với credential mã hoá, gắn với user hiện tại

#### Scenario: Thiếu API token
- **WHEN** user submit form thiếu API token (`api_key`)
- **THEN** hệ thống từ chối tạo `AffiliateConnection`, hiển thị lỗi validate rõ ràng

### Requirement: Import Product facts từ CSV và tạo affiliate link thật qua ACCESSTRADE
Hệ thống SHALL nhận CSV sản phẩm theo schema Dataminer đã xác nhận trong Porting Note (`idx,name,url,price,rating,sold,discount,is_mall,location,is_ad,image`), lưu raw row, tự động normalize/dedupe/filter/rank các dòng đủ điều kiện trong lúc import, rồi gọi ACCESSTRADE `product_link/create` cho tất cả URL đủ điều kiện. Không có bước user chọn từng Product trước khi tạo link trong POC. Product SHALL thuộc `current_user`, lưu `user_id`, `affiliate_provider`, `source_product_id` (nullable nếu CSV không cung cấp ID thật), `merchant` (nullable), `title`, `description` (nullable), `images`, `price`, `original_price` (nullable), `discount`, `category` (nullable), `rating`, `sold`, `is_mall`, `commission` (nullable), `original_product_url`, `affiliate_url`, `raw_source_data`, `last_synced_at`. Không giả lập giá trị field CSV/API không có.

#### Scenario: Import tự động tạo link cho Product đủ điều kiện
- **WHEN** user upload CSV hợp lệ và có AffiliateConnection ACCESSTRADE đang kết nối
- **THEN** hệ thống tự parse, normalize, dedupe, filter/rank các dòng theo pipeline đã cấu hình, gọi API ACCESSTRADE thật cho URL của mọi dòng đủ điều kiện mà không chờ user chọn Product, rồi tạo/update Product trong Product Library với `original_product_url` từ CSV, `affiliate_url` từ `aff_link`, và `last_synced_at`

#### Scenario: Dòng bị loại không được gửi tạo link
- **WHEN** một dòng CSV không qua validation hoặc bị loại bởi quy tắc filter trong import pipeline
- **THEN** hệ thống không gửi URL của dòng đó tới ACCESSTRADE và không tạo affiliate link cho dòng đó; các dòng đủ điều kiện khác vẫn được xử lý theo kết quả từng dòng

#### Scenario: CSV không hợp lệ
- **WHEN** file thiếu header bắt buộc hoặc không parse được
- **THEN** hệ thống báo lỗi file, không gọi API ACCESSTRADE, và không ghi Product

#### Scenario: Upload không an toàn hoặc URL không thuộc phạm vi Shopee
- **WHEN** file vượt quá giới hạn kích thước cấu hình, không phải CSV parseable, hoặc một row chứa URL không phải HTTPS Shopee VN
- **THEN** hệ thống từ chối file/row tại boundary, không gửi URL ngoài phạm vi sang ACCESSTRADE, không lưu path do filename cung cấp, và không log token hay raw credential

#### Scenario: Một dòng CSV hoặc một URL lỗi cục bộ
- **WHEN** một row sai định dạng hoặc ACCESSTRADE trả URL trong `error_link`/`suspend_url`
- **THEN** hệ thống vẫn lưu các Product hợp lệ khác, không tạo affiliate URL giả, và báo đúng `imported_count`/`failed_count`

#### Scenario: Re-import cùng URL sản phẩm
- **WHEN** một URL đã import xuất hiện lại trong file mới
- **THEN** hệ thống update cùng Product dựa trên `(user_id, affiliate_provider, original_product_url)`, không tạo bản ghi trùng

#### Scenario: User chỉ xem và cập nhật sản phẩm của mình
- **WHEN** user upload, filter, list hoặc xem Product trong khi có Product thuộc user khác
- **THEN** Operation chỉ đọc/ghi Product thuộc `current_user`; Product của user khác không bị lộ hoặc thay đổi

#### Scenario: ACCESSTRADE batch vượt giới hạn
- **WHEN** danh sách URL sau filter/rank vượt quá 20
- **THEN** hệ thống chia thành nhiều request theo `batch_size` cấu hình, mỗi request không quá giới hạn reference là 20 URL

### Requirement: original_product_url và affiliate_url lấy từ đúng nguồn
Hệ thống SHALL lưu `original_product_url` từ trường `url` trong CSV và `affiliate_url` từ trường `aff_link` trong response ACCESSTRADE. Không được sinh, suy diễn hoặc copy field này sang field kia.

#### Scenario: Product giữ URL nguồn và tracking link riêng
- **WHEN** một Product được import thành công
- **THEN** `original_product_url` bằng URL CSV và `affiliate_url` bằng `aff_link` ACCESSTRADE tương ứng với URL đó

### Requirement: Filter và Score Product trong Product Library
Hệ thống SHALL cho phép filter Product theo category/price/rating/discount và tính score theo reference `sold * 1.0 + rating * 100 + is_mall * 200 + discount * 1`, dựa trên facts CSV thật và không tạo giá trị giả.

#### Scenario: User filter theo category và rating tối thiểu
- **WHEN** user áp filter category=X và rating>=4.0 trên Product Library
- **THEN** hệ thống trả danh sách Product thật thoả điều kiện, sắp xếp theo score giảm dần

#### Scenario: User chọn Product đã import để generate content
- **WHEN** sau khi import hoàn tất, user chọn một Product đã có trong Product Library
- **THEN** hệ thống cho phép chuyển sang bước Generate Content với đúng Product đó, giữ nguyên facts và affiliate_url thật đã được gắn trong lúc import
