# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository (EVM / Solidity Stack).

## Trạng thái dự án
- **Tên dự án:** EscrowVault (Hệ thống ký quỹ thanh toán tự động P2P)
- **Mục tiêu dự án:** Xây dựng giao thức ký quỹ phi tập trung cho phép người mua khóa tài sản (ERC20/ETH) vào hợp đồng thông minh và chỉ giải ngân cho người bán khi giao dịch hoàn tất hoặc được trọng tài xác nhận khi có tranh chấp.
- **Mạng triển khai dự kiến:** Base Sepolia (Testnet, Chain ID 84532) và Base Mainnet (Chain ID 8453).
- **Hiện trạng mã nguồn:** Đã khởi tạo Foundry (Foundry 1.10.0, solc 0.8.28 ghim trong `foundry.toml`, OpenZeppelin v5.7.0, forge-std v1.17.0 trong `lib/`).
  - Contract: `src/EscrowVault.sol`, interface `src/interfaces/IEscrowVault.sol`.
  - Test: `test/` (unit test theo luồng `EscrowVault.*.t.sol`, fuzz `EscrowVault.Fuzz.t.sol`, invariant `EscrowVault.invariant.t.sol` + `test/handlers/`, mock trong `test/mocks/`, setup chung `test/utils/BaseTest.sol`).
  - Remapping: `@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/` (trong `foundry.toml`).
  - Script deploy: `script/DeployEscrowVault.s.sol` (tham số đọc từ env, test tại `test/DeployEscrowVault.t.sol`). Checklist deploy: `docs/04-van-hanh/deploy-checklist-base-sepolia.md`.
  - Chưa có Frontend (`package.json`) hay Indexer.
- **Tech stack:** Solidity (Foundry / Hardhat) + OpenZeppelin + Next.js (Viem / Wagmi) + Indexer (Ponder / The Graph).
- **Lệnh vận hành (Foundry):**
  - Build contracts: `forge build`
  - Run tests: `forge test -vvv`
  - Gas report: `forge test --gas-report`
  - Storage layout: `forge inspect EscrowVault storageLayout`
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
