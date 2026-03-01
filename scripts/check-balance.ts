import { network } from "hardhat";

const { viem } = await network.connect({
  network: "mainnet",
  chainType: "l1",
});

const publicClient = await viem.getPublicClient();
const [walletClient] = await viem.getWalletClients();

const balance = await publicClient.getBalance({ address: walletClient.account.address });
console.log("Address:", walletClient.account.address);
console.log("Balance:", (Number(balance) / 1e18).toFixed(6), "ETH");
