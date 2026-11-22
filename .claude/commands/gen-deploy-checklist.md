---
description: Tạo checklist an toàn trước khi triển khai Smart Contract lên Testnet/Mainnet.
---

Hãy tạo danh sách kiểm tra trước khi triển khai (Pre-Deployment Checklist) dựa trên trạng thái hiện tại của dự án:
1. Kiểm tra 100% test cases (`forge test`) đã pass và độ phủ code (coverage).
2. Kiểm tra danh sách tham số `constructor` / `initialize` (địa chỉ token, địa chỉ ví Multisig Admin, phí giao dịch).
3. Kiểm tra quy trình chuyển quyền sở hữu (`transferOwnership` sang Gnosis Safe Multisig) ngay sau khi deploy.
4. Kiểm tra cấu hình verify source code trên Block Explorer (Etherscan/Basescan/Arbiscan).
5. Cập nhật địa chỉ contract mới vào `docs/02-ky-thuat/contract-addresses.md`.
