import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Tests never write to the real development ledger or fill the console with usage lines.
// Each test file gets its own empty ledger directory, so spend from one file never
// counts against another.
process.env.RR_USAGE_LOG_DIR = mkdtempSync(join(tmpdir(), "rr-usage-"));
process.env.AI_USAGE_LOG = "off";
