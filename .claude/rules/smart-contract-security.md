# Quy tắc bảo mật Smart Contract (Solidity / EVM)

1. **Checks-Effects-Interactions (CEI):**
   - Mọi hàm thay đổi trạng thái hoặc chuyển ETH/Token **bắt buộc** kiểm tra điều kiện (`Checks`) -> cập nhật biến trạng thái (`Effects`) -> mới gọi ra contract bên ngoài (`Interactions`).
   - Sử dụng `ReentrancyGuard` (`nonReentrant`) của OpenZeppelin cho tất cả các hàm rút tiền, claim thưởng hoặc swap.
2. **Phân quyền (Access Control):**
   - Sử dụng `Ownable2Step` hoặc `AccessControl` của OpenZeppelin thay vì `Ownable` 1 bước.
   - **Cấm tuyệt đối** dùng `tx.origin` để xác thực người gọi.
   - Mọi hàm quản trị (`pause`, `unpause`, `setFee`, `upgradeTo`, `withdraw`) phải gắn modifier phân quyền và emit Event ngay khi thay đổi tham số.
3. **An toàn toán học & Vòng lặp:**
   - Khai báo rõ `pragma solidity ^0.8.20;` (hoặc phiên bản cố định, không dùng `^` nếu chuẩn bị audit).
   - Nhân trước chia sau để tránh mất độ chính xác làm tròn; sử dụng `Math.mulDiv` của OpenZeppelin khi tính toán tỷ lệ/phần trăm.
   - **Cấm** lặp (`for`/`while`) trên mảng động không giới hạn kích thước để tránh lỗi DoS Out-of-Gas.
4. **Tối ưu Gas & Chuẩn mã nguồn:**
   - Dùng **Custom Errors** (`error Unauthorized();`) thay cho chuỗi `require(..., "...")`.
   - Sắp xếp biến `storage` theo kích thước (32 bytes/slot) để tối ưu Storage Packing.
   - Áp dụng chuẩn NatSpec (`@notice`, `@dev`, `@param`, `@return`) cho mọi interface và hàm `public`/`external`.
