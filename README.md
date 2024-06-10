# MakerDAO Arbitrum Token Bridge

## Overview

### L1 to L2 deposits

To deposit a given amount of a supported token into Arbitrum, Alice calls `outboundTransfer[CustomRefund]()` on the `L1TokenGateway`. This call locks Alice's tokens into an escrow contract and creates an [Arbitrum Retryable Tickets](https://docs.arbitrum.io/how-arbitrum-works/arbos/l1-l2-messaging#retryable-tickets) which instructs the Arbitrum sequencer to asynchroneously call `finalizeInboundTransfer()` on `L2TokenGateway`. That latter call mints an equivalent amount of L2 tokens for Alice.

Note that the `outboundTransfer[CustomRefund]` payable function requires a number of gas parameters to be provided, and must be called with some corresponding amount of ETH as `msg.value`. An example of how to calculate these parameters is provided in `script/Deposit.s.sol`.

### L2 to L1 withdrawals

To withdraw her tokens back to L1, Alice calls `outboundTransfer()` on the `L2TokenGateway`. This call burns Alice's tokens and performs a call to the [ArbSys](https://docs.arbitrum.io/how-arbitrum-works/arbos/l2-l1-messaging#client-flow) precompile contract, which enables anyone to call `finalizeInboundTransfer()` on `L1TokenGateway` after the ~7 days security period. That latter call releases an equivalent amount of L1 tokens from the escrow to Alice.

## Declare env variables

Add the required env variables listed in `.env.example` to your `.env` file, and run `source .env`.

Make sure to set the `L1` and `L2` env variables according to your desired deployment environment.

Mainnet deployment:

```
L1=mainnet
L2=arbitrum_one
```

Testnet deployment:

```
L1=sepolia
L2=arbitrum_one_sepolia
```

## Deploy the bridge

The following command deploys the L1 and L2 sides of the bridge:

```
forge script script/Deploy.s.sol:Deploy --sender $DEPLOYER --private-key $PRIVATE_KEY --slow --verify --multi --broadcast
```

Note that the deployment script deploys mocks for the L2 contracts. For production deployment, the actual L2 token contracts must be used instead (they are not included in this repo).

## Initialize the bridge

On mainnet, the bridge should be initialized via the spell process. On testnet, the bridge initialization can be performed via the following command:

```
forge script script/Init.s.sol:Init --sender $DEPLOYER --private-key $PRIVATE_KEY --slow --multi --broadcast
```

## Test the deployment

To perform a test deposit, use the following command:

```
forge script script/Deposit.s.sol:Deposit --sender $DEPLOYER --private-key $PRIVATE_KEY --slow --multi --broadcast
```

To subsequently perform a test withdrawal, use the following command:

```
forge script script/Deposit.s.sol:Deposit --sender $DEPLOYER --private-key $PRIVATE_KEY --slow --multi --broadcast --skip-simulation
```

Note that the `--skip-simulation` flag is required due to usage of custom Arb OpCodes in ArbSys.

The message can be relayed manually to L1 using [this Arbitrum tool](https://retryable-dashboard.arbitrum.io/).
