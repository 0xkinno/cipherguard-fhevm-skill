// CipherGuard Example 5 — Frontend Integration
// Complete TypeScript integration with Zama fhevmjs SDK
// Demonstrates: wallet connection, client-side encryption,
// MetaMask signing, decryption flow, proof generation

import { createInstance, type FhevmInstance } from "fhevmjs";
import { BrowserProvider, Contract, type Signer } from "ethers";

// ── Configuration ─────────────────────────────────────────────────────────

const CONFIG = {
  chainId: 11155111, // Sepolia
  chainIdHex: "0xaa36a7",
  rpcUrl: `https://sepolia.infura.io/v3/${import.meta.env.VITE_INFURA_KEY}`,
  gatewayUrl: "https://gateway.sepolia.zama.ai",
  contracts: {
    vault: "0xYourVaultAddress",
    score: "0xYourScoreAddress",
    token: "0xYourTokenAddress",
  },
};

// ── ABIs ──────────────────────────────────────────────────────────────────

const VAULT_ABI = [
  "function deposit(bytes32 encryptedAmount, bytes calldata inputProof) external",
  "function withdraw(bytes32 encryptedAmount, bytes calldata inputProof) external",
  "function getEncryptedBalance(address user) external view returns (bytes32)",
  "function hasDeposited(address) external view returns (bool)",
  "function getVaultStats() external view returns (uint256, uint256, uint256, uint256)",
];

const SCORE_ABI = [
  "function submitProfile(bytes32 encIncome, bytes incomeProof, bytes32 encDebt, bytes debtProof) external",
  "function computeScore() external",
  "function proveScoreAbove(uint64 threshold) external returns (bytes32)",
  "function proveLoanEligibility(uint64 loanAmount) external returns (bytes32)",
  "function proveLowRisk() external returns (bytes32)",
  "function getEncryptedScore(address user) external view returns (bytes32)",
  "function hasScore(address) external view returns (bool)",
  "function hasProfile(address) external view returns (bool)",
];

const TOKEN_ABI = [
  "function wrap(uint64 amount) external",
  "function unwrap(uint64 amount) external",
  "function confidentialTransfer(address to, bytes32 encAmount, bytes calldata inputProof) external",
  "function encryptedBalanceOf(address user) external view returns (bytes32)",
  "function tokenInfo() external view returns (string, string, uint256, uint256)",
];

// ── FHEVM Instance ────────────────────────────────────────────────────────

let fhevmInstance: FhevmInstance | null = null;

export async function initFhevm(): Promise<FhevmInstance> {
  if (fhevmInstance) return fhevmInstance;

  fhevmInstance = await createInstance({
    networkUrl: CONFIG.rpcUrl,
    gatewayUrl: CONFIG.gatewayUrl,
  });

  return fhevmInstance;
}

// ── Wallet Connection ─────────────────────────────────────────────────────

export interface WalletState {
  provider: BrowserProvider;
  signer: Signer;
  address: string;
}

export async function connectWallet(): Promise<WalletState> {
  if (!window.ethereum) {
    throw new Error("MetaMask not found. Please install MetaMask.");
  }

  const provider = new BrowserProvider(window.ethereum);

  // Request accounts — MetaMask will pop up
  await provider.send("eth_requestAccounts", []);

  // Check network — switch to Sepolia if needed
  const network = await provider.getNetwork();
  if (Number(network.chainId) !== CONFIG.chainId) {
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: CONFIG.chainIdHex }],
      });
    } catch (error: any) {
      // Network not added yet — add it
      if (error.code === 4902) {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: CONFIG.chainIdHex,
            chainName: "Sepolia Testnet",
            nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
            rpcUrls: [CONFIG.rpcUrl],
            blockExplorerUrls: ["https://sepolia.etherscan.io"],
          }],
        });
      } else {
        throw error;
      }
    }
  }

  const signer  = await provider.getSigner();
  const address = await signer.getAddress();

  return { provider, signer, address };
}

// ── Encryption Helper ─────────────────────────────────────────────────────

