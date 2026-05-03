# Layer 2 — Operations: Every FHE Function with Correct Signatures

## CRITICAL RULE FOR AGENTS

The FHEVM library uses **overloaded functions**. Most operations accept either:
- `(encryptedType, encryptedType)` — two encrypted values
- `(encryptedType, plaintextType)` — one encrypted, one plaintext

**Comparison functions (ge, gt, le, lt, eq, ne) ONLY work with plaintext second argument for cross-type comparisons.**

Always check the signature before using any function.

---

## Arithmetic Operations

### Addition
```solidity
// euint64 + euint64
euint64 result = FHE.add(_balance[user], encAmount);

// euint64 + plaintext uint64
euint64 result = FHE.add(_balance[user], uint64(1000));
```

### Subtraction
```solidity
// euint64 - euint64
euint64 result = FHE.sub(_balance[user], encAmount);

// euint64 - plaintext uint64
euint64 result = FHE.sub(_balance[user], uint64(500));
```

### Multiplication
```solidity
// euint64 * plaintext uint64 (most common — multiply by scalar)
euint64 result = FHE.mul(_balance[user], uint64(500)); // 5% = 500 bps

// euint64 * euint64
euint64 result = FHE.mul(encA, encB);
```

### Division
```solidity
// euint64 / plaintext uint64 ONLY — no encrypted divisor
euint64 result = FHE.div(_balance[user], uint64(10000));
```

### Remainder
```solidity
// euint64 % plaintext uint64 ONLY
euint64 result = FHE.rem(_balance[user], uint64(100));
```

---

## Comparison Operations

### CORRECT signatures for euint64

```solidity
// Greater than or equal — encrypted vs plaintext
ebool result = FHE.ge(_balance[user], uint64(1000));

// Greater than — encrypted vs plaintext  
ebool result = FHE.gt(_score[user], uint64(600));

// Less than or equal — encrypted vs plaintext
ebool result = FHE.le(_debt[user], uint64(5000));

// Less than — encrypted vs plaintext
ebool result = FHE.lt(_balance[user], uint64(100));

// Equal — encrypted vs plaintext
ebool result = FHE.eq(_balance[user], uint64(0));

// Not equal — encrypted vs plaintext
ebool result = FHE.ne(_balance[user], uint64(0));
```

### Comparing two encrypted values
```solidity
// These DO exist for euint64 vs euint64:
ebool result = FHE.ge(encA, encB);   // ✅ exists
ebool result = FHE.gt(encA, encB);   // ✅ exists
ebool result = FHE.le(encA, encB);   // ✅ exists
ebool result = FHE.lt(encA, encB);   // ✅ exists
ebool result = FHE.eq(encA, encB);   // ✅ exists
ebool result = FHE.ne(encA, encB);   // ✅ exists
```

---

## Conditional Logic

### FHE.select — The FHE Ternary Operator
```solidity
// select(condition, valueIfTrue, valueIfFalse)
// This is how you do if/else in FHE

ebool sufficient = FHE.ge(_balance[user], uint64(amount));

_balance[user] = FHE.select(
    sufficient,
    FHE.sub(_balance[user], uint64(amount)), // if true: subtract
    _balance[user]                            // if false: keep same
);
```

**Rule: Never use plaintext if/else based on encrypted values.**
**Always use FHE.select() for conditional encrypted logic.**

---

## Type Casting

### Converting between encrypted types
```solidity
// Cast up (safe)
euint64 big   = FHE.asEuint64(smallEuint32);
euint128 huge = FHE.asEuint128(normalEuint64);

// Cast down (loses precision — use carefully)
euint32 small = FHE.asEuint32(bigEuint64);

// From plaintext to encrypted
euint64 enc   = FHE.asEuint64(uint64(1000));
ebool   encB  = FHE.asEbool(true);

// From encrypted to ebool
ebool flag    = FHE.asEbool(encUint);
```

---

## Input Handling — fromExternal

### Every user input must go through fromExternal
```solidity
function deposit(
    externalEuint64 encryptedAmount,  // handle from fhevmjs
    bytes calldata inputProof          // ZK proof from fhevmjs
) external {
    // Verify proof and decode — this is mandatory
    euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
    
    // Now safe to use amount in FHE operations
    _balance[msg.sender] = FHE.add(_balance[msg.sender], amount);
    FHE.allowThis(_balance[msg.sender]);
    FHE.allow(_balance[msg.sender], msg.sender);
}
```

