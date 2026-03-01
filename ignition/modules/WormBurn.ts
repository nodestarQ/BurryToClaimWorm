import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("BurryToClaimWormModule", (m) => {
  const cypherWormsAddress = m.getParameter(
    "cypherWormsAddress",
    "0x94f827db182ed0ff90e03713d4ac7af3184b8f9c"
  );
  const rewardTokenAddress = m.getParameter("rewardTokenAddress");

  const burryToClaimWorm = m.contract("BurryToClaimWorm", [
    cypherWormsAddress,
    rewardTokenAddress,
  ]);

  return { burryToClaimWorm };
});
