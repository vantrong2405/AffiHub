# Tasks

## 1. Porting Note

- [x] 1.1 Đọc source thật `tunguyendg/aff-pipeline` (import/normalize/filter/scoring/ranking/affiliate links), check LICENSE; nếu thiếu kiến trúc worker/batch/tracking đọc thêm `Duke0503/shopee-aff`; nếu cần chi tiết Shopee-specific đọc `bcat95/shopee-aff` và phân loại Official/Unofficial/Reverse-engineered/Deprecated từng phần dùng. Viết `affihub/docs/reference-analysis/affiliate-product-pipeline.md` đủ mục template, verify: file tồn tại

## 2. Migration bổ sung (nếu Porting Note phát hiện thiếu field)

- [x] 2.1 Viết `spec/models/product_spec.rb` xác nhận `Product belongs_to :user`, `User has_many :products`, `is_mall` tồn tại, và cùng URL/provider có thể thuộc hai user riêng; chạy fail nếu cột/index chưa có
- [x] 2.2 Thêm migration `user_id` + foreign key + `is_mall` boolean (không sửa migration change 01) để spec 2.1 pass; verify: spec pass

## 3. Connect ACCESSTRADE (tạo `AffiliateConnection`)

ACCESSTRADE dùng API token server-to-server theo reference (không OAuth, không browser consent). Form ghi rõ API token; không yêu cầu secret thứ hai. Lưu token mã hoá trong cột `api_key` sẵn có của `AffiliateConnection`.

- [x] 3.1 Viết `spec/forms/affiliate_connections/create_form_spec.rb` (nhận API token qua `api_key`, validate presence; không yêu cầu `api_secret`), chạy fail
- [x] 3.2 Implement `app/forms/affiliate_connections/create_form.rb` để spec 3.1 pass, verify: spec pass
- [x] 3.3 Viết `spec/operations/affiliate_connections/create_operation_spec.rb` (tạo `AffiliateConnection` với `provider: "accesstrade"`, `belongs_to :user` = current_user, API token được mã hoá qua `encrypts :api_key`), chạy fail
- [x] 3.4 Implement `app/operations/affiliate_connections/create_operation.rb` để spec 3.3 pass, verify: spec pass
- [x] 3.5 Viết `spec/requests/affiliate_connections_spec.rb` (form nhập API token, submit tạo AffiliateConnection, dùng `render_operation`), chạy fail
- [x] 3.6 Thêm route `resource :affiliate_connection` (hoặc tương đương) vào `config/routes.rb`. Dùng skill `ui-ux` để quyết định layout/token màu cho form nhập API token ACCESSTRADE trước khi viết view; implement `app/controllers/affiliate_connections_controller.rb` + view để spec 3.5 pass. Verify code gate: request specs pass và form hiển thị trên `rtk bin/dev`; xác minh token/affiliate link ACCESSTRADE thật thuộc task 7.1.

## 4. Import Product từ CSV và tạo affiliate link thật

- [x] 4.1 Viết `spec/clients/accesstrade_client_spec.rb` cho `create_affiliate_links`: POST tới `product_link/create` với `Authorization: Token`, map `url_origin` → `aff_link`/`short_link`; verify base URL/path/config values được đọc từ `config/accesstrade.yml`, và mọi HTTP request đi qua một transport method chung. Stub HTTP ở boundary, chạy fail
- [x] 4.2 Thêm `config/accesstrade.yml` với base URL/path, campaign ID/UTM defaults, batch size 20, timeout, retries/backoff theo Porting Note; implement `app/clients/accesstrade_client.rb` dùng `Rails.application.config_for(:accesstrade)` + một private HTTP request method chung; không hard-code URL, ID, port/version hay config literal trong client. Làm spec 4.1 pass
- [x] 4.3 Viết `spec/operations/affiliate_products/import_operation_spec.rb` cho upload CSV theo schema Dataminer trong Porting Note (`idx,name,url,price,rating,sold,discount,is_mall,location,is_ad,image`); parse số, preserve raw row, dedupe theo URL, gán category theo `match_keywords`/`exclude_keywords` (exclude ưu tiên), tự động filter/score theo reference và chỉ gửi URL của các dòng đủ điều kiện để tạo link (không phải Product do user chọn), lưu facts từ CSV và `affiliate_url` từ `aff_link`, set `last_synced_at`; chạy fail
- [x] 4.4 Viết `spec/operations/affiliate_products/import_operation_spec.rb` bổ sung upsert idempotent theo `(user_id, affiliate_provider, original_product_url)` (không tạo duplicate khi cùng user re-import URL; hai user khác nhau có thể lưu link riêng), chạy fail
- [x] 4.5 Viết `spec/operations/affiliate_products/import_operation_spec.rb` bổ sung lỗi toàn file (header bắt buộc thiếu/CSV không parse được) — không gọi ACCESSTRADE và không ghi Product; chạy fail
- [x] 4.6 Viết `spec/operations/affiliate_products/import_operation_spec.rb` bổ sung lỗi cục bộ (CSV row lỗi, URL không phải HTTPS Shopee VN, API trả `error_link`/`suspend_url`, hoặc response không map được) — không gửi URL ngoài scope sang ACCESSTRADE, Product hợp lệ khác vẫn lưu; báo `imported_count`/`failed_count` chính xác; chạy fail
- [x] 4.7 Implement `app/operations/affiliate_products/import_operation.rb` theo chuỗi parse → validate → dedupe → categorize/filter/score tự động → batch create links cho mọi dòng đủ điều kiện → upsert; chỉ dùng `AffiliateConnection` và Product thuộc `current_user`; xử lý lỗi toàn file trước khi ghi DB và lỗi từng dòng/link độc lập để spec 4.3–4.6 pass
- [x] 4.8 Viết spec cho việc chia trên 20 URL thành nhiều batch tối đa 20, retry/backoff/timeout theo config và map kết quả bằng `url_origin` (không dựa vào response array order); chạy fail
- [x] 4.9 Implement batch/retry trong `AccesstradeClient` theo reference, dùng toàn bộ giá trị từ YAML; làm spec 4.8 pass
- [x] 4.10 Viết `spec/models/product_spec.rb` xác nhận `original_product_url` lấy từ CSV, `affiliate_url` lấy từ response ACCESSTRADE, không copy chéo; `commission`/field CSV không có vẫn `nil`; chạy fail
- [x] 4.11 Viết `spec/models/product_spec.rb` xác nhận identity unique theo `(user_id, affiliate_provider, original_product_url)` và re-import update đúng record; chạy fail
- [x] 4.12 Thêm migration thay unique index `(affiliate_provider, source_product_id)` bằng `(user_id, affiliate_provider, original_product_url)` để spec 4.11 pass; không sửa migration change 01

