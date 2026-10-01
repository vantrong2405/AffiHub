# Design

## Context

Model khung `AffiliateConnection`/`Product` đã tồn tại từ change `01`. Xem `proposal.md` cho motivation. Reference bắt buộc: `tunguyendg/aff-pipeline` trước, fallback `Duke0503/shopee-aff` (kiến trúc worker/batch/tracking), rồi `bcat95/shopee-aff` (chi tiết Shopee-specific, phải phân loại Official/Unofficial/Reverse-engineered/Deprecated).

## Goals / Non-Goals

**Goals:**
- Import Product thật, filter/score chạy trên dữ liệu thật, không mock ở tầng integration.
- Giữ `original_product_url`/`affiliate_url` nguyên trạng từ provider, không app nào được sinh/sửa 2 field này ngoài Operation import.

**Non-Goals:**
- Không implement multi-affiliate-provider (chỉ ACCESSTRADE).
- Không implement background sync tự động theo lịch (import là action thủ công user bấm trong POC).

## Decisions

### 1. Operation + Client pattern (nhất quán với change 02)
`app/clients/accesstrade_client.rb` (PORO, chỉ I/O + parse response thô) + `app/operations/affiliate_products/import_operation.rb` (business rule: map field, giữ nullable, set `last_synced_at`, không tạo record khi lỗi).

### 2. Scoring là method thuần Ruby trên Product, không cần background job
Vì khối lượng Product trong POC nhỏ, scoring tính trực tiếp trong query/scope lúc filter (không cần precompute/cache), tránh thêm job thừa.

Alternative: precompute score bằng background job sau mỗi import. Bị loại — over-engineering cho khối lượng dữ liệu POC, thêm sau nếu cần (ponytail: thêm khi đo được chậm thật).

**Công thức score mặc định (chốt cụ thể, không để developer tự bịa khi implement)** — đã bị phát hiện qua review là thiếu tiêu chí: Porting Note (task 1.1) ưu tiên dùng công thức/trọng số thật nếu `tunguyendg/aff-pipeline` có định nghĩa rõ ràng; **nếu reference không có công thức cụ thể hoặc không áp dụng được**, dùng công thức mặc định sau (không phải để Porting Note "tự nghĩ ra bất kỳ thứ gì"):

```ruby
# Mỗi thành phần normalize về [0, 1] trước khi cộng trọng số — field nil bị LOẠI khỏi
# công thức (không coi là 0), trọng số của các field còn lại không đổi (không re-normalize
# lại tổng trọng số — đơn giản, chấp nhận score hơi thấp hơn khi thiếu field, không coi là bug).
score =
  0.4 * (rating.to_f / 5.0)                                    if rating.present?
  0.3 * [discount.to_f / 100.0, 1.0].min                        if discount.present?
  0.3 * Math.log10(sold.to_f + 1) / Math.log10(max_sold_seen + 1) if sold.present? && max_sold_seen.positive?
```
- `max_sold_seen = (Product.maximum(:sold) || 0)` — query 1 lần, KHÔNG dùng trực tiếp `Product.maximum(:sold)` làm biến (trả `nil` khi Library rỗng hoặc mọi Product có `sold` nil → gọi `.positive?` trên `nil` raise `NoMethodError`); luôn ép về `Integer` qua `|| 0` trước khi dùng — dùng log scale vì `sold` có thể chênh lệch rất lớn giữa sản phẩm hot và sản phẩm thường.
- **`max_sold_seen == 0`** (Library rỗng, hoặc mọi Product có `sold` 0/nil): `log10(max_sold_seen + 1) == log10(1) == 0`, chia 0 → `NaN`. Guard rõ: khi `max_sold_seen` không dương, thành phần `sold` bị LOẠI khỏi công thức hoàn toàn (coi như `sold.present?` false ở bước này), giống cách field nil bị loại — KHÔNG coi `sold = 0` là tham gia công thức với giá trị `0`. `score` vẫn luôn numeric, không bao giờ `NaN`.
- **Tie-breaker khi score bằng nhau**: sắp theo `last_synced_at DESC` (sản phẩm vừa sync gần nhất lên trước — dữ liệu mới hơn, đáng tin hơn), sau đó `id DESC` nếu vẫn bằng (đảm bảo thứ tự ổn định/deterministic giữa các lần query, không phụ thuộc thứ tự vật lý ngẫu nhiên của DB).
- `score` SHALL luôn là 1 giá trị numeric (không `nil`) — Product thiếu TẤT CẢ 3 field trên vẫn có `score = 0.0`, không bị loại khỏi danh sách (vẫn hiển thị, chỉ xếp cuối).

