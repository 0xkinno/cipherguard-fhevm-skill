// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

// CipherGuard Example 3 — Confidential ERC-7984 Token
// Confidential token standard using Zama FHEVM
// Demonstrates: encrypted balances, private transfers,
// wrapping ERC-20 to confidential, unwrapping back

import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ConfidentialERC7984 is ZamaEthereumConfig, Ownable, ReentrancyGuard {

    // ── Token metadata ────────────────────────────────────────────────
    string  public name;
    string  public symbol;
    uint8   public decimals;
    IERC20  public underlying;

    // ── Encrypted balances ────────────────────────────────────────────
    mapping(address => euint64) private _encBalance;
    mapping(address => bool)    public  hasBalance;

    // ── Encrypted allowances ──────────────────────────────────────────
    mapping(address => mapping(address => euint64)) private _encAllowance;

    // ── Public stats ──────────────────────────────────────────────────
    uint256 public totalWrapped;
    uint256 public totalHolders;

    // ── Events ────────────────────────────────────────────────────────
    event Wrapped(address indexed user, uint256 amount);
    event Unwrapped(address indexed user, uint256 amount);
    event ConfidentialTransfer(address indexed from, address indexed to);
    event ConfidentialApproval(address indexed owner, address indexed spender);

    constructor(
        string memory _name,
        string memory _symbol,
        uint8  _decimals,
        address _underlying
    ) Ownable(msg.sender) {
        name       = _name;
        symbol     = _symbol;
        decimals   = _decimals;
        underlying = IERC20(_underlying);
    }

    // ── Wrap ERC-20 → Confidential ────────────────────────────────────

    function wrap(uint64 amount) external nonReentrant {
        require(
            underlying.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        euint64 encAmount = FHE.asEuint64(amount);

        if (!hasBalance[msg.sender]) {
            _encBalance[msg.sender] = encAmount;
            hasBalance[msg.sender]  = true;
            totalHolders++;
        } else {
            _encBalance[msg.sender] = FHE.add(
                _encBalance[msg.sender],
                encAmount
            );
        }

        FHE.allowThis(_encBalance[msg.sender]);
        FHE.allow(_encBalance[msg.sender], msg.sender);

        totalWrapped += amount;
        emit Wrapped(msg.sender, amount);
    }

    // ── Unwrap Confidential → ERC-20 ──────────────────────────────────

    function unwrap(uint64 amount) external nonReentrant {
        require(hasBalance[msg.sender], "No balance");

        euint64 encAmount = FHE.asEuint64(amount);
        ebool sufficient  = FHE.ge(_encBalance[msg.sender], encAmount);

        _encBalance[msg.sender] = FHE.select(
            sufficient,
            FHE.sub(_encBalance[msg.sender], encAmount),
            _encBalance[msg.sender]
        );

        FHE.allowThis(_encBalance[msg.sender]);
        FHE.allow(_encBalance[msg.sender], msg.sender);

        require(
            underlying.transfer(msg.sender, amount),
            "Transfer failed"
        );

        totalWrapped -= amount;
        emit Unwrapped(msg.sender, amount);
    }

    // ── Confidential Transfer ─────────────────────────────────────────

    function confidentialTransfer(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external nonReentrant {
        require(hasBalance[msg.sender], "No balance");
        require(to != address(0), "Zero address");
        require(to != msg.sender, "Self transfer");

        euint64 amount    = FHE.fromExternal(encryptedAmount, inputProof);
        ebool sufficient  = FHE.ge(_encBalance[msg.sender], amount);

        // Deduct from sender
        _encBalance[msg.sender] = FHE.select(
            sufficient,
            FHE.sub(_encBalance[msg.sender], amount),
            _encBalance[msg.sender]
        );

        // Add to recipient
        if (!hasBalance[to]) {
            _encBalance[to] = FHE.select(
                sufficient,
                amount,
                FHE.asEuint64(uint64(0))
            );
            hasBalance[to] = true;
            totalHolders++;
        } else {
            _encBalance[to] = FHE.select(
                sufficient,
                FHE.add(_encBalance[to], amount),
                _encBalance[to]
            );
        }

        // Set permissions for both parties
        FHE.allowThis(_encBalance[msg.sender]);
        FHE.allow(_encBalance[msg.sender], msg.sender);
        FHE.allowThis(_encBalance[to]);
        FHE.allow(_encBalance[to], to);

        emit ConfidentialTransfer(msg.sender, to);
    }

    // ── Confidential Approve ──────────────────────────────────────────

    function confidentialApprove(
        address spender,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        _encAllowance[msg.sender][spender] = amount;

        FHE.allowThis(_encAllowance[msg.sender][spender]);
        FHE.allow(_encAllowance[msg.sender][spender], msg.sender);
        FHE.allow(_encAllowance[msg.sender][spender], spender);

        emit ConfidentialApproval(msg.sender, spender);
    }

    // ── Confidential TransferFrom ─────────────────────────────────────

    function confidentialTransferFrom(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external nonReentrant {
        require(hasBalance[from], "No balance");
        require(to != address(0), "Zero address");

        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);

        // Check allowance
        ebool allowedEnough = FHE.ge(
            _encAllowance[from][msg.sender],
            amount
        );

        // Deduct allowance
        _encAllowance[from][msg.sender] = FHE.select(
            allowedEnough,
            FHE.sub(_encAllowance[from][msg.sender], amount),
            _encAllowance[from][msg.sender]
        );

        // Check balance
        ebool sufficient = FHE.ge(_encBalance[from], amount);

        // Deduct from sender
        _encBalance[from] = FHE.select(
            sufficient,
            FHE.sub(_encBalance[from], amount),
            _encBalance[from]
        );

        // Add to recipient
        if (!hasBalance[to]) {
            _encBalance[to] = FHE.select(
                sufficient,
                amount,
                FHE.asEuint64(uint64(0))
            );
            hasBalance[to] = true;
            totalHolders++;
        } else {
            _encBalance[to] = FHE.select(
                sufficient,
                FHE.add(_encBalance[to], amount),
                _encBalance[to]
            );
        }

        FHE.allowThis(_encBalance[from]);
        FHE.allow(_encBalance[from], from);
        FHE.allowThis(_encBalance[to]);
        FHE.allow(_encBalance[to], to);
        FHE.allowThis(_encAllowance[from][msg.sender]);
        FHE.allow(_encAllowance[from][msg.sender], from);
        FHE.allow(_encAllowance[from][msg.sender], msg.sender);

        emit ConfidentialTransfer(from, to);
    }

    // ── Read ──────────────────────────────────────────────────────────

    function encryptedBalanceOf(address user)
        external view returns (euint64) {
        return _encBalance[user];
    }

    function encryptedAllowance(address owner, address spender)
        external view returns (euint64) {
        return _encAllowance[owner][spender];
    }

    function tokenInfo() external view returns (
        string memory _name,
        string memory _symbol,
        uint256 wrapped,
        uint256 holders
    ) {
        return (name, symbol, totalWrapped, totalHolders);
    }
}