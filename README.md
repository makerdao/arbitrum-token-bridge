# MakerDAO Arbitrum Token Bridge

## Overview

The Arbitrum Token Bridge is a [custom Arbitrum bridge](https://docs.arbitrum.io/build-decentralized-apps/token-bridging/bridge-tokens-programmatically/how-to-bridge-tokens-custom-gateway) that allows users to deposit a supported token to Arbitrum and withdraw it back to Ethereum. It operates similarly to the previously deployed [Arbitrum Dai Bridge](https://github.com/makerdao/arbitrum-dai-bridge) and relies on the same security model but allows MakerDAO governance to update the set of tokens supported by the bridge.

## Contracts

- `L1TokenGateway.sol` - L1 side of the bridge. Transfers the deposited tokens into an escrow contract. Transfer them back to the user upon receiving a withdrawal message from the `L2TokenGateway`.
- `L2TokenGateway.sol` - L2 side of the bridge. Mints new L2 tokens after receiving a deposit message from `L1TokenGateway`. Burns L2 tokens when withdrawing them to L1.

### External dependencies

- The L2 implementations of the bridged tokens are not provided as part of this repository and are assumed to exist in external repositories. It is assumed that only simple, regular ERC20 tokens will be used with this bridge. In particular, the supported tokens are assumed to revert on failure (instead of returning false) and do not execute any hook on transfer.
- The [escrow contract](https://etherscan.io/address/0xA10c7CE4b876998858b1a9E12b10092229539400#code) holds the bridged tokens on L1. This is assumed to be the same escrow as the one used by the Arbitrum Dai Bridge.
- The [`L1GovernanceRelay`](https://etherscan.io/address/0x9ba25c289e351779E0D481Ba37489317c34A899d#code) & [`L2GovernanceRelay`](https://arbiscan.io/address/0x10E6593CDda8c58a1d0f14C5164B376352a55f2F#code) allow governance to exert admin control over the deployed L2 contracts. These contracts have been previously deployed to control the Arbitrum Dai Bridge.

## User flows

### L1 to L2 deposits

To deposit a given amount of a supported token into Arbitrum, Alice calls `outboundTransfer[CustomRefund]()` on the `L1TokenGateway`. This call locks Alice's tokens into an escrow contract and creates an [Arbitrum Retryable Ticket](https://docs.arbitrum.io/how-arbitrum-works/arbos/l1-l2-messaging#retryable-tickets) which instructs the Arbitrum sequencer to asynchroneously call `finalizeInboundTransfer()` on `L2TokenGateway`. That latter call mints an equivalent amount of L2 tokens for Alice.

Note that the `outboundTransfer[CustomRefund]` payable function requires a number of gas parameters to be provided, and must be called with some corresponding amount of ETH as `msg.value`. An example of how to calculate these parameters is provided in `script/Deposit.s.sol`.

### L2 to L1 withdrawals

To withdraw her tokens back to L1, Alice calls `outboundTransfer()` on the `L2TokenGateway`. This call burns Alice's tokens and performs a call to the [ArbSys](https://docs.arbitrum.io/how-arbitrum-works/arbos/l2-l1-messaging#client-flow) precompile contract, which enables anyone to call `finalizeInboundTransfer()` on `L1TokenGateway` after the ~7 days security period. That latter call releases an equivalent amount of L1 tokens from the escrow to Alice.

## Upgrades

### Upgrade to a new bridge (and deprecate this bridge)

1. Deploy the new token bridge and connect it to the same escrow as the one used by this bridge. The old and new bridges can operate in parallel.
2. Optionally, deprecate the old bridge by closing it. This involves calling `close()` on both the `L1TokenGateway` and `L2TokenGateway` so that no new outbound message can be sent to the other side of the bridge. After all cross-chain messages are done processing (can take ~1 week), the bridge is effectively closed and governance can consider revoking the approval to transfer funds from the escrow on L1 and the token minting rights on L2.

### Upgrade a single token to a new bridge

To migrate a single token to a new bridge, follow the steps below:

1. Deploy the new token bridge and connect it to the same escrow as the one used by this bridge.
2. Unregister the token on `L1TokenGateway`, removing the ability to initiate new L1 to L2 transfers for that token.
3. Wait a few days to give a chance for any failed L1 to L2 transfer to be retried.
4. Execute an L2 spell to unregister the token on `L2TokenGateway`, removing the ability to initiate new L2 to L1 transfers for that token.

Note that step 3 is required because unregistering the token on `L2TokenGateway` not only removes the ability to initiate new L2 to L1 transfers but also causes the finalization of pending L1 to L2 transfers to revert. This is a point of difference with the implementation of the Arbitrum generic-custom gateway, where a missing L2 token triggers a withdrawal of the tokens back to L1 instead of a revert.

## Deployment

### Declare env variables

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

### Deploy the bridge

Deploy the L1 and L2 tokens (not included in this repo) that must be supported by the bridge then fill in the addresses of these tokens in `script/input/{chainId}/config.json` as two arrays of address strings under the `tokens` key for both the L1 and L2 domains. On testnet, if the `tokens` key is missing for a domain, mock tokens will automatically be deployed for that domain.

The following command deploys the L1 and L2 sides of the bridge:

```
forge script script/Deploy.s.sol:Deploy --slow --multi --broadcast --verify
```

### Initialize the bridge

On mainnet, the bridge should be initialized via the spell process. On testnet, the bridge initialization can be performed via the following command:

```
forge script script/Init.s.sol:Init --slow --multi --broadcast
```

### Test the deployment

Make sure the L1 deployer account holds at least 10^18 units of the first token listed under `"l1Tokens"` in `script/output/{chainId}/deployed-latest.json`. To perform a test deposit of that token, use the following command:

```
forge script script/Deposit.s.sol:Deposit --slow --multi --broadcast
```

To subsequently perform a test withdrawal, use the following command:

```
forge script script/Withdraw.s.sol:Withdraw --slow --multi --broadcast --skip-simulation
```

Note that the `--skip-simulation` flag is required due to usage of custom Arb OpCodes in ArbSys.

The message can be relayed manually to L1 using [this Arbitrum tool](https://retryable-dashboard.arbitrum.io/).
