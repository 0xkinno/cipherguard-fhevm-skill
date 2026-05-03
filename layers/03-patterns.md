# Layer 3 — Patterns: 6 Production Contract Templates

## Pattern 1 — Private Balance Vault

The most common FHEVM pattern. Encrypted deposits,
withdrawals verified in FHE, balance never revealed.

```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ConfidentialVault is ZamaEthereumConfig, ReentrancyGuard {
    mapping(address => euint64) private _balance;
    mapping(address => bool) public hasDeposited;

    function deposit(
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external nonReentrant {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);

        if (!hasDeposited[msg.sender]) {
            _balance[msg.sender] = amount;
            hasDeposited[msg.sender] = true;
        } else {
            _balance[msg.sender] = FHE.add(_balance[msg.sender], amount);
        }

        // ALWAYS call these two after every balance update
        FHE.allowThis(_balance[msg.sender]);
        FHE.allow(_balance[msg.sender], msg.sender);
    }

    function withdraw(
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external nonReentrant {
        require(hasDeposited[msg.sender], "No balance");
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);

        // FHE check — never use plaintext if/else here
        ebool sufficient = FHE.ge(_balance[msg.sender], amount);
        _balance[msg.sender] = FHE.select(
            sufficient,
            FHE.sub(_balance[msg.sender], amount),
            _balance[msg.sender]
        );

        FHE.allowThis(_balance[msg.sender]);
        FHE.allow(_balance[msg.sender], msg.sender);
    }

    function getEncryptedBalance(address user) 
        external view returns (euint64) {
        return _balance[user];
    }
}
```

---

## Pattern 2 — Private Voting

Votes encrypted onchain. Nobody sees individual votes.
Tally computed in FHE and revealed only when voting ends.

```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE, euint32, externalEuint32, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ConfidentialVoting is ZamaEthereumConfig, Ownable {
    euint32 private _votesYes;
    euint32 private _votesNo;
    mapping(address => bool) public hasVoted;
    bool public votingOpen;
    uint256 public deadline;

    event Voted(address indexed voter, uint256 timestamp);
    event VotingEnded(uint256 timestamp);

    constructor() Ownable(msg.sender) {
        votingOpen = true;
        deadline = block.timestamp + 7 days;
    }

    function vote(
        externalEuint32 encryptedChoice, // 1 = yes, 0 = no
        bytes calldata inputProof
    ) external {
        require(votingOpen, "Voting closed");
        require(block.timestamp < deadline, "Deadline passed");
        require(!hasVoted[msg.sender], "Already voted");

        euint32 choice = FHE.fromExternal(encryptedChoice, inputProof);

        // Add encrypted vote to encrypted tally
        _votesYes = FHE.add(_votesYes, choice);
        _votesNo  = FHE.add(_votesNo, FHE.sub(FHE.asEuint32(1), choice));

        FHE.allowThis(_votesYes);
        FHE.allowThis(_votesNo);

        hasVoted[msg.sender] = true;
        emit Voted(msg.sender, block.timestamp);
    }

    function endVoting() external onlyOwner {
        votingOpen = false;
        // Make tallies publicly decryptable after voting ends
        FHE.makePubliclyDecryptable(_votesYes);
        FHE.makePubliclyDecryptable(_votesNo);
        emit VotingEnded(block.timestamp);
    }

    function getEncryptedTallies() 
        external view returns (euint32 yes, euint32 no) {
        return (_votesYes, _votesNo);
    }
}
```

---

## Pattern 3 — Selective Disclosure

Prove facts about encrypted data without revealing
the underlying value. Core privacy primitive.

```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract SelectiveDisclosure is ZamaEthereumConfig {
    mapping(address => euint64) private _score;
    mapping(address => bool) public hasScore;

    // Submit encrypted score
    function submitScore(
        externalEuint64 encryptedScore,
        bytes calldata inputProof
    ) external {
        euint64 score = FHE.fromExternal(encryptedScore, inputProof);
        _score[msg.sender] = score;
        FHE.allowThis(_score[msg.sender]);
        FHE.allow(_score[msg.sender], msg.sender);
        hasScore[msg.sender] = true;
    }

    // Prove score is above threshold — returns encrypted bool
    // Verifier gets proof without seeing the score
    function proveScoreAbove(
        uint64 threshold
    ) external returns (ebool) {
        require(hasScore[msg.sender], "No score");
        ebool result = FHE.ge(_score[msg.sender], threshold);
        FHE.allowThis(result);
        FHE.allow(result, msg.sender);
        return result;
    }

    // Prove eligibility for loan amount
    function proveLoanEligibility(
        uint64 loanAmount
    ) external returns (ebool) {
        require(hasScore[msg.sender], "No score");
        uint64 required = loanAmount <= 5000 ? 400 :
                          loanAmount <= 10000 ? 550 : 700;
        ebool eligible = FHE.ge(_score[msg.sender], required);
        FHE.allowThis(eligible);
        FHE.allow(eligible, msg.sender);
        return eligible;
    }
}
```

---

## Pattern 4 — Confidential ERC-20 Wrapper

Wrap a standard ERC-20 into a confidential version
where balances and transfers are encrypted.