export async function encryptValue(
  instance: FhevmInstance,
  contractAddress: string,
  userAddress: string,
  value: number
): Promise<{ handle: string; inputProof: string }> {
  const input = instance.createEncryptedInput(contractAddress, userAddress);
  input.add64(BigInt(value));
  const { handles, inputProof } = await input.encrypt();

  return {
    handle: handles[0],
    inputProof: inputProof,
  };
}

// ── Vault Functions ───────────────────────────────────────────────────────

export async function depositToVault(
  instance: FhevmInstance,
  signer: Signer,
  amount: number
): Promise<string> {
  const address  = await signer.getAddress();
  const contract = new Contract(CONFIG.contracts.vault, VAULT_ABI, signer);

  // Encrypt amount client-side — never touches chain as plaintext
  const { handle, inputProof } = await encryptValue(
    instance,
    CONFIG.contracts.vault,
    address,
    amount
  );

  // MetaMask will pop up for signing
  const tx      = await contract.deposit(handle, inputProof);
  const receipt = await tx.wait();

  return receipt.hash;
}

export async function withdrawFromVault(
  instance: FhevmInstance,
  signer: Signer,
  amount: number
): Promise<string> {
  const address  = await signer.getAddress();
  const contract = new Contract(CONFIG.contracts.vault, VAULT_ABI, signer);

  const { handle, inputProof } = await encryptValue(
    instance,
    CONFIG.contracts.vault,
    address,
    amount
  );

  const tx      = await contract.withdraw(handle, inputProof);
  const receipt = await tx.wait();

  return receipt.hash;
}

export async function getDecryptedBalance(
  instance: FhevmInstance,
  signer: Signer
): Promise<bigint> {
  const address  = await signer.getAddress();
  const provider = signer.provider!;
  const contract = new Contract(CONFIG.contracts.vault, VAULT_ABI, provider);

  // Get encrypted handle from contract
  const encHandle = await contract.getEncryptedBalance(address);

  // Generate keypair for reencryption
  const { publicKey, privateKey } = instance.generateKeypair();

  // EIP-712 signing — proves user owns this address
  const eip712 = instance.createEIP712(publicKey, CONFIG.contracts.vault);
  const signature = await signer.signTypedData(
    eip712.domain,
    { Reencrypt: eip712.types.Reencrypt },
    eip712.message
  );

  // Decrypt client-side using private key
  const decrypted = await instance.reencrypt(
    encHandle,
    privateKey,
    publicKey,
    signature,
    CONFIG.contracts.vault,
    address
  );

  return decrypted;
}

// ── Score Functions ───────────────────────────────────────────────────────

export async function submitFinancialProfile(
  instance: FhevmInstance,
  signer: Signer,
  monthlyIncome: number,
  totalDebt: number
): Promise<string> {
  const address  = await signer.getAddress();
  const contract = new Contract(CONFIG.contracts.score, SCORE_ABI, signer);

  // Encrypt both inputs separately
  const encIncome = await encryptValue(
    instance, CONFIG.contracts.score, address, monthlyIncome
  );
  const encDebt = await encryptValue(
    instance, CONFIG.contracts.score, address, totalDebt
  );

  // Submit both encrypted values in one transaction
  const tx = await contract.submitProfile(
    encIncome.handle,
    encIncome.inputProof,
    encDebt.handle,
    encDebt.inputProof
  );
  const receipt = await tx.wait();

  return receipt.hash;
}

export async function computeCreditScore(
  signer: Signer
): Promise<string> {
  const contract = new Contract(CONFIG.contracts.score, SCORE_ABI, signer);
  const tx       = await contract.computeScore();
  const receipt  = await tx.wait();
  return receipt.hash;
}

