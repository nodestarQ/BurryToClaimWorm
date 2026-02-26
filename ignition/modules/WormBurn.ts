import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("WormBurnModule", (m) => {
  const cypherWormsAddress = m.getParameter(
    "cypherWormsAddress",
    "0x4b76b30Ed4c50C0A1E963ef2C5e065F9aF057F5E"
  );
  const rewardTokenAddress = m.getParameter("rewardTokenAddress");
  const nftSupply = m.getParameter("nftSupply");

  const wormBurn = m.contract("WormBurn", [
    cypherWormsAddress,
    rewardTokenAddress,
    nftSupply,
  ]);

  return { wormBurn };
});
