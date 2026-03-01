import { network } from "hardhat";

const { viem } = await network.connect({
  network: "mainnet",
  chainType: "l1",
});

const publicClient = await viem.getPublicClient();
const gasPrice = await publicClient.getGasPrice();
console.log("Gas price:", Number(gasPrice) / 1e9, "gwei");

const block = await publicClient.getBlock();
console.log("Base fee:", Number(block.baseFeePerGas!) / 1e9, "gwei");

// Rough estimate: contract deploy ~800k-1.2M gas
const estimatedGasLow = 800_000n;
const estimatedGasHigh = 1_200_000n;
console.log("Estimated deploy cost (low):", Number(estimatedGasLow * gasPrice) / 1e18, "ETH");
console.log("Estimated deploy cost (high):", Number(estimatedGasHigh * gasPrice) / 1e18, "ETH");
