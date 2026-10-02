# Tasks

## 1. Porting Note

- [x] 1.1 Đọc source/reference hiện hành `gitroomhq/postiz-app` và `thenavidm/facebook-mcp`, check LICENSE, đối chiếu tài liệu Meta đã truy cập được; ghi findings, giới hạn docs 429 và scope implementation trong `affihub/docs/reference-analysis/facebook-social-connection.md`

## 2. Migration bổ sung (nếu cần)

- [x] 2.1 Rà `spec/models/social_destination_spec.rb` và schema; các field `destination_type`, `page_id`, `name`, `page_access_token` đã đủ từ change 01
- [x] 2.2 Không cần migration bổ sung; schema change 01 đã có đủ field yêu cầu

## 3. Facebook App credential config (thiếu hoàn toàn ở bản trước — cần trước khi build authorize URL)

- [x] 3.1 Tạo Facebook Developer App thật (nếu chưa có), ghi App ID/App Secret vào `config/credentials.yml.enc` (namespace `facebook: {app_id:, app_secret:}`), verify: Rails credentials giải mã thành công và cả hai giá trị khớp env mà không lộ plaintext.
- [x] 3.2 Set redirect URI trong Facebook Developer App settings = `http://localhost:4000/social_connections/callback` (khớp đúng route sẽ tạo ở task 4.7), verify: redirect URI hiển thị đúng trong Facebook App dashboard
- [x] 3.3 Ghi giới hạn app Development/test mode và quyền Page vào Porting Note; live access vẫn cần cấu hình app thật

## 4. Connect Facebook — authorize + callback round-trip qua session (xem design.md Decision 1b)

- [x] 4.1 Viết `spec/clients/meta_graph_client_spec.rb` cho authorize URL và OAuth code exchange; HTTP transport được WebMock stub tại boundary
- [x] 4.2 Thêm config-driven `MetaGraphClient` với một HTTP request method GET/POST và endpoints/timeouts từ `config/facebook.yml`; spec pass
- [x] 4.2b Viết test long-lived token exchange, chạy fail trước implementation
- [x] 4.2c Implement `exchange_long_lived_token`, spec pass
- [x] 4.3 Viết operation specs cho success và long-lived exchange failure; không persist short-lived token
- [x] 4.4 Implement `ConnectOperation`; spec pass
- [x] 4.5 Viết request specs cho session state, callback mismatch, state consumption, cancellation; chạy fail
- [x] 4.6 Implement `connect`/`callback` với one-time state validation; spec pass
- [x] 4.7 Thêm route connect/callback; `rtk bin/rails routes -g social_connections` hiển thị đúng. Redirect URI app dashboard còn ở task 3.2.

## 5. Discover Page

- [x] 5.1 Viết client spec cho Page discovery qua endpoint/version config
- [x] 5.2 Implement `list_pages` qua transport chung, spec pass
- [x] 5.3 Viết operation specs cho Page list, empty state, cache metadata không chứa token
- [x] 5.4 Implement `DiscoverPagesOperation`; spec pass

## 6. Sync SocialDestination (chống trust page_id từ client, không cache token)

- [x] 6.1 Viết client spec cho Page token lookup qua API config
- [x] 6.2 Implement `fetch_page_token` qua transport chung, spec pass
- [x] 6.3 Viết sync operation specs cho token mới và Page ID không thuộc discover cache
- [x] 6.4 Implement `SyncDestinationOperation`, spec pass

## 7. Validation Publication cần SocialDestination (chuẩn bị association)

- [x] 7.1 Viết `spec/models/social_destination_spec.rb` xác nhận association `has_many :publications`, chạy fail
- [x] 7.2 Implement association trong `app/models/social_destination.rb`, verify: spec pass

## 8. UI Social Connections + Facebook Pages

- [x] 8.1 Viết request specs cho discover/empty state và sync destination, chạy fail
- [x] 8.2 Implement UI/controllers/views; request specs + browser smoke qua Facebook Connection/Pages pass. Live connect/discover thuộc task 9.1.

## 9. Verify thủ công end-to-end phase này

- [x] 9.1 Connect Facebook thật, discover Page thật, chọn 1 Page thật tạo SocialDestination thành công qua UI
- [x] 9.2 Chạy task scoped RSpec command, verify: 19 examples, 0 failures
