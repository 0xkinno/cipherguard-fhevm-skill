// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

// CipherGuard Example 2 — Confidential Voting
// Private onchain voting using Zama FHEVM
// Demonstrates: encrypted votes, private tally,
// public result after voting ends

import { FHE, euint32, externalEuint32, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ConfidentialVoting is ZamaEthereumConfig, Ownable {

    // ── Encrypted tallies ─────────────────────────────────────────────
    euint32 private _votesYes;
    euint32 private _votesNo;

    // ── Public state ──────────────────────────────────────────────────
    mapping(address => bool) public hasVoted;
    bool    public votingOpen;
    uint256 public deadline;
    uint256 public totalVoters;
    string  public proposition;

    // ── Events ────────────────────────────────────────────────────────
    event Voted(address indexed voter, uint256 timestamp);
    event VotingStarted(string proposition, uint256 deadline);
    event VotingEnded(uint256 timestamp);

    constructor(
        string memory _proposition,
        uint256 durationSeconds
    ) Ownable(msg.sender) {
        proposition = _proposition;
        deadline    = block.timestamp + durationSeconds;
        votingOpen  = true;
        emit VotingStarted(_proposition, deadline);
    }

    // ── Vote ──────────────────────────────────────────────────────────

    // encryptedChoice: encrypt 1 for YES, 0 for NO
    function vote(
        externalEuint32 encryptedChoice,
        bytes calldata inputProof
    ) external {
        require(votingOpen, "Voting is closed");
        require(block.timestamp < deadline, "Deadline passed");
        require(!hasVoted[msg.sender], "Already voted");

        euint32 choice = FHE.fromExternal(encryptedChoice, inputProof);

        // Add to YES tally
        _votesYes = FHE.add(_votesYes, choice);

        // Add to NO tally — (1 - choice)
        // If choice=1 (yes): adds 0 to no
        // If choice=0 (no):  adds 1 to no
        euint32 noVote = FHE.sub(FHE.asEuint32(uint32(1)), choice);
        _votesNo = FHE.add(_votesNo, noVote);

        FHE.allowThis(_votesYes);
        FHE.allowThis(_votesNo);

        hasVoted[msg.sender] = true;
        totalVoters++;
        emit Voted(msg.sender, block.timestamp);
    }

    // ── End voting ────────────────────────────────────────────────────

    function endVoting() external onlyOwner {
        require(votingOpen, "Already ended");
        votingOpen = false;

        // Make tallies publicly decryptable
        FHE.makePubliclyDecryptable(_votesYes);
        FHE.makePubliclyDecryptable(_votesNo);

        emit VotingEnded(block.timestamp);
    }

    // ── Read ──────────────────────────────────────────────────────────

    function getEncryptedTallies()
        external view returns (euint32 yes, euint32 no) {
        return (_votesYes, _votesNo);
    }

    function getVotingInfo() external view returns (
        string memory prop,
        bool open,
        uint256 end,
        uint256 voters
    ) {
        return (proposition, votingOpen, deadline, totalVoters);
    }
}