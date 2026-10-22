# Frontend

Driver (DVR) website. Node 24.21.0 and npm 11.19.0.

```shell
cd frontend
npm ci
npm run dev
npm run generate
npm run sync:anvil
npm run sync:sepolia
npm test
npm run lint
npm run typecheck
npm run build
```

`npm run generate` builds the Foundry project and writes `src/generated/contracts.ts`. Forge must be on `PATH`.

`npm run sync:anvil` reads `contracts/broadcast/DeployDriver.s.sol/31337/run-latest.json` and writes the `"31337"` entry in `src/config/addresses.json`. It leaves any other chain in that file. The script is `scripts/sync-anvil-addresses.mts`.

`npm run sync:sepolia` reads `contracts/broadcast/DeployDriver.s.sol/11155111/run-latest.json` and writes the `"11155111"` entry. The Anvil entry must already be there. The script is `scripts/sync-sepolia-addresses.mts`.

`npm test` runs the Vitest checks for claim eligibility, countdowns, faucet errors, action errors, wallet errors, DVR amounts, mUSDC amounts, farm labels, round choice, parsed amounts, slippage, buyback quotes, claim status, burned DVR, basis points, the address explorer, the transaction explorer, switch prompts, chain selection, owner action targets, the page navigation, wallet alerts, the theme choice, farm APR, account switching, header menus, the request deadline, the owner card, and address sync.

Copy `.env.example` to `.env` for local settings.

## Sepolia

`NEXT_PUBLIC_CHAIN` is read when `npm run dev` or `npm run build` starts, and that choice stays for the running process. Leave it unset or empty for Anvil. Set it to `sepolia` for the Sepolia deployment. Any other value stops the build.

Leave `NEXT_PUBLIC_SEPOLIA_RPC_URL` empty to use the public Sepolia endpoint built into the site. Set it only when a Sepolia build should talk to a local fork. Do not put a keyed provider URL in it. A `NEXT_PUBLIC_` value is shipped in the browser bundle.

### Owner actions from the terminal

Run from the repo root after `set -a; source .env; set +a`. Read addresses with `jq` from `frontend/src/config/addresses.json`, key `"11155111"`. Every command uses `--rpc-url "$SEPOLIA_RPC_URL" --account sepolia-wallet`.

Skip moves the demo clock by the epoch fixed at deployment, 2592000 seconds. Do not fill that argument from `cast call`. Cast adds a bracketed note to numbers.

```shell
cast send --rpc-url "$SEPOLIA_RPC_URL" --account sepolia-wallet "$(jq -r '.["11155111"].DemoDriverClock' frontend/src/config/addresses.json)" "advanceTime(uint256)" 2592000
```

The site's harvest button sets a 1% minimum. This is a backup and sends 0.

```shell
cast send --rpc-url "$SEPOLIA_RPC_URL" --account sepolia-wallet "$(jq -r '.["11155111"].CruiseControl' frontend/src/config/addresses.json)" "harvest(uint256)" 0
cast send --rpc-url "$SEPOLIA_RPC_URL" --account sepolia-wallet "$(jq -r '.["11155111"].DegenDriver' frontend/src/config/addresses.json)" "harvest(uint256)" 0
```
