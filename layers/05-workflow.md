# Layer 5 — Workflow: Full FHEVM Development Process

## Overview
Step 1: Setup          → Install dependencies, configure Hardhat
Step 2: Write Contract → Use patterns from Layer 3
Step 3: Test           → Local Hardhat node with FHE mocking
Step 4: Deploy         → Sepolia testnet
Step 5: Frontend       → fhevmjs SDK integration
Step 6: Verify         → Etherscan verification

---

## Step 1 — Environment Setup

```bash
# Clone official Zama template
git clone https://github.com/zama-ai/fhevm-hardhat-template
cd fhevm-hardhat-template
npm install

# Install OpenZeppelin
npm install @openzeppelin/contracts

# Create .env file
cp .env.example .env
```

```env
# .env
PRIVATE_KEY=0xyour_deployer_wallet_private_key
INFURA_API_KEY=your_infura_key
ETHERSCAN_API_KEY=your_etherscan_key
```

```typescript
// hardhat.config.ts — exact working configuration
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import "dotenv/config";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "cancun",
    },
  },
  networks: {
    hardhat: { chainId: 31337 },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.INFURA_API_KEY}`,
      chainId: 11155111,
      accounts: process.env.PRIVATE_KEY ? [`${process.env.PRIVATE_KEY}`] : [],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || "",
  },
};

export default config;
```

---

## Step 2 — Writing a Contract

Follow this exact structure for every FHEVM contract:

```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

// 1. FHE imports
import { FHE, euint64, externalEuint64, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

// 2. OpenZeppelin imports
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// 3. Contract declaration — ZamaEthereumConfig always first
contract MyContract is ZamaEthereumConfig, Ownable, ReentrancyGuard {

    // 4. Encrypted state variables
    mapping(address => euint64) private _encryptedValue;
    mapping(address => bool) public hasValue;

    // 5. Public stats — never store sensitive data as plaintext
    uint256 public totalUsers;

    // 6. Events — never emit encrypted values
    event ValueSet(address indexed user, uint256 timestamp);

    // 7. Constructor
    constructor() Ownable(msg.sender) {}

    // 8. Functions with encrypted inputs
    function setValue(
        externalEuint64 encryptedInput,
        bytes calldata inputProof
    ) external {
        euint64 value = FHE.fromExternal(encryptedInput, inputProof);
        _encryptedValue[msg.sender] = value;

        // Always set permissions after every write
        FHE.allowThis(_encryptedValue[msg.sender]);
        FHE.allow(_encryptedValue[msg.sender], msg.sender);

        if (!hasValue[msg.sender]) {
            hasValue[msg.sender] = true;
            totalUsers++;
        }

        emit ValueSet(msg.sender, block.timestamp);
    }

    // 9. Read functions — return encrypted handle
    function getEncryptedValue(address user) 
        external view returns (euint64) {
        return _encryptedValue[user];
    }
}
```

---

## Step 3 — Testing

```typescript
// test/MyContract.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { createInstances } from "../utils/fhevm";

describe("MyContract", function () {
  let contract: any;
  let owner: any;
  let user: any;
  let fhevm: any;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();
    
    const Factory = await ethers.getContractFactory("MyContract");
    contract = await Factory.deploy();
    await contract.waitForDeployment();
    
    // Initialize FHEVM instance for testing
    fhevm = await createInstances(
      await contract.getAddress(), 
      ethers, 
      user
    );
  });

  it("should set encrypted value", async function () {
    const contractAddress = await contract.getAddress();
    
    // Encrypt value client-side (simulated in test)
    const input = fhevm.createEncryptedInput(
      contractAddress, 
      user.address
    );
    input.add64(BigInt(1000));
    const { handles, inputProof } = await input.encrypt();

    // Submit encrypted value
    const tx = await contract.connect(user).setValue(
      handles[0],
      inputProof
    );
    await tx.wait();

    // Verify user has value
    expect(await contract.hasValue(user.address)).to.equal(true);
    expect(await contract.totalUsers()).to.equal(1);
  });

  it("should allow user to decrypt their value", async function () {
    const contractAddress = await contract.getAddress();

    // Set a value
    const input = fhevm.createEncryptedInput(
      contractAddress,
      user.address
    );
    input.add64(BigInt(5000));
    const { handles, inputProof } = await input.encrypt();
    await contract.connect(user).setValue(handles[0], inputProof);

    // Get encrypted handle
    const encHandle = await contract.getEncryptedValue(user.address);

    // Decrypt client-side
    const decrypted = await fhevm.userDecrypt(
      encHandle,
      contractAddress,
      user
    );

    expect(decrypted).to.equal(BigInt(5000));
  });
});
```

---

## Step 4 — Deploy to Sepolia

```typescript
// scripts/deploy.ts
import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying with:", deployer.address);
  console.log("Balance:", await deployer.provider.getBalance(deployer.address));

  const Factory = await ethers.getContractFactory("MyContract");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("✅ Deployed to:", address);
  console.log("Etherscan:", `https://sepolia.etherscan.io/address/${address}`);
}

main().catch(console.error);
```

```bash
# Deploy command
npx hardhat run scripts/deploy.ts --network sepolia

# Verify on Etherscan
npx hardhat verify --network sepolia YOUR_CONTRACT_ADDRESS
```

---

## Step 5 — Frontend Integration

```typescript
// frontend/src/lib/fhevm.ts
import { createInstance, type FhevmInstance } from "fhevmjs";
import { BrowserProvider, Contract } from "ethers";

