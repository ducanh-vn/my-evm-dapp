# Danh sách địa chỉ Smart Contract đã triển khai

## 1. Local Network (Anvil - Chain ID: 31337)
- `EscrowVault`: deploy lại mỗi lần chạy Anvil (không cố định).

## 2. Testnet — Base Sepolia (Chain ID: 84532)

### EscrowVault
| Mục | Giá trị |
| :--- | :--- |
| Địa chỉ | [`0xEC01EeE5BEeA3Ab571F7aE31E70f9f479618560e`](https://sepolia.basescan.org/address/0xEC01EeE5BEeA3Ab571F7aE31E70f9f479618560e) |
| Tx deploy | [`0x07a69d628237f94bd664067e7f8a266cc306161c50d14398072c13732d9db944`](https://sepolia.basescan.org/tx/0x07a69d628237f94bd664067e7f8a266cc306161c50d14398072c13732d9db944) |
| Block deploy (start block cho Indexer) | `62219774` |
| Ngày deploy | 2026-11-22 |
| Mã nguồn | nhánh `feat/escrow-vault-mvp`, commit `137b285` (solc 0.8.28, optimizer 200 runs, EVM `cancun`) |
| Gas sử dụng | 2.135.915 |
| Deployer | `0xfc14501bDC2C4377EC81fF854906AE48B72ce053` (không có quyền gì sau deploy) |
| Verify Basescan | Chưa xác nhận (cần kiểm tra tab "Contract" trên Basescan) |

### Tham số constructor (đã đọc lại trên chain sau deploy)
| Tham số | Giá trị |
| :--- | :--- |
| `owner` | `0x4dba37cB320b902B4F53E9BDA0f1377820baBA91`: Gnosis Safe "EscrowVault Admin", v1.5.0, **1/1** (người ký `0xfc14…e053`) |
| `pendingOwner` | `0x0000000000000000000000000000000000000000` |
| `feeRecipient` | `0xC393509A9B2E668D908b2cDb461d3b097a1DA63A` (EOA) |
| `defaultArbiter` | `0x5A7EFfb94119e4bd04195c5Ee32bbA0aE4FeE9EF` (EOA) |
| `feeBps` | `100` (1%) |
| Token whitelist | USDC `0x036CbD53842c5426634e7929541eC2318f3dCF7e` (name/symbol `USDC`, 6 decimals) |
| `paused` | `false` |
| `MIN_DELIVERY_DURATION` | `86400` (1 ngày) |

> Safe 1/1 chỉ chấp nhận cho testnet. Mainnet bắt buộc Safe nhiều người ký (xem [checklist deploy](../04-van-hanh/deploy-checklist-base-sepolia.md)).

## 3. Mainnet — Base (Chain ID: 8453)
- `EscrowVault`: `<Chưa triển khai>`
