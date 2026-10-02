# Proposal

## Precondition

**Code gate (đủ để BẮT ĐẦU viết task code/test của change này):**
- Các task implementation của change `02` đã hoàn tất và RSpec pass, bao gồm task 11 chuẩn hoá shared HTTP transport; chỉ còn bước verify OAuth/prompt thật. Change `03` không gọi Codex, nên kết quả kết nối Codex thật không chặn việc bắt đầu code change này.

**Archive gate (chỉ archive change `02`, hoặc coi change `02` "xong hẳn", khi đủ):**
- Change `02` đã ở trạng thái `archived`.
- Task "Verify thủ công" cuối của change `02` đã xác nhận Test Connection Codex chạy thật thành công.

## Why

Vertical slice POC cần Product thật (không mock) làm nguồn facts cho các bước sau và affiliate URL do ACCESSTRADE tạo. Theo source `tunguyendg/aff-pipeline`, product facts được nạp từ CSV xuất bởi Dataminer; ACCESSTRADE nhận URL sản phẩm để tạo tracking link, không phải nguồn khám phá catalog. Change này port behavior đó vào Rails, dựa trên model khung (`AffiliateConnection`/`Product`) đã tạo ở change `01-poc-foundation-domain-model`.

## What Changes

- Đọc source thật `tunguyendg/aff-pipeline` (fallback `Duke0503/shopee-aff`, `bcat95/shopee-aff` nếu thiếu kiến trúc), viết Porting Note trước khi code.
- Implement upload/import CSV sản phẩm theo schema Dataminer đã xác nhận trong Porting Note; parse, dedupe theo URL, filter/score và gọi ACCESSTRADE API thật để tạo affiliate link theo batch.
- Cấu hình endpoint, path, timeout và giới hạn batch trong `config/accesstrade.yml`; dùng một HTTP request method chung trong `AccesstradeClient`, không hard-code URL/giá trị cấu hình trong client.
- Implement filter (category/price/rating/discount) và scoring trên Product Library.
- Implement UI Product Library (list + filter) + Product Detail.
- **BREAKING**: không áp dụng.

## Capabilities

### New Capabilities

- `affiliate-product-pipeline`: Nhập facts sản phẩm từ CSV Dataminer, normalize/filter/score theo behavior của reference, và tạo `affiliate_url` thật qua ACCESSTRADE; Product giữ riêng URL gốc và affiliate URL — AI không được generate các field này.

### Modified Capabilities

(không có)

## Impact

- **Code**: `affihub/app/operations/affiliate_products/*`, `affihub/app/clients/accesstrade_client.rb`, `affihub/app/controllers/products_controller.rb`, migration về ownership/identity của Product, `config/accesstrade.yml`, `config/product_catalog.yml`, UI Product/connection.
- **Phụ thuộc**: cần change `01-poc-foundation-domain-model` đã archive (model `AffiliateConnection`/`Product` khung rỗng đã tồn tại).
- **Hệ thống ngoài**: ACCESSTRADE API thật cần API token thật; product facts đến từ CSV Dataminer do user cung cấp.
