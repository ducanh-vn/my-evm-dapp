// Hook chạy tự động sau khi Claude Edit/Write file trong dự án EVM
const { execSync } = require('child_process');
const fs = require('fs');

let inputData = '';
process.stdin.on('data', chunk => {
  inputData += chunk;
});

process.stdin.on('end', () => {
  try {
    const event = JSON.parse(inputData);
    const filePath = event?.tool_input?.file_path || '';

    // 1. Nếu sửa file Solidity (.sol) -> tự động chạy forge fmt (nếu có foundry)
    if (filePath.endsWith('.sol')) {
      try {
        execSync('forge fmt', { stdio: 'ignore' });
        console.log(
          JSON.stringify({
            systemMessage:
              'Đã tự động chạy `forge fmt` cho file Solidity. Hãy chạy `forge test` sau khi hoàn tất cụm thay đổi để xác nhận không có lỗi biên dịch hoặc hồi quy.'
          })
        );
      } catch (e) {
        // Bỏ qua nếu máy chưa cài foundry
      }
    }

    // 2. Nếu sửa tài liệu trong docs/ -> nhắc cập nhật README.md
    if (filePath.includes('docs/') && !filePath.endsWith('README.md')) {
      console.log(
        JSON.stringify({
          systemMessage:
            'Nhắc nhở quy tắc docs-placement.md: Bạn vừa chỉnh sửa tài liệu trong docs/. Hãy cập nhật README.md của thư mục nhóm và docs/README.md!'
        })
      );
    }
  } catch (err) {
    // Bỏ qua lỗi parse JSON
  }
});
