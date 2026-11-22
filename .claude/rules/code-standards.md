# Quy chuẩn kiến trúc & tổ chức mã nguồn (Off-chain / dApp)

1. **Tách biệt trách nhiệm (Modular Architecture):**
   - Frontend/Backend tách rõ: `src/types/`, `src/constants/` (chứa ABI & Contract Addresses), `src/lib/`, `src/hooks/` (chứa Wagmi/Viem hooks), và `src/components/`.
   - Không gọi trực tiếp RPC/Contract bên trong file giao diện UI component; phải đóng gói qua custom hooks.
2. **Giới hạn độ dài tệp:**
   - File Component giao diện không vượt quá **350 dòng**.
   - File Page hoặc Orchestrator điều phối không vượt quá **250 dòng**.
3. **Xử lý giao dịch Web3:**
   - Luôn tách biệt 2 trạng thái: chờ người dùng ký ví (`isPending`) và chờ xác nhận block (`isConfirming`), kèm xử lý lỗi từ chối giao dịch (`UserRejectedRequestError`) hoặc revert từ contract.
