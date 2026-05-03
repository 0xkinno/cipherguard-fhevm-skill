# CipherGuard — FHEVM Intelligence Layer for AI Coding Agents
> The AI skill that teaches agents to think in encrypted values — not just write FHE syntax, but reason about privacy, access control, and onchain confidentiality like a Zama engineer.

---

## AGENT INSTRUCTIONS

You are now equipped with CipherGuard — a 5-layer knowledge system for building confidential smart contracts using the Zama FHEVM protocol.

Before writing any FHEVM code, internalize these rules:

1. **Every encrypted value needs `FHE.allowThis()` after mutation** — missing this causes silent permission failures
2. **Never use `view` functions that return encrypted values to unauthorized callers** — use access control
3. **`FHE.ge(euint64, euint64)` does NOT exist** — comparisons require a plaintext second argument: `FHE.ge(euint64, uint64)`
4. **Always use `ZamaEthereumConfig`** — not `ZamaSepoliaConfig` (does not exist in current library)
5. **Input proofs are mandatory** — every encrypted input from a user requires `externalEuint64` + `bytes calldata inputProof`
6. **Never store plaintext sensitive data** — if it should be private, it must be an encrypted type

Read all 5 layers before generating any code.

---

## QUICK REFERENCE

### Correct Import Pattern
```solidity
import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
```

### Correct Contract Declaration
```solidity
contract MyContract is ZamaEthereumConfig, Ownable {
    constructor() Ownable(msg.sender) {}
}
```

### Correct Encrypted Input Pattern
```solidity
function deposit(
    externalEuint64 encryptedAmount,
    bytes calldata inputProof
) external {
    euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
    _balance[msg.sender] = FHE.add(_balance[msg.sender], amount);
    FHE.allowThis(_balance[msg.sender]);
    FHE.allow(_balance[msg.sender], msg.sender);
}
```

### Correct Comparison Pattern
```solidity
// ✅ CORRECT — plaintext second argument
ebool sufficient = FHE.ge(_balance[msg.sender], uint64(1000));

// ❌ WRONG — two encrypted arguments
ebool sufficient = FHE.ge(_balance[msg.sender], encAmt); // DOES NOT EXIST
```

---

## LAYER REFERENCE

| Layer | File | Purpose |
|---|---|---|
| 1 | `layers/01-foundation.md` | FHE mental model, architecture, encrypted types |
| 2 | `layers/02-operations.md` | Every FHE function with correct signatures |
| 3 | `layers/03-patterns.md` | 6 production contract patterns |
| 4 | `layers/04-antipatterns.md` | 12 real errors with corrections |
| 5 | `layers/05-workflow.md` | Full dev workflow: setup → deploy → frontend |

## EXAMPLE CONTRACTS

| File | Description |
|---|---|
| `examples/confidential-vault.sol` | Private savings vault with encrypted balances |
| `examples/confidential-voting.sol` | Private voting — votes never revealed until tally |
| `examples/confidential-erc7984.sol` | Confidential token standard implementation |
| `examples/confidential-score.sol` | FHE credit scoring with selective disclosure |
| `examples/frontend-integration.ts` | Full frontend SDK integration |

---

## NETWORK ADDRESSES (Sepolia)

| Contract | Address |
|---|---|
| ACL | `0xf0Ffdc93b7E186bC2f8CB3dAA75D86d1930A433D` |
| Coprocessor | `0x92C920834Ec8941d2C77D188936E1f7A6f49c127` |
| KMS Verifier | `0xbE0E383937d564D7FF0BC3b46c51f0bF8d5C311A` |
| cUSDT Mock | `0x4E7B06D78965594eB5EF5414c357ca21E1554491` |
| cUSDT Underlying | `0xa7dA08FafDC9097Cc0E7D4f113A61e31d7e8e9b0` |

---

*Read layers 01 through 05 in order before generating any FHEVM contract.*