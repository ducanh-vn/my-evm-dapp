# Biểu mẫu: Đặc tả Quy trình Nghiệp vụ (dApp / Web3 Flow)

- **Tên tính năng / Quy trình:** `<Điền tên tính năng>`
- **Trạng thái:** `Nháp` | `Đang duyệt` | `Đã chốt`

## 1. Mục tiêu & Tác nhân (Actors)
- **Mục tiêu nghiệp vụ:** `<Giải quyết bài toán gì?>`
- **Các vai trò tham gia:** `<User Wallet, Admin Multisig, Backend Relayer, Indexer>`

## 2. Luồng xử lý On-chain & Off-chain
1. **Frontend:** Người dùng ký duyệt (Approve ERC20 hoặc ký EIP-712) trên ví.
2. **Smart Contract:** Thực thi giao dịch và phát sự kiện (`Event`).
3. **Indexer:** Lắng nghe sự kiện, cập nhật dữ liệu vào PostgreSQL.
4. **Frontend:** Cập nhật trạng thái giao dịch thành công cho người dùng.

## 3. Tiêu chí nghiệm thu (Acceptance Criteria)
- [ ] Giao dịch hiển thị đúng ước tính phí gas và trạng thái chờ xác nhận.
- [ ] Indexer đồng bộ dữ liệu chính xác sau khi giao dịch đạt finality.