## 5. Filter + Score

- [x] 5.1 Viết spec cho category assignment từ `match_keywords`/`exclude_keywords` (exclude ưu tiên), config category/default filters, và filter theo category/price/rating/discount; chạy fail
- [x] 5.2 Thêm `config/product_catalog.yml` chứa category keyword rules, filter defaults, score weights theo reference và giới hạn kích thước CSV; implement phân loại/filter qua `ImportOperation`/model scope phù hợp, không tạo Query/Service layer mới; làm spec 5.1 pass
- [x] 5.3 Viết `spec/models/product_spec.rb` bổ sung `#score` theo weighted sum thật trong design.md Decision 3 (`sold * 1.0 + rating * 100 + is_mall * 200 + discount * 1`), normalize dữ liệu CSV như reference, field thiếu không làm lỗi; sort `score DESC, last_synced_at DESC, id DESC`, chạy fail
- [x] 5.4 Implement `Product#score` + scope sort theo công thức reference trong `app/models/product.rb` để spec 5.3 pass, verify: spec pass

## 6. UI Product Library + Product Detail

- [x] 6.1 Viết `spec/operations/products/list_operation_spec.rb` và `show_operation_spec.rb` xác nhận chỉ trả Product của `current_user`; chạy fail
- [x] 6.2 Implement `Products::ListOperation`/`ShowOperation` với ownership scope để spec 6.1 pass, verify: specs pass
- [x] 6.3 Viết `spec/requests/products_spec.rb` (list/filter, Product Detail, upload CSV, trạng thái imported/failed count, lỗi CSV, giới hạn kích thước file; seed Product của user khác và xác nhận không lộ), chạy fail
- [x] 6.4 Thêm route `resources :products, only: [:index, :show]` và action upload/import tương ứng vào `config/routes.rb`. Dùng skill `ui-ux` để quyết định layout/component/token màu cho CSV upload, filter form và Product Detail trước khi viết view; implement `app/controllers/products_controller.rb` + views (`index` có upload/filter; `show` detail — CHƯA có CTA "Generate Content" ở change này; CTA thêm tại change 04 task 6.2). Product chỉ được user chọn từ Product Library sau khi import và tạo link xong. Controller chỉ gọi Operations; action command dùng `render_operation`, read-only action render dữ liệu Operation trả về; không query Model trực tiếp. Verify code gate: request specs pass (import dùng HTTP stub) và `rtk bin/dev` hiển thị Product Library/upload/filter; import Dataminer CSV và tạo tracking link thật thuộc task 7.1.

## 7. Verify thủ công end-to-end phase này

- [ ] 7.1 Upload CSV product thật từ Dataminer; pipeline tự filter/rank và dùng token ACCESSTRADE thật đã nhập ở nhóm 3 để tạo tracking link cho các dòng đủ điều kiện trong lúc import; sau đó chọn Product trong Product Library. Verify: facts lấy từ CSV, `original_product_url` khớp URL nguồn, `affiliate_url` lấy từ `aff_link` response thật và mở được
- [x] 7.2 Chạy `RAILS_ENV=test rtk bundle exec rspec spec/forms/affiliate_connections spec/operations/affiliate_connections spec/requests/affiliate_connections_spec.rb spec/clients/accesstrade_client_spec.rb spec/operations/affiliate_products spec/models/product_spec.rb spec/requests/products_spec.rb`, verify: pass 100%
