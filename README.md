# Driver ($DVR)

Driver is a Sepolia meme-token protocol. Contracts live in `contracts/` (Foundry). The website will live in `frontend/`.

## Setup

Copy `.env.example` to `.env` and fill in the values on your machine. Never commit `.env`.

Deploy with an encrypted Foundry keystore: `cast wallet import driver-deployer --interactive`, then pass `--account driver-deployer`.

From `contracts/`:

```shell
forge build
forge test
```
