# Proposal

## Precondition

- Change `01` đến `06` phải **tất cả** ở trạng thái `archived` (`openspec list --json` không còn change nào trong 6 change đó ở trạng thái `in-progress`) trước khi bắt đầu change này — đây là gate cứng, không phải gợi ý: task 1.1 của `tasks.md` kiểm tra điều này trước khi cho phép code Dashboard, không dựa vào tự giác.

## Why

Sau khi 6 change trước (01–06) archive xong, từng capability đã chạy thật riêng lẻ. `docs/PROJECT_SPEC.md` quy định POC không được coi là Done nếu chỉ từng phần chạy riêng lẻ — cần 1 Dashboard tổng hợp trạng thái và 1 lượt verify toàn chuỗi 34-bước DoD thật trước khi coi vertical slice hoàn thành.

## What Changes

- Implement Dashboard: status Codex/ACCESSTRADE/Facebook connected + recent publications.
- Verify thủ công toàn chuỗi 34-bước DoD theo `docs/PROJECT_SPEC.md` §POC Definition of Done, từ login đến Publication Published thật trên Facebook.
- **BREAKING**: không áp dụng.

## Capabilities

### New Capabilities

(không có — Dashboard chỉ tổng hợp dữ liệu đã có từ 6 capability trước, không thêm behavior nghiệp vụ mới; `skip_specs: true` đã khai báo trong `.openspec.yaml`)

### Modified Capabilities

(không có)

## Impact

- **Code**: `affihub/app/controllers/dashboard_controller.rb`, `affihub/app/views/dashboard/*`.
- **Phụ thuộc**: toàn bộ change `01`–`06` phải archive xong trước khi bắt đầu change này.
