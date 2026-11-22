# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository (EVM / Solidity Stack).

## Trạng thái dự án
- **Mục tiêu dự án:** <TODO: Điền mô tả ngắn gọn mục tiêu dự án Blockchain / dApp>
- **Tech stack:** Solidity (Foundry / Hardhat) + OpenZeppelin + Next.js (Viem / Wagmi) + Indexer (Ponder / The Graph).
- **Lệnh vận hành (Foundry / Node):**
  - Build contracts: `forge build`
  - Run tests: `forge test -vvv`
  - Gas report: `forge test --gas-report`
  - Format Solidity: `forge fmt`

## Chính sách bắt buộc (luôn nạp)
@.claude/skills/policies/write-guard.md
@.claude/skills/plans/plan.md

## Rule trong `.claude/rules/` (MANDATORY)
Đọc file rule tương ứng trước khi làm việc thuộc phạm vi của nó:
- `smart-contract-security.md`: Quy tắc bảo mật Smart Contract Solidity (CEI, Access Control, Gas, Upgradeability).
- `onchain-offchain-boundary.md`: Ranh giới xử lý dữ liệu giữa On-chain và Off-chain/Indexer.
- `docs-placement.md`: Quy tắc phân loại tài liệu vào `docs/` và cập nhật mục lục `README.md`.
- `code-standards.md`: Quy chuẩn tổ chức module Frontend/Backend và giới hạn độ dài file.

## Slash Commands hỗ trợ nhanh
- `/new-contract <tên contract>`: Thiết kế đặc tả, lập kế hoạch và viết Smart Contract mới kèm Unit Test.
- `/audit-contract`: Kích hoạt Security Auditor rà soát bảo mật Smart Contract theo chuẩn SWC & OWASP.
- `/gas-report`: Phân tích chi phí Gas và đề xuất tối ưu Storage Packing.
- `/gen-deploy-checklist`: Tạo danh sách kiểm tra an toàn trước khi deploy lên Testnet/Mainnet.
- `/sync-docs`: Rà soát và đồng bộ lại toàn bộ mục lục `docs/README.md`.
