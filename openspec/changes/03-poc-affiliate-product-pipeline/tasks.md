# Tasks

## 1. Porting Note

- [ ] 1.1 Đọc source thật `tunguyendg/aff-pipeline` (import/normalize/filter/scoring/ranking/affiliate links), check LICENSE; nếu thiếu kiến trúc worker/batch/tracking đọc thêm `Duke0503/shopee-aff`; nếu cần chi tiết Shopee-specific đọc `bcat95/shopee-aff` và phân loại Official/Unofficial/Reverse-engineered/Deprecated từng phần dùng. Viết `affihub/docs/reference-analysis/affiliate-product-pipeline.md` đủ mục template, verify: file tồn tại

## 2. Migration bổ sung (nếu Porting Note phát hiện thiếu field)

- [ ] 2.1 Viết `spec/models/product_spec.rb` bổ sung assertion cho field mới phát hiện (nếu có), chạy fail nếu cột chưa có
- [ ] 2.2 Thêm migration tương ứng để spec pass, verify: spec pass (bỏ qua nếu model change 01 đã đủ field)

## 3. Connect ACCESSTRADE (tạo `AffiliateConnection`) — thiếu hoàn toàn ở bản trước, import không có gì để import từ

ACCESSTRADE là API server-to-server (API key/secret cấp sẵn qua đăng ký tài khoản, KHÔNG phải OAuth 3-chân như Codex/Facebook — user không "consent" qua browser, chỉ nhập key/secret đã có) — xác nhận lại hướng cụ thể trong Porting Note task 1.1 nếu ACCESSTRADE thực tế có cơ chế khác.

- [ ] 3.1 Viết `spec/forms/affiliate_connections/create_form_spec.rb` (nhận `api_key`/`api_secret`, validate presence), chạy fail
- [ ] 3.2 Implement `app/forms/affiliate_connections/create_form.rb` để spec 3.1 pass, verify: spec pass
- [ ] 3.3 Viết `spec/operations/affiliate_connections/create_operation_spec.rb` (tạo `AffiliateConnection` với `provider: "accesstrade"`, `belongs_to :user` = current_user, key/secret mã hoá qua `encrypts`), chạy fail
- [ ] 3.4 Implement `app/operations/affiliate_connections/create_operation.rb` để spec 3.3 pass, verify: spec pass
- [ ] 3.5 Viết `spec/requests/affiliate_connections_spec.rb` (form nhập credential, submit tạo AffiliateConnection, dùng `render_operation`), chạy fail
- [ ] 3.6 Thêm route `resource :affiliate_connection` (hoặc tương đương) vào `config/routes.rb`. Dùng skill `ui-ux` để quyết định layout/token màu cho form nhập credential ACCESSTRADE trước khi viết view; implement `app/controllers/affiliate_connections_controller.rb` + view (form nhập API key/secret) để spec 3.5 pass, verify: spec pass + `rtk bin/dev` nhập credential ACCESSTRADE thật tạo được AffiliateConnection

## 4. Import Product

