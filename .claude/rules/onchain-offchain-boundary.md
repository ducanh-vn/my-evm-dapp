# Ranh giới On-chain vs Off-chain (EVM Architecture)

1. **Những gì lưu On-chain (Smart Contract):**
   - Quyền sở hữu tài sản, số dư, trạng thái ký quỹ (escrow), tỷ lệ chia thưởng, chữ ký xác thực (EIP-712) và các tham số ảnh hưởng trực tiếp tới tiền.
   - Mọi thay đổi trạng thái quan trọng **phải emit Event** kèm `indexed` cho các trường cần lọc (tối đa 3 `indexed` parameters/event).
2. **Những gì lưu Off-chain (Database / IPFS / Indexer):**
   - Metadata mô tả dài, hình ảnh, lịch sử giao dịch phục vụ phân trang/tìm kiếm, bảng xếp hạng không ảnh hưởng trực tiếp tới phân chia tài sản.
   - Không viết hàm `view` trả về mảng hàng nghìn phần tử trên contract chỉ để phục vụ hiển thị Frontend; hãy dùng Indexer (Ponder / The Graph) để truy vấn.