### 3. Upsert theo khoá (affiliate_provider, source_product_id), không tạo trùng
Import SHALL dùng `Product.find_or_initialize_by(affiliate_provider:, source_product_id:)` rồi update toàn bộ field — tránh tạo duplicate Product mỗi lần re-import cùng 1 sản phẩm. Hành vi phân trang khi ACCESSTRADE trả nhiều trang KHÔNG quyết định tại đây — đây là chi tiết phải lấy từ cách `tunguyendg/aff-pipeline` đã làm thật (Task 1.1 Porting Note). Nullable: field ACCESSTRADE không trả (vd `commission` có thể null cho vài merchant) SHALL được coi là "không tham gia scoring" (loại khỏi công thức) thay vì coi là 0 (0 có thể làm sai lệch ranking so với "không có dữ liệu"). Công thức `score` cụ thể đã chốt ở Decision 2.

**Atomicity của import: per-record, KHÔNG phải all-or-nothing cho cả batch** (đã bị phát hiện qua review là thiếu chốt) — nếu ACCESSTRADE trả 1 trang N sản phẩm và record thứ `k` lỗi (field bắt buộc thiếu nghiêm trọng, response sai định dạng cho riêng record đó...), `import_operation` SHALL vẫn giữ lại các record `1..k-1` ĐÃ lưu thành công (không rollback transaction toàn batch), tiếp tục xử lý record `k+1..N`, rồi báo cáo `imported_count`/`failed_count` theo TỪNG RECORD (không phải theo toàn request — 1 request có thể vừa có `imported_count > 0` vừa có `failed_count > 0` cùng lúc).

Lý do chọn per-record thay vì all-or-nothing: "Provider trả lỗi khi import" (Requirement đã có — lỗi ở tầng REQUEST, vd auth sai/rate limit toàn bộ API call) khác với "1 record trong response hợp lệ bị lỗi khi map/save" (lỗi cục bộ 1 record) — rollback cả batch vì 1 record lỗi sẽ vứt bỏ N-1 record hợp lệ đã có, không cần thiết và làm user phải import lại từ đầu mỗi lần ACCESSTRADE trả 1 record dữ liệu lạ. Alternative (transaction bọc cả batch, rollback toàn bộ nếu có ≥1 record lỗi): bị loại vì đánh đổi tệ hơn (mất dữ liệu hợp lệ) để đổi lấy "tất cả hoặc không gì" không có lợi ích rõ ràng cho use case import catalog sản phẩm.

## Risks / Trade-offs

- [ACCESSTRADE rate limit/quota giới hạn số lần import trong lúc dev/test] → Mitigation: lưu `raw_source_data` để không cần gọi lại API khi debug, xử lý lỗi rate limit như lỗi import thông thường.
- [`bcat95/shopee-aff` có thể chứa phần reverse-engineered không rõ license] → Mitigation: Porting Note phải phân loại rõ Official/Unofficial/Reverse-engineered/Deprecated trước khi quyết định port phần nào; phần Reverse-engineered/Deprecated không port code, chỉ học behavior rồi clean-room reimplement nếu thật sự cần.

## Migration Plan

Model đã có từ change 01; change này không cần migration mới trừ khi Porting Note phát hiện field còn thiếu so với response ACCESSTRADE thật — khi đó `add_column` bổ sung, không sửa migration change 01.