- [ ] 4.1 Viết `spec/clients/accesstrade_client_spec.rb` (gọi API thật qua stub HTTP, parse response thô), chạy fail
- [ ] 4.2 Implement `app/clients/accesstrade_client.rb` để spec 4.1 pass, verify: spec pass
- [ ] 4.3 Viết `spec/operations/affiliate_products/import_operation_spec.rb` (Requirement "Import Product thật từ ACCESSTRADE": map đủ field, nullable khi thiếu, lưu raw_source_data/last_synced_at, upsert theo `(affiliate_provider, source_product_id)` không tạo trùng khi re-import cùng sản phẩm), chạy fail
- [ ] 4.4 Implement `app/operations/affiliate_products/import_operation.rb` (dùng `find_or_initialize_by(affiliate_provider:, source_product_id:)`, trả về số lượng `imported_count`/`failed_count` qua `attr_reader` để UI hiển thị kết quả import) để spec 4.3 pass, verify: spec pass
- [ ] 4.5 Viết `spec/operations/affiliate_products/import_operation_spec.rb` bổ sung case lỗi provider (Requirement "Import Product thật từ ACCESSTRADE" - scenario lỗi toàn request: không tạo Product giả, không update last_synced_at), chạy fail
- [ ] 4.6 Implement error handling (request-level) trong Operation/Client để spec 4.5 pass, verify: spec pass
- [ ] 4.6b Viết `spec/operations/affiliate_products/import_operation_spec.rb` bổ sung case 1 record lỗi giữa 1 batch N record hợp lệ (Requirement "Import Product thật từ ACCESSTRADE" - scenario atomicity per-record: record khác vẫn lưu thành công, không rollback cả batch, `imported_count`/`failed_count` đúng theo từng record), chạy fail
- [ ] 4.6c Implement `import_operation.rb` xử lý từng record độc lập (rescue riêng mỗi record trong vòng lặp, không bọc transaction cả batch, cộng dồn `imported_count`/`failed_count`) để spec 4.6b pass, verify: spec pass
- [ ] 4.6d Viết `spec/clients/accesstrade_client_spec.rb` bổ sung case ACCESSTRADE trả nhiều trang (pagination) — xác nhận client gọi lặp tới khi hết trang (theo cơ chế phân trang thật của ACCESSTRADE, chốt cụ thể ở Porting Note task 1.1 — tổng/offset hoặc cursor, không tự bịa), trả về đủ toàn bộ record qua các trang, không dừng ở trang đầu, chạy fail
- [ ] 4.6e Implement pagination loop trong `app/clients/accesstrade_client.rb` để spec 4.6d pass, verify: spec pass
- [ ] 4.7 Viết `spec/models/product_spec.rb` bổ sung assertion `original_product_url`/`affiliate_url` đúng bằng giá trị provider trả về cho từng field, không bị copy chéo; record vẫn hợp lệ nếu 2 giá trị trùng nhau (Requirement "original_product_url và affiliate_url lấy thật từ provider, không bị hệ thống tự sinh"), chạy fail nếu chưa đúng
- [ ] 4.8 Verify spec 4.7 pass (nên đã pass từ 4.4, chỉ cần xác nhận, không cần code thêm)

## 5. Filter + Score

- [ ] 5.1 Viết `spec/models/product_spec.rb` bổ sung scope filter theo category/price/rating/discount (Requirement "Filter và Score Product trong Product Library"), chạy fail
- [ ] 5.2 Implement scope trong `app/models/product.rb` để spec 5.1 pass, verify: spec pass
- [ ] 5.3 Viết `spec/models/product_spec.rb` bổ sung method `#score` (công thức mặc định ở design.md Decision 2 — trọng số rating/discount/sold normalize, field nil bị loại khỏi công thức, luôn trả numeric không nil kể cả khi thiếu cả 3 field; case toàn bộ Product Library có `sold` 0/nil (kể cả khi `Product.maximum(:sold)` trả `nil`) → `max_sold_seen == 0` → `score` vẫn là số thật, KHÔNG `NaN`/raise) và scope sort theo `score DESC, last_synced_at DESC, id DESC` (tie-breaker), chạy fail
- [ ] 5.4 Implement `Product#score` + scope sort (dùng `max_sold_seen` query 1 lần, không hard-code) trong `app/models/product.rb` để spec 5.3 pass, verify: spec pass

## 6. UI Product Library + Product Detail

- [ ] 6.1 Viết `spec/requests/products_spec.rb` (list có filter param trả đúng kết quả, show hiển thị Product Detail), chạy fail
- [ ] 6.2 Thêm `resources :products, only: [:index, :show]` vào `config/routes.rb`. Dùng skill `ui-ux` để quyết định layout/component/token màu cho filter form và Product Detail trước khi viết view; implement `app/controllers/products_controller.rb` + views (`index` có filter form, `show` detail — CHƯA có CTA "Generate Content" ở change này, route `new_content_path` chưa tồn tại tới khi change `04` tạo `resources :contents`; CTA được thêm vào view này ở change `04` task 6.2, không phải ở đây, để tránh view gọi route helper chưa tồn tại). `index`/`show` là read-only, gọi Operation rồi render view trực tiếp; không query Model trong Controller. Các action command nếu bổ sung sau phải dùng `render_operation` để xử lý success/failure; verify: spec pass + `rtk bin/dev` filter hoạt động đúng trên UI

## 7. Verify thủ công end-to-end phase này

- [ ] 7.1 Import thật từ ACCESSTRADE credential thật qua UI (đã connect ở nhóm 3), verify: Product trong DB có `original_product_url`/`affiliate_url` thật, mở link xác nhận khả dụng
- [ ] 7.2 Chạy `RAILS_ENV=test rtk bundle exec rspec spec/forms/affiliate_connections spec/operations/affiliate_connections spec/requests/affiliate_connections_spec.rb spec/clients/accesstrade_client_spec.rb spec/operations/affiliate_products spec/models/product_spec.rb spec/requests/products_spec.rb`, verify: pass 100%
