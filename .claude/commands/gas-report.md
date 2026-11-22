---
description: Chạy đo lường chi phí Gas và đề xuất tối ưu hóa Smart Contract.
---

Hãy thực hiện phân tích tối ưu Gas:
1. Chạy lệnh `forge test --gas-report` để thu thập số liệu gas deployment và gas thực thi từng hàm.
2. Phân tích bố cục bộ nhớ của các contract chính bằng `forge inspect <ContractName> storage-layout`.
3. Đề xuất các điểm tối ưu: gom biến vào cùng slot 32-byte (Storage Packing), dùng `calldata` thay `memory` cho tham số mảng/struct chỉ đọc, dùng `unchecked` ở các phép tăng biến đếm vòng lặp an toàn, và chuyển sang Custom Errors.
