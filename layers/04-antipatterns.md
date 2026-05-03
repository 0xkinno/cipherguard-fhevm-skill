# Layer 4 — Anti-Patterns: 12 Real FHEVM Mistakes and Corrections

These 12 mistakes were discovered during real FHEVM development.
Every agent using CipherGuard must check code against this list
before outputting any FHEVM contract.

---

## Mistake 1 — Wrong Config Import

❌ WRONG:
```solidity
import { ZamaSepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
contract MyContract is ZamaSepoliaConfig { }
```

✅ CORRECT:
```solidity
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
contract MyContract is ZamaEthereumConfig { }
```

**Why:** `ZamaSepoliaConfig` does not exist in the current library.
`ZamaEthereumConfig` handles both Ethereum mainnet and Sepolia
automatically based on `block.chainid`.

---

## Mistake 2 — Missing FHE.allowThis()

❌ WRONG:
```solidity
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    _balance[msg.sender] = FHE.add(_balance[msg.sender], amount);
    // Missing FHE.allowThis — contract loses access to this value
}
```

✅ CORRECT:
```solidity
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    _balance[msg.sender] = FHE.add(_balance[msg.sender], amount);
    FHE.allowThis(_balance[msg.sender]); // contract keeps access
    FHE.allow(_balance[msg.sender], msg.sender); // user can decrypt
}
```

**Why:** Every time an encrypted value is written or updated,
permissions reset. Without `FHE.allowThis()` the contract
cannot use that value in any future transaction.
This is the #1 cause of silent FHEVM failures.

---

## Mistake 3 — Using FHE.gte() Instead of FHE.ge()

❌ WRONG:
```solidity
ebool sufficient = FHE.gte(_balance[msg.sender], encAmt);
```

✅ CORRECT:
```solidity
// Two encrypted values
ebool sufficient = FHE.ge(_balance[msg.sender], encAmt);

// Encrypted vs plaintext
ebool sufficient = FHE.ge(_balance[msg.sender], uint64(1000));
```

**Why:** `FHE.gte()` does not exist. The correct function
is `FHE.ge()`. Same applies to `lte` → use `le`.

---

## Mistake 4 — Plaintext if/else on Encrypted Values

❌ WRONG:
```solidity
function withdraw(uint64 amount) external {
    // Cannot compare encrypted balance to plaintext this way
    if (_balance[msg.sender] >= amount) {
        _balance[msg.sender] = FHE.sub(_balance[msg.sender], amount);
    }
}
```

✅ CORRECT:
```solidity
function withdraw(
    externalEuint64 encAmount,
    bytes calldata proof
) external {
    euint64 amount = FHE.fromExternal(encAmount, proof);
    ebool sufficient = FHE.ge(_balance[msg.sender], amount);
    _balance[msg.sender] = FHE.select(
        sufficient,
        FHE.sub(_balance[msg.sender], amount),
        _balance[msg.sender]
    );
    FHE.allowThis(_balance[msg.sender]);
    FHE.allow(_balance[msg.sender], msg.sender);
}
```

**Why:** Encrypted values cannot be used in plaintext
conditionals. All branching logic must use `FHE.select()`.

---

## Mistake 5 — Returning Encrypted Values from View Functions
to Unauthorized Callers

❌ WRONG:
```solidity
// Anyone can call this and get the encrypted handle
function getBalance() external view returns (euint64) {
    return _balance[msg.sender];
}
```

✅ CORRECT:
```solidity
function getBalance(address user) external view returns (euint64) {
    // Still returns handle but check permission first
    require(
        FHE.isAllowed(_balance[user], msg.sender),
        "Not authorized"
    );
    return _balance[user];
}
```

**Why:** While the encrypted handle does not reveal the value,
best practice requires permission checks before returning
encrypted handles to callers.

---

## Mistake 6 — Using Plain uint64 for User Input Instead of externalEuint64

❌ WRONG:
```solidity
function deposit(uint64 amount) external {
    euint64 encAmount = FHE.asEuint64(amount);
    // amount was visible onchain — defeats the purpose of FHE
}
```

✅ CORRECT:
```solidity
function deposit(
    externalEuint64 encryptedAmount,
    bytes calldata inputProof
) external {
    euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
    // amount was encrypted client-side — never visible onchain
}
```

**Why:** If the user passes a plaintext amount, it appears
in the transaction calldata and is visible to everyone.
Always use `externalEuint64` + `inputProof` for private inputs.

---

## Mistake 7 — Dividing by an Encrypted Value

❌ WRONG:
```solidity
// This function does not exist
euint64 result = FHE.div(encNumerator, encDenominator);
```

✅ CORRECT:
```solidity
// Divisor must be plaintext
euint64 result = FHE.div(encNumerator, uint64(10000));
```

**Why:** `FHE.div(euint64, euint64)` does not exist.
Division only supports a plaintext divisor.
Same rule applies to `FHE.rem()`.

