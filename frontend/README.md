# Frontend

Driver (DVR) website. Node 24.21.0 and npm 11.19.0.

```shell
cd frontend
npm ci
npm run dev
npm run generate
npm run sync:anvil
npm test
npm run lint
npm run typecheck
npm run build
```

`npm run generate` builds the Foundry project and writes `src/generated/contracts.ts`. Forge must be on `PATH`.

`npm run sync:anvil` reads `contracts/broadcast/DeployDriver.s.sol/31337/run-latest.json` and writes `src/config/addresses.json`. The script is `scripts/sync-anvil-addresses.mts`.

`npm test` runs the Vitest checks for claim eligibility, countdowns, faucet errors, action errors, wallet errors, DVR amounts, mUSDC amounts, farm labels, round choice, parsed amounts, slippage, buyback quotes, claim status, burned DVR, basis points, the address explorer, the page navigation, wallet alerts, the theme choice, farm APR, account switching, header menus, the request deadline, and the owner card.

Copy `.env.example` to `.env` for local settings.