export async function getDecryptedScore(
  instance: FhevmInstance,
  signer: Signer
): Promise<bigint> {
  const address  = await signer.getAddress();
  const provider = signer.provider!;
  const contract = new Contract(CONFIG.contracts.score, SCORE_ABI, provider);

  const encHandle = await contract.getEncryptedScore(address);

  const { publicKey, privateKey } = instance.generateKeypair();
  const eip712 = instance.createEIP712(publicKey, CONFIG.contracts.score);
  const signature = await signer.signTypedData(
    eip712.domain,
    { Reencrypt: eip712.types.Reencrypt },
    eip712.message
  );

  const decrypted = await instance.reencrypt(
    encHandle,
    privateKey,
    publicKey,
    signature,
    CONFIG.contracts.score,
    address
  );

  return decrypted;
}

export async function generateLoanProof(
  signer: Signer,
  loanAmount: number
): Promise<string> {
  const contract = new Contract(CONFIG.contracts.score, SCORE_ABI, signer);
  const tx       = await contract.proveLoanEligibility(BigInt(loanAmount));
  const receipt  = await tx.wait();
  return receipt.hash;
}

// ── Token Functions ───────────────────────────────────────────────────────

export async function wrapTokens(
  signer: Signer,
  amount: number
): Promise<string> {
  const contract = new Contract(CONFIG.contracts.token, TOKEN_ABI, signer);
  const tx       = await contract.wrap(BigInt(amount));
  const receipt  = await tx.wait();
  return receipt.hash;
}

export async function confidentialTransfer(
  instance: FhevmInstance,
  signer: Signer,
  recipient: string,
  amount: number
): Promise<string> {
  const address  = await signer.getAddress();
  const contract = new Contract(CONFIG.contracts.token, TOKEN_ABI, signer);

  const { handle, inputProof } = await encryptValue(
    instance,
    CONFIG.contracts.token,
    address,
    amount
  );

  const tx      = await contract.confidentialTransfer(recipient, handle, inputProof);
  const receipt = await tx.wait();

  return receipt.hash;
}

// ── Error Handler ─────────────────────────────────────────────────────────

export function handleFHEVMError(error: any): string {
  if (error.code === 4001) {
    return "Transaction rejected in MetaMask.";
  }
  if (error.code === -32603) {
    return "RPC error — check your network connection.";
  }
  if (error.message?.includes("allowThis")) {
    return "Permission error — FHE.allowThis() missing in contract.";
  }
  if (error.message?.includes("proof")) {
    return "Invalid input proof — re-encrypt your value.";
  }
  return error.message || "Unknown error occurred.";
}

// ── React Hook Example ────────────────────────────────────────────────────

/*
// hooks/useShadowVault.ts
import { useState, useCallback } from "react";
import { initFhevm, connectWallet, depositToVault, getDecryptedBalance } from "./frontend-integration";

export function useShadowVault() {
  const [wallet, setWallet]   = useState<WalletState | null>(null);
  const [balance, setBalance] = useState<bigint | null>(null);
  const [loading, setLoading] = useState(false);
  const [txHash, setTxHash]   = useState<string | null>(null);
  const [error, setError]     = useState<string | null>(null);

  const connect = useCallback(async () => {
    setLoading(true);
    try {
      const w = await connectWallet();
      setWallet(w);
    } catch (e: any) {
      setError(handleFHEVMError(e));
    }
    setLoading(false);
  }, []);

  const deposit = useCallback(async (amount: number) => {
    if (!wallet) return;
    setLoading(true);
    setError(null);
    try {
      const instance = await initFhevm();
      const hash     = await depositToVault(instance, wallet.signer, amount);
      setTxHash(hash);
    } catch (e: any) {
      setError(handleFHEVMError(e));
    }
    setLoading(false);
  }, [wallet]);

  const fetchBalance = useCallback(async () => {
    if (!wallet) return;
    setLoading(true);
    try {
      const instance = await initFhevm();
      const bal      = await getDecryptedBalance(instance, wallet.signer);
      setBalance(bal);
    } catch (e: any) {
      setError(handleFHEVMError(e));
    }
    setLoading(false);
  }, [wallet]);

  return { wallet, balance, loading, txHash, error, connect, deposit, fetchBalance };
}
*/