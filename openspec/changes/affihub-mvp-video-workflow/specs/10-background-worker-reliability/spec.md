# Spec Delta

## Purpose

Đảm bảo worker dài hạn chỉ thực hiện side effect khi còn sở hữu claim hợp lệ, đồng thời phát hiện và phục hồi job bị bỏ dở sau khi worker hoặc app dừng.

## ADDED Requirements

### Requirement: Claim nguyên tử cho job có side effect
AffiHub MUST claim mỗi job bằng transition nguyên tử theo trạng thái hiện tại, lease, heartbeat và fencing token dùng chung cho worker dài hạn.

#### Scenario: Hai worker cùng nhận job
- **WHEN** hai worker đồng thời thử claim cùng một job
- **THEN** chỉ một worker sở hữu lease và job chỉ được gửi một lần tới side effect kế tiếp

### Requirement: Ghi bền attempt trước side effect ngoài
Trước request có thể tạo side effect, AffiHub MUST lưu operation/attempt ID, stage và trạng thái `Submitting`; dùng provider idempotency key ổn định nếu API hỗ trợ. Khi attempt có thể đã rời process, worker mới MUST reconcile attempt đó và không tạo attempt thứ hai cho cùng bước cho tới khi kết quả được xác định.

#### Scenario: Worker mới nhận job khi request cũ đang gửi
- **WHEN** lease hết hạn trong lúc attempt ở trạng thái `Submitting`
- **THEN** worker mới giữ attempt cũ, đối soát hoặc chuyển `OutcomeUnknown`, không phát request thứ hai chỉ vì đã có fencing token mới

### Requirement: Worker cũ không được claim side effect mới sau khi mất lease
Worker MUST xác minh fencing token còn hiệu lực trước transition nội bộ và trước khi tạo attempt; worker mất lease MUST không được claim side effect tiếp theo. Fencing nội bộ không được coi là provider-side idempotency; attempt đã tạo phải qua quy trình reconcile riêng.

#### Scenario: Lease hết hạn trong lúc xử lý
- **WHEN** worker cũ tiếp tục sau khi worker khác đã claim lại job
- **THEN** fencing token từ chối transition hoặc attempt mới của worker cũ, còn mọi attempt đã được lưu vẫn chỉ được reconcile theo cùng attempt ID

### Requirement: Phục hồi job bị treo có đối soát
AffiHub MUST dùng sweeper để phát hiện lease quá hạn và đánh dấu job cần phục hồi hoặc đối soát thay vì để `Rendering`, `Uploading` hoặc `Generating` vô thời hạn.

#### Scenario: Job mất heartbeat
- **WHEN** lease hết hạn mà không có heartbeat hợp lệ
- **THEN** sweeper ghi nhận job stale, nêu worker/stage cuối và chỉ enqueue worker mới sau khi xác định side effect trước đó chưa chạy hoặc đã được reconcile

### Requirement: Khôi phục checkpoint sau restart
Worker MUST tiếp tục từ checkpoint bền vững gần nhất; nếu không thể xác định liệu side effect đã xảy ra, job MUST chuyển `OutcomeUnknown` và chờ reconcile.

#### Scenario: App restart sau khi upload một phần
- **WHEN** app khởi động lại sau khi remote upload đã tiến tới một checkpoint được lưu
- **THEN** worker mới resume hoặc poll từ checkpoint đó, không khởi tạo upload/publish/reply mới

#### Scenario: Không có checkpoint hoặc remote reference
- **WHEN** worker không thể xác định bước remote đã hoàn tất hay chưa
- **THEN** job chuyển `OutcomeUnknown` và chặn retry cho tới khi dùng được quy trình đối soát

### Requirement: Xử lý thủ công side effect không thể reconcile
Khi API/provider không thể phân định `OutcomeUnknown`, AffiHub MUST yêu cầu người dùng chọn kết quả đã xảy ra, chắc chắn chưa xảy ra hoặc vẫn chưa rõ và lưu bằng chứng/decision.

#### Scenario: Người dùng xác nhận đã xảy ra
- **WHEN** người dùng mở destination/provider và ghi nhận side effect đã xảy ra
- **THEN** AffiHub lưu URL/reference cùng bằng chứng ở trạng thái `ManualOutcomeConfirmed` mà không giả thành provider-confirmed success

#### Scenario: Người dùng xác nhận chắc chắn chưa xảy ra
- **WHEN** người dùng ghi nhận side effect chưa xảy ra, xác nhận rủi ro retry, worker/sender cũ đã được xác nhận dừng và cửa sổ request tối đa đã hết nếu request có thể đã rời process
- **THEN** AffiHub cho retry có audit record về người xác nhận, thời điểm, lý do và side effect được retry

#### Scenario: Người dùng vẫn chưa rõ
- **WHEN** người dùng chưa thể xác định side effect có xảy ra hay không
- **THEN** AffiHub giữ `OutcomeUnknown` và tiếp tục chặn retry

### Requirement: Audit báo worker và lease stale
Preflight MUST phát hiện job đang chạy vượt lease/heartbeat và báo stage, worker cuối cùng cùng hành động phục hồi.

#### Scenario: Audit gặp job stale
- **WHEN** project có job `Rendering`, `Uploading` hoặc `Generating` đã quá hạn
- **THEN** audit đánh dấu `Chặn` hoặc `Chưa thể kiểm tra` cho luồng phụ thuộc và cung cấp hành động reconcile

### Requirement: Che secret và URL upload khỏi log
AffiHub MUST redact access/refresh token, API key, authorization header, signed upload URL/session URI và provider error/payload chứa các giá trị đó khỏi log và thông báo vận hành.

#### Scenario: Upload lỗi có URI hoặc secret
- **WHEN** provider trả lỗi có chứa credential hoặc signed upload/session URI
- **THEN** log và Telegram alert chỉ lưu thông tin đã redact cùng mã lỗi an toàn
