import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

export default defineConfig({
  out: "src/generated/contracts.ts",
  plugins: [
    foundry({
      project: "../contracts",
      include: [
        "DriverToken.sol/DriverToken.json",
        "DriverFaucet.sol/DriverFaucet.json",
        "MockUSDC.sol/MockUSDC.json",
        "MockUsdcFaucet.sol/MockUsdcFaucet.json",
        "DriverClock.sol/DriverClock.json",
        "DemoDriverClock.sol/DemoDriverClock.json",
        "TaxSplitter.sol/TaxSplitter.json",
        "OfficialPool.sol/OfficialPool.json",
        "MockFarm.sol/MockFarm.json",
      ],
      includeBroadcasts: false,
      forge: {
        build: true,
        clean: false,
      },
    }),
  ],
});
