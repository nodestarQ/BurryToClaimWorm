import { network } from "hardhat";
import { readFileSync } from "fs";

const CYPHER_WORMS = "0x94f827db182ed0ff90e03713d4ac7af3184b8f9c";
const WORM_TOKEN = "0xfC9d98CdB3529F32cD7fb02d175547641e145B29";

const { viem } = await network.connect({
  network: "mainnet",
  chainType: "l1",
});

const publicClient = await viem.getPublicClient();
const [walletClient] = await viem.getWalletClients();

console.log("Deployer:", walletClient.account.address);

const balance = await publicClient.getBalance({ address: walletClient.account.address });
console.log("Balance:", (Number(balance) / 1e18).toFixed(6), "ETH");

const gasPrice = await publicClient.getGasPrice();
console.log("Gas price:", Number(gasPrice) / 1e9, "gwei");

const artifact = JSON.parse(
  readFileSync("artifacts/contracts/BurryToClaimWorm.sol/BurryToClaimWorm.json", "utf-8")
);

console.log("\nDeploying BurryToClaimWorm...");
console.log("  CypherWorms:", CYPHER_WORMS);
console.log("  WORM Token:", WORM_TOKEN);

const hash = await walletClient.deployContract({
  abi: artifact.abi,
  bytecode: artifact.bytecode as `0x${string}`,
  args: [CYPHER_WORMS, WORM_TOKEN],
});

console.log("Transaction hash:", hash);
console.log("Waiting for confirmation...");

const receipt = await publicClient.waitForTransactionReceipt({ hash });
console.log("Contract deployed at:", receipt.contractAddress);
console.log("Gas used:", receipt.gasUsed.toString());
