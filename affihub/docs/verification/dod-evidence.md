# Bằng chứng kiểm thử POC end-to-end

Ngày chạy: 2026-10-02 (Asia/Ho_Chi_Minh)

Đây là kết quả trên môi trường development hiện có, không phải xác nhận DoD hoàn tất. Playwright đăng nhập bằng seed user và kiểm tra Dashboard ở desktop/mobile. Facebook OAuth đã hoàn tất sau khi tạo Meta app có use case Pages API; quyền Page được cấp và Page `Test mail` đã được chọn. Codex Test Connection trả về `Hello!`. Không tìm thấy Dataminer CSV trong workspace, Downloads hoặc Desktop, nên đã tạo một CSV một dòng theo cùng schema từ thông tin sản phẩm công khai trên Shopee để tiếp tục kiểm tra boundary/import. Bộ lọc nhận dòng này, nhưng ACCESSTRADE từ chối campaign chưa đăng ký; không có Product hay affiliate link nào được lưu. Không tạo dữ liệu sản phẩm, nội dung hay publication giả.

Ảnh Dashboard hiện trạng: [dashboard-current-state.png](dashboard-current-state.png). Ảnh chỉ chứng minh màn hình và trạng thái hiện tại, không phải bằng chứng cho một bài Facebook đã đăng.

Ảnh kiểm tra tiếp tục ngày 2026-10-02: [Product Library đang trống](product-library-empty.png) và [campaign Shopee đang Pending trên ACCESSTRADE](accesstrade-campaign-pending.png). Nội dung campaign ghi ACCESSTRADE tạm ngưng duyệt Publisher mới từ 26/05/2026 đến khi có thông báo mới; trường hợp đặc biệt cần liên hệ nhân sự phụ trách để được xem xét.

Codex Test Connection chạy lại trong phiên này thành công, trả `Hello!`: [ảnh kết quả](codex-test-connection.png).

| Bước | Kết quả | Bằng chứng / ghi chú |
|---:|---|---|
| 1 | PASS | Seed user `demo@affihub.local` tồn tại và đăng nhập được bằng credential dev mặc định. |
| 2 | PASS | Đăng nhập thành công qua Playwright; redirect tới Dashboard. |
| 3 | FAIL | Không kiểm tra được trạng thái ban đầu chưa kết nối; DB đã có Codex và ACCESSTRADE connection trước lần chạy này. |
| 4 | FAIL | Chưa chạy lại trọn OAuth/PKCE thật trong phiên e2e có bằng chứng lưu được. |
| 5 | PASS | Dashboard đọc AIConnection của demo user với trạng thái connected. |
| 6 | PASS | Chạy lại Test Connection thật trong phiên này; UI nhận `Codex responded: Hello!`. Ảnh: [Codex Test Connection](codex-test-connection.png). |
| 7 | PASS | Credential ACCESSTRADE thật từ ENV đã được lưu vào AffiliateConnection mã hóa. |
| 8 | FAIL | Import CSV cùng schema từ listing Shopee thật; row qua filter/rank nhưng lần gọi campaign ACCESSTRADE (`4751584435713464237`) trả về `You have not registered for campaign: Shopee Việt Nam Smartlink cho tất cả thiết bị`. Đã gửi yêu cầu tham gia; giao diện hiện `Pending`. Campaign ghi rõ đang tạm ngưng duyệt Publisher mới từ 26/05/2026; chỉ trường hợp đặc biệt được nhân sự phụ trách xem xét, nên chờ tự động không phải đường xử lý đáng tin cậy. Ảnh: [Product Library trống](product-library-empty.png), [campaign Pending](accesstrade-campaign-pending.png). Nguồn facts: [Shopee product listing](https://shopee.vn/Ng%C5%AF-C%E1%BB%91c-Granola-%C4%82n-Ki%C3%AAng-Nhi%E1%BB%81u-H%E1%BA%A1t-70-y%E1%BA%BFn-m%E1%BA%A1ch-H%C5%A9-500g-i.441745099.22873387114) và [shop listing](https://shopee.vn/anan_shop_mypham). |
| 9 | FAIL | ACCESSTRADE không cấp tracking link nên Product không được lưu. |
| 10 | FAIL | Không có Product affiliate URL; API trả về campaign chưa đăng ký. |
| 11 | FAIL | Chưa kiểm tra filter trên tập Product thật được import. |
| 12 | FAIL | Chưa kiểm tra điểm số với tập Product thật được import. |
| 13 | FAIL | Chưa có Product thật được import để chọn. |
| 14 | FAIL | Chưa tạo Content từ Product thật. |
| 15 | FAIL | Chưa kiểm tra nội dung Codex được sinh từ Product facts thật. |
| 16 | FAIL | Chưa có Content thật để xác minh affiliate URL được app gắn vào. |
| 17 | FAIL | Chưa có Content thật để xác minh trạng thái Review. |
| 18 | FAIL | Chưa có Content thật để review/edit. |
| 19 | FAIL | Chưa có Content thật để xác minh regenerate trên cùng bản. |
| 20 | FAIL | Chưa có Content thật để approve. |
| 21 | PASS | Meta OAuth hoàn tất bằng app `affihub-poc-pages`; app nhận các quyền `pages_show_list`, `pages_read_engagement`, `pages_manage_posts`. |
| 22 | PASS | Callback thật tạo SocialConnection Facebook cho demo user. |
| 23 | PASS | Discover Page gọi Meta Graph API thật và trả về Page `Test mail` (`1103223882865504`). |
| 24 | PASS | Chọn và lưu Page `Test mail` làm SocialDestination thành công. |
| 25 | FAIL | Chưa có Content Approved và SocialDestination thật để tạo Publication. |
| 26 | FAIL | Chưa tạo Publication thật để Post Now hoặc Schedule. |
| 27 | FAIL | Chưa enqueue job cho một Publication thật. |
| 28 | FAIL | Chưa có PublishJob thật để xác nhận claim atomic. |
| 29 | FAIL | Chưa chạy PublisherResolver với Publication thật. |
| 30 | FAIL | Chưa gọi Meta Graph API publish thật. |
| 31 | FAIL | Chưa có bài đăng thật trên Facebook Page. |
| 32 | FAIL | Chưa có provider response thật để xác nhận các trường publication result. |
| 33 | FAIL | Chưa có Publication Published thật; điều kiện bắt buộc của demo chính chưa đạt. |
| 34 | FAIL | Dashboard responsive và trạng thái kết nối đã được kiểm tra; chưa có recent Publication thật để đối chiếu status/thời gian. |

**Kết luận:** DoD chưa đạt. Facebook OAuth, Page discovery/selection và Codex Test Connection đã được xác minh runtime. Gate hiện tại là ACCESSTRADE chưa duyệt yêu cầu tham gia campaign Shopee (`Pending`), nên chưa thể tạo tracking link thật; các bước affiliate→content→publication phải chờ quyền campaign trước khi xác minh. Không thể suy ra thành công từ unit/request specs.
