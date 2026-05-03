# CipherGuard — FHEVM Intelligence Layer for AI Coding Agents

> The AI skill that teaches agents to think in encrypted values —
> not just write FHE syntax, but reason about privacy, access
> control, and onchain confidentiality like a Zama engineer.

---

## What Is CipherGuard?

CipherGuard is a production-ready AI skill file system that enables
AI coding agents — Claude Code, Cursor, Windsurf, and similar tools
— to accurately build, test, and deploy confidential smart contracts
using the Zama FHEVM protocol.

When a developer drops CipherGuard into their AI coding environment
and prompts:

> "Write me a confidential voting contract using FHEVM"

The agent produces correct, working code — no hallucinated functions,
no missing `FHE.allowThis()`, no wrong config imports.

---

## The Problem CipherGuard Solves

AI agents today have zero built-in knowledge of FHEVM. They hallucinate:
- Functions that don't exist (`FHE.gte`, `ZamaSepoliaConfig`)
- Missing permission calls (`FHE.allowThis`)
- Wrong patterns (plaintext if/else on encrypted values)
- Incorrect type signatures (encrypted divisors in `FHE.div`)

CipherGuard eliminates all of these with a 5-layer knowledge system
built from real FHEVM development experience.

---

## 5-Layer Architecture
Layer 1 — Foundation
FHE mental model, architecture, encrypted types,
access control concepts, environment setup

Layer 2 — Operations
Every FHE function with correct signatures,
arithmetic, comparison, conditional logic,
type casting, random generation

Layer 3 — Patterns
6 production contract templates agents can adapt:
vault, voting, selective disclosure, ERC-7984,
auction, credit score

Layer 4 — Anti-Patterns
12 real mistakes with corrections discovered
during actual FHEVM development — the most
common agent failures eliminated

Layer 5 — Workflow
Full dev workflow: setup → write → test →
deploy → frontend → verify
---

## File Structure
cipherguard/
├── SKILL.md                      ← Drop this into Cursor/Claude Code
├── README.md                     ← This file
│
├── layers/
│   ├── 01-foundation.md          ← FHE mental model + types
│   ├── 02-operations.md          ← Every FHE function
│   ├── 03-patterns.md            ← 6 contract templates
│   ├── 04-antipatterns.md        ← 12 real mistakes + fixes
│   └── 05-workflow.md            ← Full dev workflow
│
├── examples/
│   ├── confidential-vault.sol    ← Private savings vault
│   ├── confidential-voting.sol   ← Private voting system
│   ├── confidential-erc7984.sol  ← Confidential token standard
│   ├── confidential-score.sol    ← FHE credit scoring
│   └── frontend-integration.ts  ← Full SDK integration
│
└── templates/
└── hardhat.config.ts         ← Ready-to-use config
---

## How to Use CipherGuard

### In Cursor

1. Copy `SKILL.md` into your project root
2. Open Cursor Agent panel
3. Type `@SKILL.md` to attach it as context
4. Prompt naturally:
Using @SKILL.md, write me a confidential voting contract
where votes are encrypted and only the tally is revealed
after voting ends

### In Claude Code

1. Copy `SKILL.md` into your project root
2. Start a session and reference it:
Read SKILL.md first, then help me build a confidential
ERC-7984 token with encrypted balances and private transfers

### In Windsurf

1. Add `SKILL.md` to your workspace
2. Use it as context in Cascade:
@SKILL.md Build me a confidential auction where bids
are encrypted and the winner is determined in FHE
---

## What CipherGuard Teaches Agents

### Correct Patterns

```solidity
// ✅ Correct config import
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
contract MyContract is ZamaEthereumConfig { }

// ✅ Correct encrypted input
function deposit(
    externalEuint64 encryptedAmount,
    bytes calldata inputProof
) external {
    euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
    _balance[msg.sender] = FHE.add(_balance[msg.sender], amount);
    FHE.allowThis(_balance[msg.sender]); // never forget this
    FHE.allow(_balance[msg.sender], msg.sender);
}

// ✅ Correct comparison
ebool sufficient = FHE.ge(_balance[msg.sender], uint64(1000));

// ✅ Correct conditional
_balance[msg.sender] = FHE.select(
    sufficient,
    FHE.sub(_balance[msg.sender], amount),
    _balance[msg.sender]
);
```

### Anti-Patterns Eliminated

```solidity
// ❌ Does not exist
import { ZamaSepoliaConfig } ...
FHE.gte(_balance, encAmt)
FHE.div(encA, encB)

// ❌ Wrong pattern
if (_balance[user] >= amount) { } // cannot use encrypted in if/else
function compute() external view returns (ebool) { } // view + FHE = error

// ❌ Missing permissions
_balance[user] = FHE.add(_balance[user], amount);
// Missing: FHE.allowThis() — contract loses access forever
```

---

## Validation Results

CipherGuard was tested with Cursor on the following prompts:

| Prompt | Result |
|---|---|
| "Write a confidential vault with deposit and withdraw" | ✅ Compiles first try |
| "Build a private voting contract" | ✅ Compiles first try |
| "Create an ERC-7984 confidential token" | ✅ Compiles first try |
| "Compute a credit score privately with FHE" | ✅ Compiles first try |
| "Write a confidential auction" | ✅ Compiles first try |

Without CipherGuard — same prompts produced:
- `ZamaSepoliaConfig` import errors
- Missing `FHE.allowThis()` silent failures
- `FHE.gte` does not exist errors
- `view` modifier conflicts with FHE operations

---

## Sepolia Contract Addresses

| Contract | Address |
|---|---|
| ACL | `0xf0Ffdc93b7E186bC2f8CB3dAA75D86d1930A433D` |
| Coprocessor | `0x92C920834Ec8941d2C77D188936E1f7A6f49c127` |
| KMS Verifier | `0xbE0E383937d564D7FF0BC3b46c51f0bF8d5C311A` |
| cUSDT Mock | `0x4E7B06D78965594eB5EF5414c357ca21E1554491` |

---

## Built For

Zama Developer Program — Bounty Track Season 2
Deadline: May 10, 2026

---

## License

BSD-3-Clause-Clear
