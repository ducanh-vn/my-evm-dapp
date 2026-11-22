# Biểu mẫu: Đặc tả Kỹ thuật Smart Contract

- **Tên Contract:** `<ContractName.sol>`
- **Chuẩn kế thừa:** `<ERC20 / ERC721 / Ownable2Step / UUPSUpgradeable>`
- **Trạng thái:** `Nháp` | `Đang Audit` | `Sẵn sàng Deploy`

## 1. Mục đích & Vai trò trong hệ thống
- `<Mô tả nhiệm vụ chính của contract và cách tương tác với các contract khác>`

## 2. Biến trạng thái cốt lõi (Storage Variables)
| Tên biến | Kiểu dữ liệu | Visibility | Mô tả |
| :--- | :--- | :--- | :--- |
| `owner` | `address` | `public` | Ví Multisig quản trị hợp đồng |
| `balances` | `mapping(address => uint256)` | `public` | Số dư tài sản của từng người dùng |

## 3. Ma trận phân quyền các hàm (Access Control Matrix)
| Tên hàm | Visibility | Modifier quyền | Mô tả hành động | Event phát ra |
| :--- | :--- | :--- | :--- | :--- |
| `deposit(uint256)` | `external` | `nonReentrant`, `whenNotPaused` | Nạp token vào hợp đồng | `Deposited` |
| `withdraw(uint256)` | `external` | `nonReentrant` | Rút token khỏi hợp đồng | `Withdrawn` |
| `pause()` | `external` | `onlyOwner` | Tạm dừng khẩn cấp | `Paused` |

## 4. Kịch bản kiểm thử bắt buộc (Test Plan)
- [ ] **Happy Path:** Nạp và rút đúng số dư.
- [ ] **Revert Cases:** Nạp số lượng 0, rút quá số dư, gọi hàm admin từ ví thường.
- [ ] **Fuzz Test:** Thử nghiệm với 1,000+ giá trị `amount` ngẫu nhiên.
- [ ] **Reentrancy Test:** Thử tấn công gọi đệ quy vào hàm rút tiền.
