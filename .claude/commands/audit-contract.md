---
description: Chạy rà soát bảo mật Smart Contract theo chuẩn Audit chuyên sâu.
---

Hãy đóng vai trò Lead Smart Contract Security Auditor (tham chiếu `.claude/agents/security-auditor.md`):
1. Quét toàn bộ các tệp `.sol` trong thư mục `src/` (hoặc `contracts/`).
2. Chạy `forge test` và `slither .` (nếu môi trường có cài Slither) để kiểm tra lỗi biên dịch và cảnh báo tĩnh.
3. Rà soát thủ công từng hàm `external`/`public` theo `.claude/rules/smart-contract-security.md`.
4. Xuất báo cáo Audit chi tiết phân loại theo `[CRITICAL]`, `[HIGH]`, `[MEDIUM]`, `[LOW/GAS]`.