```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ConfidentialWrapper is ZamaEthereumConfig {
    IERC20 public underlying;
    mapping(address => euint64) private _encBalance;
    mapping(address => bool) public hasBalance;

    constructor(address _underlying) {
        underlying = IERC20(_underlying);
    }

    // Wrap ERC-20 tokens into confidential balance
    function wrap(uint64 amount) external {
        require(
            underlying.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        euint64 encAmount = FHE.asEuint64(amount);

        if (!hasBalance[msg.sender]) {
            _encBalance[msg.sender] = encAmount;
            hasBalance[msg.sender] = true;
        } else {
            _encBalance[msg.sender] = FHE.add(
                _encBalance[msg.sender], 
                encAmount
            );
        }

        FHE.allowThis(_encBalance[msg.sender]);
        FHE.allow(_encBalance[msg.sender], msg.sender);
    }

    // Confidential transfer — amount encrypted
    function confidentialTransfer(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external {
        require(hasBalance[msg.sender], "No balance");
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);

        ebool sufficient = FHE.ge(_encBalance[msg.sender], amount);

        _encBalance[msg.sender] = FHE.select(
            sufficient,
            FHE.sub(_encBalance[msg.sender], amount),
            _encBalance[msg.sender]
        );

        if (!hasBalance[to]) {
            _encBalance[to] = FHE.select(
                sufficient,
                amount,
                FHE.asEuint64(uint64(0))
            );
            hasBalance[to] = true;
        } else {
            _encBalance[to] = FHE.select(
                sufficient,
                FHE.add(_encBalance[to], amount),
                _encBalance[to]
            );
        }

        FHE.allowThis(_encBalance[msg.sender]);
        FHE.allow(_encBalance[msg.sender], msg.sender);
        FHE.allowThis(_encBalance[to]);
        FHE.allow(_encBalance[to], to);
    }

    // Unwrap back to ERC-20
    function unwrap(uint64 amount) external {
        require(hasBalance[msg.sender], "No balance");
        euint64 encAmount = FHE.asEuint64(amount);
        ebool sufficient = FHE.ge(_encBalance[msg.sender], encAmount);

        _encBalance[msg.sender] = FHE.select(
            sufficient,
            FHE.sub(_encBalance[msg.sender], encAmount),
            _encBalance[msg.sender]
        );

        FHE.allowThis(_encBalance[msg.sender]);
        FHE.allow(_encBalance[msg.sender], msg.sender);

        require(underlying.transfer(msg.sender, amount), "Transfer failed");
    }
}
```

---

## Pattern 5 — Private Auction

Bids encrypted onchain. Highest bidder determined
in FHE without revealing any bid amounts.

```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ConfidentialAuction is ZamaEthereumConfig, Ownable {
    euint64 private _highestBid;
    address public highestBidder;
    mapping(address => euint64) private _bids;
    bool public auctionOpen;
    uint256 public endTime;

    constructor(uint256 duration) Ownable(msg.sender) {
        auctionOpen = true;
        endTime = block.timestamp + duration;
    }

    function placeBid(
        externalEuint64 encryptedBid,
        bytes calldata inputProof
    ) external {
        require(auctionOpen, "Auction ended");
        require(block.timestamp < endTime, "Time expired");

        euint64 bid = FHE.fromExternal(encryptedBid, inputProof);
        _bids[msg.sender] = bid;

        // Check if this bid is higher than current highest
        ebool isHigher = FHE.gt(bid, _highestBid);

        // Update highest bid in FHE — no plaintext comparison
        _highestBid = FHE.select(isHigher, bid, _highestBid);

        FHE.allowThis(_highestBid);
        FHE.allow(_highestBid, owner());
        FHE.allowThis(_bids[msg.sender]);
        FHE.allow(_bids[msg.sender], msg.sender);
    }

    function endAuction() external onlyOwner {
        require(block.timestamp >= endTime, "Not ended");
        auctionOpen = false;
        FHE.makePubliclyDecryptable(_highestBid);
    }
}
```

---

## Pattern 6 — FHE Credit Score

Compute credit score from encrypted financial inputs.
Score stays private. Only proofs revealed.

```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract ConfidentialScore is ZamaEthereumConfig {
    mapping(address => euint64) private _score;
    mapping(address => bool) public hasScore;

    function computeScore(
        externalEuint64 encryptedIncome,
        bytes calldata incomeProof,
        externalEuint64 encryptedDebt,
        bytes calldata debtProof
    ) external {
        euint64 income = FHE.fromExternal(encryptedIncome, incomeProof);
        euint64 debt   = FHE.fromExternal(encryptedDebt, debtProof);

        // Score = (income * 600) / (income + debt + 1)
        euint64 numerator   = FHE.mul(income, uint64(600));
        euint64 denominator = FHE.add(FHE.add(income, debt), uint64(1));
        euint64 raw         = FHE.div(numerator, denominator);

        // Cap at 800
        ebool over  = FHE.gt(raw, uint64(800));
        _score[msg.sender] = FHE.select(over, FHE.asEuint64(uint64(800)), raw);

        FHE.allowThis(_score[msg.sender]);
        FHE.allow(_score[msg.sender], msg.sender);
        hasScore[msg.sender] = true;
    }

    function proveAbove(uint64 threshold) external returns (ebool) {
        require(hasScore[msg.sender], "No score");
        ebool result = FHE.ge(_score[msg.sender], threshold);
        FHE.allowThis(result);
        FHE.allow(result, msg.sender);
        return result;
    }
}
```

---

*Continue to Layer 4 — Anti-patterns for the 12 most common FHEVM mistakes.*