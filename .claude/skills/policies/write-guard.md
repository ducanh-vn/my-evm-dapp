# Policy: Write Guard (Bảo vệ thao tác ghi & triển khai)

1. **Bảo mật khóa bí mật:** Không bao giờ yêu cầu, đọc, in ra hoặc hardcode Private Key, Mnemonic, Seed Phrase hay API Key RPC vào mã nguồn hoặc file test.
2. **Không giả định:** Không tự bịa địa chỉ contract, ABI, lệnh Foundry/Hardhat hoặc biến môi trường khi chưa đọc file cấu hình thực tế (`foundry.toml`, `hardhat.config.ts`, `package.json`).
3. **Đọc trước khi sửa:** Luôn đọc nội dung file hiện tại trước khi chỉnh sửa.
4. **Cấm tự ý Deploy:** Tuyệt đối không chạy lệnh broadcast giao dịch lên Testnet/Mainnet; chỉ chạy kiểm thử trên môi trường local (`forge test`, `anvil`).
