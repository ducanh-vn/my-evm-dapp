// Sao chép ABI EscrowVault từ artifact Foundry (../out) sang src/constants/escrowVaultAbi.ts.
// Chạy sau mỗi lần `forge build` khi contract đổi: npm run sync-abi
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const artifact = join(here, "..", "..", "out", "EscrowVault.sol", "EscrowVault.json");
const target = join(here, "..", "src", "constants", "escrowVaultAbi.ts");

const { abi } = JSON.parse(readFileSync(artifact, "utf8"));
const body =
  "// FILE SINH TỰ ĐỘNG bởi scripts/sync-abi.mjs từ out/EscrowVault.sol/EscrowVault.json. Không sửa tay.\n" +
  `export const escrowVaultAbi = ${JSON.stringify(abi, null, 2)} as const;\n`;
writeFileSync(target, body);
console.log(`ABI: ${abi.length} entries -> ${target}`);
