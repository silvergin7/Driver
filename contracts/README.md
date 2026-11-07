# Contracts

Foundry project for Driver. Run commands from this directory.

## Environment

Copy the repository root `.env.example` to `.env` and fill it in on your machine. Never commit `.env`.

Sepolia commands use the encrypted keystore `sepolia-wallet`.

```shell
cast wallet import sepolia-wallet --interactive
```

Pass `--account sepolia-wallet` on Sepolia `forge` and `cast` commands.

Mainnet uses the keystore `mainnet-wallet`.

```shell
cast wallet import mainnet-wallet --interactive
```

The project overview is in the root `README.md`.

## Build and test

```shell
forge build
forge test
```

## Local chain

In one terminal, from the repository root:

```shell
anvil --host 127.0.0.1 --port 8545 --block-time 1
```

In another, from this directory. The sender is the first local account.

```shell
forge script script/DeployDriver.s.sol:DeployDriver --rpc-url http://127.0.0.1:8545 --broadcast --unlocked --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

The Sepolia contracts are the archived demo. Their addresses are in the root README, under tag v0.1.0 and branch archive/sepolia-demo.

## Mainnet

Put `MAINNET_RPC_URL`, `MAINNET_DEPLOYER`, `DEPLOY_PROFILE=demo`, and `ETHERSCAN_API_KEY` in the root `.env`. Do not commit that file, and do not write the deployer address into the repository.

Forge does not load `.env` on its own. From the repository root:

```shell
set -a
source .env
set +a
cd contracts
```

Verification stays on the broadcast command, with `--verify`. That is the command that verified the Sepolia contracts.

Dry run, with no `--broadcast`. It shows the expected gas. Glamsterdam (EIP-8037) is live on Sepolia and not on mainnet, and mainnet has no activation date yet, so Forge's simulator matches the chain. If Glamsterdam activates on mainnet before the deploy, code deposits cost more and the total rises.

```shell
forge script script/DeployDriver.s.sol:DeployDriver --rpc-url mainnet --account mainnet-wallet --sender "$MAINNET_DEPLOYER" --chain mainnet
```

Then broadcast and verify together. `--skip-simulation` and `--slow` are the same flags as the Sepolia broadcast, and they are harmless here.

```shell
forge script script/DeployDriver.s.sol:DeployDriver --rpc-url mainnet --account mainnet-wallet --sender "$MAINNET_DEPLOYER" --chain mainnet --broadcast --verify --slow --skip-simulation
```

## Known limits

- An emergency exit on Cruise Control is permanent. That fund's only farm is paused and taken off the list, and the list never grows. The fund then holds mUSDC and cannot put it back to work. Do not run this on the public demo.
- Harvest Cruise Control before Degen Driver. The monthly rebalance reads Cruise Control's value at Degen Driver's harvest. The other order sends a little more to Cruise Control, and that extra stays there.
- The owner can set the pool tax from 0 to 300 basis points (0% to 3%). This demo uses 100 (1%).
- A holder can lock and vote just before a round ends, then unlock as soon as the next round opens. The vote from the closed round still counts. The rules allow this.
- `pendingRewards` can show more than the farm's reward reserve. A claim pays only what the reserve has left. The gap shows up only when a reserve runs low.
