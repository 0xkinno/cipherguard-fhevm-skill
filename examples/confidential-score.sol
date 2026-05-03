// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

// CipherGuard Example 4 — Confidential Credit Score
// FHE-computed credit scoring with selective disclosure
// Demonstrates: multi-input FHE computation, score capping,
// selective disclosure proofs, loan eligibility verification

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ConfidentialScore is ZamaEthereumConfig, Ownable {

    // ── Encrypted state ───────────────────────────────────────────────
    mapping(address => euint64) private _score;
    mapping(address => euint64) private _income;
    mapping(address => euint64) private _debt;
    mapping(address => bool)    public  hasProfile;
    mapping(address => bool)    public  hasScore;

    // ── Public stats ──────────────────────────────────────────────────
    uint256 public totalProfiles;

    // ── Score thresholds (public rules) ──────────────────────────────
    uint64 public constant MAX_SCORE      = 800;
    uint64 public constant LOAN_TIER_1    = 5000;
    uint64 public constant LOAN_TIER_2    = 10000;
    uint64 public constant LOAN_TIER_3    = 25000;
    uint64 public constant SCORE_TIER_1   = 400;
    uint64 public constant SCORE_TIER_2   = 550;
    uint64 public constant SCORE_TIER_3   = 700;
    uint64 public constant SCORE_LOW_RISK = 600;

    // ── Events ────────────────────────────────────────────────────────
    event ProfileCreated(address indexed user, uint256 timestamp);
    event ScoreComputed(address indexed user, uint256 timestamp);
    event ProofGenerated(address indexed user, string proofType);

    constructor() Ownable(msg.sender) {}

    // ── Submit financial profile ──────────────────────────────────────

    function submitProfile(
        externalEuint64 encryptedIncome,
        bytes calldata incomeProof,
        externalEuint64 encryptedDebt,
        bytes calldata debtProof
    ) external {
        euint64 income = FHE.fromExternal(encryptedIncome, incomeProof);
        euint64 debt   = FHE.fromExternal(encryptedDebt, debtProof);

        _income[msg.sender] = income;
        _debt[msg.sender]   = debt;

        FHE.allowThis(_income[msg.sender]);
        FHE.allow(_income[msg.sender], msg.sender);
        FHE.allowThis(_debt[msg.sender]);
        FHE.allow(_debt[msg.sender], msg.sender);

        if (!hasProfile[msg.sender]) {
            hasProfile[msg.sender] = true;
            totalProfiles++;
            emit ProfileCreated(msg.sender, block.timestamp);
        }
    }

    // ── Compute credit score in FHE ───────────────────────────────────

    // Score formula: (income * 600) / (income + debt + 1)
    // Max score: 800
    // All computation happens on encrypted values
    function computeScore() external {
        require(hasProfile[msg.sender], "Submit profile first");

        euint64 numerator   = FHE.mul(_income[msg.sender], uint64(600));
        euint64 denominator = FHE.add(
            FHE.add(_income[msg.sender], _debt[msg.sender]),
            uint64(1)
        );
        euint64 rawScore = FHE.div(numerator, denominator);

        // Cap score at MAX_SCORE (800)
        ebool overMax = FHE.gt(rawScore, MAX_SCORE);
        _score[msg.sender] = FHE.select(
            overMax,
            FHE.asEuint64(MAX_SCORE),
            rawScore
        );

        FHE.allowThis(_score[msg.sender]);
        FHE.allow(_score[msg.sender], msg.sender);

        hasScore[msg.sender] = true;
        emit ScoreComputed(msg.sender, block.timestamp);
    }

    // ── Selective Disclosure Proofs ───────────────────────────────────

    // Prove score is above a threshold
    // Returns encrypted bool — verifier cannot see actual score
    function proveScoreAbove(
        uint64 threshold
    ) external returns (ebool) {
        require(hasScore[msg.sender], "Compute score first");

        ebool result = FHE.ge(_score[msg.sender], threshold);
        FHE.allowThis(result);
        FHE.allow(result, msg.sender);

        emit ProofGenerated(msg.sender, "SCORE_ABOVE");
        return result;
    }

    // Prove loan eligibility for specific amount
    function proveLoanEligibility(
        uint64 loanAmount
    ) external returns (ebool) {
        require(hasScore[msg.sender], "Compute score first");

        uint64 requiredScore;
        if (loanAmount <= LOAN_TIER_1) {
            requiredScore = SCORE_TIER_1; // 400
        } else if (loanAmount <= LOAN_TIER_2) {
            requiredScore = SCORE_TIER_2; // 550
        } else {
            requiredScore = SCORE_TIER_3; // 700
        }

        ebool eligible = FHE.ge(_score[msg.sender], requiredScore);
        FHE.allowThis(eligible);
        FHE.allow(eligible, msg.sender);

        emit ProofGenerated(msg.sender, "LOAN_ELIGIBLE");
        return eligible;
    }

    // Prove risk tier — Low/Medium/High
    function proveLowRisk() external returns (ebool) {
        require(hasScore[msg.sender], "Compute score first");

        ebool lowRisk = FHE.ge(_score[msg.sender], SCORE_LOW_RISK);
        FHE.allowThis(lowRisk);
        FHE.allow(lowRisk, msg.sender);

        emit ProofGenerated(msg.sender, "LOW_RISK");
        return lowRisk;
    }

    // Prove income is above threshold
    function proveIncomeAbove(
        uint64 threshold
    ) external returns (ebool) {
        require(hasProfile[msg.sender], "Submit profile first");

        ebool result = FHE.ge(_income[msg.sender], threshold);
        FHE.allowThis(result);
        FHE.allow(result, msg.sender);

        emit ProofGenerated(msg.sender, "INCOME_ABOVE");
        return result;
    }

    // Prove debt is below threshold
    function proveDebtBelow(
        uint64 threshold
    ) external returns (ebool) {
        require(hasProfile[msg.sender], "Submit profile first");

        ebool result = FHE.le(_debt[msg.sender], threshold);
        FHE.allowThis(result);
        FHE.allow(result, msg.sender);

        emit ProofGenerated(msg.sender, "DEBT_BELOW");
        return result;
    }

    // ── Read ──────────────────────────────────────────────────────────

    function getEncryptedScore(address user)
        external view returns (euint64) {
        return _score[user];
    }

    function getEncryptedIncome(address user)
        external view returns (euint64) {
        return _income[user];
    }

    function getEncryptedDebt(address user)
        external view returns (euint64) {
        return _debt[user];
    }

    function getStats() external view returns (
        uint256 profiles,
        uint64 maxScore,
        uint64 tier1Threshold,
        uint64 tier2Threshold,
        uint64 tier3Threshold
    ) {
        return (
            totalProfiles,
            MAX_SCORE,
            SCORE_TIER_1,
            SCORE_TIER_2,
            SCORE_TIER_3
        );
    }
}