const CONTRACT_ADDRESS = "0xYourDeployedContractAddress";
const CHAIN_ID = 11155111; // Sepolia

// ABI — only include functions you need
const ABI = [
  "function setValue(bytes32 encryptedInput, bytes calldata inputProof) external",
  "function getEncryptedValue(address user) external view returns (bytes32)",
  "function hasValue(address) external view returns (bool)",
];

// Initialize FHEVM instance
export async function initFhevm(): Promise<FhevmInstance> {
  const instance = await createInstance({
    networkUrl: `https://sepolia.infura.io/v3/${import.meta.env.VITE_INFURA_KEY}`,
    gatewayUrl: "https://gateway.sepolia.zama.ai",
  });
  return instance;
}

// Connect wallet
export async function connectWallet() {
  if (!window.ethereum) throw new Error("MetaMask not found");
  
  const provider = new BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  
  const network = await provider.getNetwork();
  if (Number(network.chainId) !== CHAIN_ID) {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: "0xaa36a7" }], // Sepolia
    });
  }
  
  const signer = await provider.getSigner();
  const address = await signer.getAddress();
  return { provider, signer, address };
}

// Encrypt and submit value
export async function submitEncryptedValue(
  instance: FhevmInstance,
  signer: any,
  amount: number
) {
  const contract = new Contract(CONTRACT_ADDRESS, ABI, signer);
  const address = await signer.getAddress();

  // Encrypt client-side
  const input = instance.createEncryptedInput(CONTRACT_ADDRESS, address);
  input.add64(BigInt(amount));
  const { handles, inputProof } = await input.encrypt();

  // Submit transaction — MetaMask will pop up
  const tx = await contract.setValue(handles[0], inputProof);
  const receipt = await tx.wait();
  
  return receipt.hash;
}

// Decrypt user's value
export async function decryptValue(
  instance: FhevmInstance,
  signer: any
): Promise<bigint> {
  const provider = signer.provider;
  const contract = new Contract(CONTRACT_ADDRESS, ABI, provider);
  const address = await signer.getAddress();

  // Get encrypted handle from contract
  const encHandle = await contract.getEncryptedValue(address);

  // EIP-712 signing for decryption permission
  const { publicKey, privateKey } = instance.generateKeypair();
  const eip712 = instance.createEIP712(publicKey, CONTRACT_ADDRESS);
  const signature = await signer.signTypedData(
    eip712.domain,
    { Reencrypt: eip712.types.Reencrypt },
    eip712.message
  );

  // Decrypt client-side
  const decrypted = await instance.reencrypt(
    encHandle,
    privateKey,
    publicKey,
    signature,
    CONTRACT_ADDRESS,
    address
  );

  return decrypted;
}
```

---

## Step 6 — Verify on Etherscan

```bash
# Basic verification
npx hardhat verify --network sepolia DEPLOYED_ADDRESS

# With constructor arguments
npx hardhat verify --network sepolia DEPLOYED_ADDRESS "arg1" "arg2"
```

After verification:
- Contract source code visible on Etherscan
- Functions readable and callable from Etherscan UI
- Judges can verify your FHE operations are real

---

## Get Sepolia Test ETH

| Faucet | URL |
|---|---|
| Alchemy | https://sepoliafaucet.com |
| QuickNode | https://faucet.quicknode.com/ethereum/sepolia |
| Infura | https://www.infura.io/faucet/sepolia |

---

## Get Sepolia Test Tokens (cUSDT Mock)

```bash
# Mint cUSDT Mock — public mint, max 1M per call
cast send 0xa7dA08FafDC9097Cc0E7D4f113A61e31d7e8e9b0 \
  "mint(address,uint256)" \
  YOUR_WALLET_ADDRESS 1000000000000 \
  --rpc-url https://sepolia.infura.io/v3/YOUR_KEY \
  --private-key YOUR_PRIVATE_KEY
```

---

## Full Project Checklist
Setup
[x] Node.js 18+ installed
[x] Hardhat initialized with TypeScript
[x] @fhevm/solidity installed
[x] @openzeppelin/contracts installed
[x] .env configured with PRIVATE_KEY + INFURA_API_KEY
[x] .gitignore includes .env
Contract
[x] Uses ZamaEthereumConfig (not ZamaSepoliaConfig)
[x] All encrypted inputs use externalEuint64 + inputProof
[x] FHE.allowThis() after every encrypted write
[x] FHE.allow() for every user who needs to decrypt
[x] FHE.select() instead of if/else for encrypted logic
[x] No view modifier on FHE functions
[x] Solidity 0.8.24 + evmVersion cancun
Testing
[x] Tests run on local Hardhat node
[x] Encryption tested with fhevmjs mock
[x] Decryption verified client-side
Deployment
[x] Deployed to Sepolia testnet
[x] Contract verified on Etherscan
[x] Contract address saved
Frontend
[x] fhevmjs installed
[x] MetaMask integration working
[x] Encryption happens client-side before tx
[x] MetaMask pops up for signing
[x] Tx hash displayed with Etherscan link
[x] Decryption uses EIP-712 signing flow

---

*All 5 layers complete. CipherGuard is ready to guide any
AI agent through the full FHEVM development workflow.*