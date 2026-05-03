// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

// CipherGuard Example 1 — Confidential Vault
// A production-ready private savings vault using Zama FHEVM
// Demonstrates: encrypted balances, private deposits,
// FHE withdrawal verification, yield accrual

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ConfidentialVault is ZamaEthereumConfig, Ownable, ReentrancyGuard {

    // ── Encrypted state ───────────────────────────────────────────────
    mapping(address => euint64) private _balance;
    mapping(address => bool)    public  hasDeposited;

    // ── Public stats (no sensitive data) ─────────────────────────────
    uint256 public totalUsers;
    uint256 public totalTransactions;
    uint256 public apyBps = 500; // 5% APY
    uint256 public lastYieldTime;

    // ── Events ────────────────────────────────────────────────────────
    event Deposited(address indexed user, uint256 timestamp);
    event Withdrawn(address indexed user, uint256 timestamp);
    event YieldAccrued(uint256 timestamp);

    constructor() Ownable(msg.sender) {
        lastYieldTime = block.timestamp;
    }

    // ── Deposit ───────────────────────────────────────────────────────

    function deposit(
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external nonReentrant {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);

        if (!hasDeposited[msg.sender]) {
            _balance[msg.sender] = amount;
            hasDeposited[msg.sender] = true;
            totalUsers++;
        } else {
            _balance[msg.sender] = FHE.add(_balance[msg.sender], amount);
        }

        FHE.allowThis(_balance[msg.sender]);
        FHE.allow(_balance[msg.sender], msg.sender);

        totalTransactions++;
        emit Deposited(msg.sender, block.timestamp);
    }

    // ── Withdraw ──────────────────────────────────────────────────────

    function withdraw(
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external nonReentrant {
        require(hasDeposited[msg.sender], "No vault found");

        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);

        // FHE balance check — balance never revealed
        ebool sufficient = FHE.ge(_balance[msg.sender], amount);

        _balance[msg.sender] = FHE.select(
            sufficient,
            FHE.sub(_balance[msg.sender], amount),
            _balance[msg.sender]
        );

        FHE.allowThis(_balance[msg.sender]);
        FHE.allow(_balance[msg.sender], msg.sender);

        totalTransactions++;
        emit Withdrawn(msg.sender, block.timestamp);
    }

    // ── Yield accrual (owner/keeper) ──────────────────────────────────

    function accrueYield(address[] calldata users) external onlyOwner {
        uint256 elapsed = block.timestamp - lastYieldTime;
        uint256 yieldPer10k = (apyBps * elapsed) / 31536000;
        if (yieldPer10k == 0) return;

        for (uint256 i = 0; i < users.length; i++) {
            if (!hasDeposited[users[i]]) continue;

            euint64 yieldAmt = FHE.div(
                FHE.mul(_balance[users[i]], uint64(yieldPer10k)),
                10000
            );
            _balance[users[i]] = FHE.add(_balance[users[i]], yieldAmt);
            FHE.allowThis(_balance[users[i]]);
            FHE.allow(_balance[users[i]], users[i]);
        }

        lastYieldTime = block.timestamp;
        emit YieldAccrued(block.timestamp);
    }

    // ── Read ──────────────────────────────────────────────────────────

    function getEncryptedBalance(address user)
        external view returns (euint64) {
        return _balance[user];
    }

    function getVaultStats() external view returns (
        uint256 users,
        uint256 transactions,
        uint256 currentApy,
        uint256 lastYield
    ) {
        return (totalUsers, totalTransactions, apyBps, lastYieldTime);
    }

    // ── Admin ─────────────────────────────────────────────────────────

    function setAPY(uint256 newApyBps) external onlyOwner {
        require(newApyBps <= 3000, "Max 30%");
        apyBps = newApyBps;
    }
}