---

## Mistake 8 — Forgetting to Allow Recipient in Transfers

❌ WRONG:
```solidity
function transfer(address to, externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    _balance[to] = FHE.add(_balance[to], amount);
    FHE.allowThis(_balance[to]);
    // Missing: FHE.allow(_balance[to], to)
    // Recipient cannot decrypt their own balance
}
```

✅ CORRECT:
```solidity
function transfer(address to, externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    _balance[to] = FHE.add(_balance[to], amount);
    FHE.allowThis(_balance[to]);
    FHE.allow(_balance[to], to); // recipient can decrypt
}
```

**Why:** `FHE.allowThis()` only gives the contract permission.
The recipient also needs `FHE.allow()` to decrypt their balance.

---

## Mistake 9 — Not Initializing Encrypted Mapping Values

❌ WRONG:
```solidity
function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    // On first deposit _balance[msg.sender] is uninitialized (zero handle)
    // Adding to uninitialized euint64 causes unexpected behavior
    _balance[msg.sender] = FHE.add(_balance[msg.sender], amount);
}
```

✅ CORRECT:
```solidity
mapping(address => bool) public hasDeposited;

function deposit(externalEuint64 enc, bytes calldata proof) external {
    euint64 amount = FHE.fromExternal(enc, proof);
    if (!hasDeposited[msg.sender]) {
        _balance[msg.sender] = amount; // initialize directly
        hasDeposited[msg.sender] = true;
    } else {
        _balance[msg.sender] = FHE.add(_balance[msg.sender], amount);
    }
    FHE.allowThis(_balance[msg.sender]);
    FHE.allow(_balance[msg.sender], msg.sender);
}
```

**Why:** Uninitialized encrypted mappings return a zero handle.
Adding to a zero handle may produce unexpected results.
Always track initialization with a bool mapping.

---

## Mistake 10 — Using Wrong Solidity Version or EVM Version

❌ WRONG:
```solidity
pragma solidity ^0.8.20;
// hardhat.config.ts — evmVersion not set
```

✅ CORRECT:
```solidity
pragma solidity ^0.8.24;
```

```typescript
// hardhat.config.ts
solidity: {
  version: "0.8.24",
  settings: {
    optimizer: { enabled: true, runs: 200 },
    evmVersion: "cancun", // required for FHEVM
  },
},
```

**Why:** FHEVM requires Solidity 0.8.24+ and the Cancun
EVM version for transient storage opcodes used internally.

---

## Mistake 11 — Calling FHE Operations in View Functions

❌ WRONG:
```solidity
// view functions cannot call state-changing FHE operations
function checkEligibility(uint64 threshold) external view returns (ebool) {
    return FHE.ge(_score[msg.sender], threshold); // FHE.ge is not pure/view
}
```

✅ CORRECT:
```solidity
// Remove view modifier — FHE operations change state
function checkEligibility(uint64 threshold) external returns (ebool) {
    ebool result = FHE.ge(_score[msg.sender], threshold);
    FHE.allowThis(result);
    FHE.allow(result, msg.sender);
    return result;
}
```

**Why:** FHE operations update the ACL (Access Control List)
which is a state change. Functions using FHE operations
cannot be marked `view` or `pure`.

---

## Mistake 12 — Missing inputProof Parameter

❌ WRONG:
```solidity
function submit(externalEuint64 encryptedValue) external {
    euint64 value = FHE.fromExternal(encryptedValue); // missing proof
}
```

✅ CORRECT:
```solidity
function submit(
    externalEuint64 encryptedValue,
    bytes calldata inputProof  // always required
) external {
    euint64 value = FHE.fromExternal(encryptedValue, inputProof);
}
```

**Why:** `FHE.fromExternal()` always requires two arguments —
the encrypted handle AND the input proof. The proof verifies
the ciphertext was generated correctly by the user.
Missing it causes a compilation error.

---

## Agent Self-Check Checklist

Before outputting any FHEVM contract, verify:

- [ ] Import uses `ZamaEthereumConfig` not `ZamaSepoliaConfig`
- [ ] Every encrypted value update followed by `FHE.allowThis()`
- [ ] Every user-facing value followed by `FHE.allow(value, user)`
- [ ] No plaintext `if/else` on encrypted values — use `FHE.select()`
- [ ] All user inputs use `externalEuint64` + `bytes calldata inputProof`
- [ ] No `FHE.div(enc, enc)` — divisor must be plaintext
- [ ] No `FHE.gte()` — correct function is `FHE.ge()`
- [ ] No `view` modifier on functions that call FHE operations
- [ ] Solidity version is `^0.8.24`
- [ ] hardhat.config.ts has `evmVersion: "cancun"`
- [ ] First deposit initializes balance directly, not via `FHE.add`
- [ ] Transfer recipients have `FHE.allow(balance, recipient)`

---

*Continue to Layer 5 — Workflow for the full development process.*