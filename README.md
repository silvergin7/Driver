# Driver ($DVR)

Driver is a meme token made for practice. It runs on Sepolia, Ethereum's test network, so the tokens are free and have no real value.

The idea is a driving school. The treasury is the student driver, and everyone who holds DVR is an instructor who votes on how fast it may drive.

Try it at [driver-dvr.vercel.app](https://driver-dvr.vercel.app).

## How it works

- **Get free tokens.** Claim 10 DVR and 100 mUSDC (a pretend dollar) once a day from the faucets.
- **Trade in the pool.** The pool is where you swap DVR and mUSDC. Every trade pays a 1% tax in mUSDC.
- **The tax fills two funds.** 40% goes to Cruise Control, the careful fund. 40% goes to Degen Driver, the risky one. The last 20% is saved for a third fund that isn't built yet.
- **Instructors vote.** Lock DVR to vote on how fast Degen Driver may earn: 40%, 80% or 160% a year. One locked DVR is one vote, and a round lasts 30 days. If you vote, your DVR stays locked until the round ends. Cruise Control always earns 5%.
- **Monthly harvest.** Once a month the owner harvests each fund. Its share of the tax goes into the fund. What it earned is split in half: one half goes back in, and the other half buys DVR from the pool and burns it, so those tokens are gone for good.
- **The careful fund stays biggest.** The funds start at 15,000 and 5,000 mUSDC. At the end of Degen Driver's harvest, if Cruise Control has fallen below three quarters of the total, Degen Driver tops it up.

## The numbers

| | |
|---|---|
| DVR that can ever exist | 1,000,000 |
| Pool / faucet / community / team | 500,000 / 50,000 / 300,000 / 150,000 |
| Faucets | 10 DVR and 100 mUSDC per wallet per day |
| Trade tax | 1% |
| Starting price | 0.02 mUSDC per DVR |
| Voting round | 30 days |

## Try it

1. Install [MetaMask](https://metamask.io/download/), a wallet app that holds your tokens.
2. In MetaMask, turn on test networks and pick Sepolia.
3. Get a little free Sepolia ETH (see below). It pays the small fee that every action costs.
4. Open the site, connect your wallet, and claim DVR and mUSDC.
5. Swap in the pool, then lock some DVR and vote.

MetaMask may warn you that this site looks unsafe. This often happens to new test sites on a shared vercel.app address. The site only asks you to connect, switch to Sepolia and use the contracts listed below, and you can check each one on Etherscan.

## Getting Sepolia ETH

Sepolia ETH is free test money for network fees. These two faucets don't need any real ETH:

- [Google Cloud Web3 faucet](https://cloud.google.com/application/web3/faucet/ethereum/sepolia): sign in with Google.
- [pk910 faucet](https://sepolia-faucet.pk910.de/): no account. Paste your address and let the page work for a few minutes.

## What's simplified

- The risky farms pay more, but the funds can never lose the money they put in. Real risky investments can.
- mUSDC is pretend. Nothing here has real value.
- The demo has its own clock, so we can show a month passing. The owner can skip it forward a month, never back. Faucet waits still use real time.

## Contracts on Sepolia

All 15 are verified on Etherscan. Click an address to open it.

| What | Address |
| --- | --- |
| Driver token | [`0xcf865f0FF3910FC9888ac0AF4f250b50019D9EeC`](https://sepolia.etherscan.io/address/0xcf865f0FF3910FC9888ac0AF4f250b50019D9EeC) |
| DVR faucet | [`0x84BBA1e41a786aa53853795BAfb2118C98359377`](https://sepolia.etherscan.io/address/0x84BBA1e41a786aa53853795BAfb2118C98359377) |
| Mock USDC | [`0x37269d0C9be48d40DD7A130fb33Df24B73c5ccF3`](https://sepolia.etherscan.io/address/0x37269d0C9be48d40DD7A130fb33Df24B73c5ccF3) |
| mUSDC faucet | [`0x146D0050ee974dad461f9ba3f95def650a4ABaE8`](https://sepolia.etherscan.io/address/0x146D0050ee974dad461f9ba3f95def650a4ABaE8) |
| Demo clock | [`0x6D5c255C139C89Af17b38DB228fE2fC2458285Aa`](https://sepolia.etherscan.io/address/0x6D5c255C139C89Af17b38DB228fE2fC2458285Aa) |
| Tax splitter | [`0xD182eE97b32Fa1109012351e3Ffbe3F162C22e01`](https://sepolia.etherscan.io/address/0xD182eE97b32Fa1109012351e3Ffbe3F162C22e01) |
| Official pool | [`0x15dD35991324e22c27A10B1fBB56aA0018694aE6`](https://sepolia.etherscan.io/address/0x15dD35991324e22c27A10B1fBB56aA0018694aE6) |
| Cruise farm (5% a year) | [`0xED916e06ec68c5Ad16Ad806C5F3a3a331C6A7068`](https://sepolia.etherscan.io/address/0xED916e06ec68c5Ad16Ad806C5F3a3a331C6A7068) |
| Highway farm (40% a year) | [`0xFBD52A17dA1dFfabE12B46c15f901df4214ce2eE`](https://sepolia.etherscan.io/address/0xFBD52A17dA1dFfabE12B46c15f901df4214ce2eE) |
| Autobahn farm (80% a year) | [`0x4BB2B635Df86c460920Df4c54F14846B4122D774`](https://sepolia.etherscan.io/address/0x4BB2B635Df86c460920Df4c54F14846B4122D774) |
| Drift farm (160% a year) | [`0x74EB8844a7bf2014769a9C4A2209E844B269726a`](https://sepolia.etherscan.io/address/0x74EB8844a7bf2014769a9C4A2209E844B269726a) |
| Round schedule | [`0xc4f78dA54c9cdd1D8e008b8158FD60FE315fAd2F`](https://sepolia.etherscan.io/address/0xc4f78dA54c9cdd1D8e008b8158FD60FE315fAd2F) |
| Cruise Control | [`0xD3D13fba75D43235a6595e891555bD22Abf1e93a`](https://sepolia.etherscan.io/address/0xD3D13fba75D43235a6595e891555bD22Abf1e93a) |
| Degen Driver | [`0x2dD01dDB664A8469cBFd7B770f6623289911a374`](https://sepolia.etherscan.io/address/0x2dD01dDB664A8469cBFd7B770f6623289911a374) |
| Vote | [`0x4Cd1D79005831D49eCbaC62c4467a689c5da3274`](https://sepolia.etherscan.io/address/0x4Cd1D79005831D49eCbaC62c4467a689c5da3274) |

## Run it yourself

You need Foundry and Node.js 24. Start a local test chain, deploy the contracts, then start the site. The exact commands are in [contracts/README.md](contracts/README.md) and [frontend/README.md](frontend/README.md).

## Good to know

A few known limits of the contracts are listed in [contracts/README.md](contracts/README.md#known-limits).