### External type imports needed
```solidity
import {
    FHE,
    euint8, euint16, euint32, euint64, euint128, euint256,
    externalEuint8, externalEuint16, externalEuint32,
    externalEuint64, externalEuint128, externalEuint256,
    ebool, externalEbool,
    eaddress, externalEaddress
} from "@fhevm/solidity/lib/FHE.sol";
```

---

## Access Control Functions

```solidity
// Allow the contract itself to use this value in future transactions
FHE.allowThis(encValue);

// Allow a specific address to decrypt this value
FHE.allow(encValue, userAddress);

// Allow temporarily for a cross-contract call (clears after tx)
FHE.allowTransient(encValue, otherContract);

// Make value decryptable by anyone publicly
FHE.makePubliclyDecryptable(encValue);

// Check if an address has permission
bool canDecrypt = FHE.isAllowed(encValue, userAddress);

// Check if msg.sender has permission
bool senderAllowed = FHE.isSenderAllowed(encValue);
```

---

## Logical Operations (ebool)

```solidity
// AND
ebool both = FHE.and(conditionA, conditionB);

// OR
ebool either = FHE.or(conditionA, conditionB);

// XOR
ebool different = FHE.xor(conditionA, conditionB);

// NOT
ebool opposite = FHE.not(conditionA);
```

---

## Min / Max

```solidity
// Encrypted min/max — returns smaller/larger encrypted value
euint64 smaller = FHE.min(encA, encB);
euint64 larger  = FHE.max(encA, encB);

// With plaintext
euint64 capped  = FHE.min(_balance[user], uint64(10000)); // cap at 10000
euint64 floored = FHE.max(_balance[user], uint64(100));   // minimum 100
```

---

## Random Number Generation

```solidity
// Generate random encrypted values
ebool  randBool = FHE.randEbool();
euint8  rand8   = FHE.randEuint8();
euint64 rand64  = FHE.randEuint64();

// With upper bound
euint64 bounded = FHE.randEuint64(uint64(1000)); // random 0-1000
```

---

## Negation

```solidity
// Negate encrypted value
euint64 negated = FHE.neg(encValue);

// Bitwise NOT
euint64 flipped = FHE.not(encValue);
```

---

## Complete Operation Reference Table

| Operation | Function | Signature |
|---|---|---|
| Add | `FHE.add` | `(euint64, euint64)` or `(euint64, uint64)` |
| Subtract | `FHE.sub` | `(euint64, euint64)` or `(euint64, uint64)` |
| Multiply | `FHE.mul` | `(euint64, euint64)` or `(euint64, uint64)` |
| Divide | `FHE.div` | `(euint64, uint64)` ONLY |
| Remainder | `FHE.rem` | `(euint64, uint64)` ONLY |
| Greater/equal | `FHE.ge` | `(euint64, euint64)` or `(euint64, uint64)` |
| Greater than | `FHE.gt` | `(euint64, euint64)` or `(euint64, uint64)` |
| Less/equal | `FHE.le` | `(euint64, euint64)` or `(euint64, uint64)` |
| Less than | `FHE.lt` | `(euint64, euint64)` or `(euint64, uint64)` |
| Equal | `FHE.eq` | `(euint64, euint64)` or `(euint64, uint64)` |
| Not equal | `FHE.ne` | `(euint64, euint64)` or `(euint64, uint64)` |
| Conditional | `FHE.select` | `(ebool, euint64, euint64)` |
| Min | `FHE.min` | `(euint64, euint64)` or `(euint64, uint64)` |
| Max | `FHE.max` | `(euint64, euint64)` or `(euint64, uint64)` |
| Allow contract | `FHE.allowThis` | `(encValue)` |
| Allow address | `FHE.allow` | `(encValue, address)` |
| Allow temp | `FHE.allowTransient` | `(encValue, address)` |
| Make public | `FHE.makePubliclyDecryptable` | `(encValue)` |

---

*Continue to Layer 3 — Patterns for production contract templates.*
