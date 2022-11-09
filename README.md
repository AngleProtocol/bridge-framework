# <img src="logo.svg" alt="Angle Bridge Framework" height="40px"> Angle Bridge Framework

[![CI](https://github.com/AngleProtocol/bridge-framework/workflows/CI/badge.svg)](https://github.com/AngleProtocol/bridge-framework/actions?query=workflow%3ACI)

This repository introduces a framework to bring a token that exists natively on a chain across different chains using whitelisted bridge solutions. Framework proposed here relies on LayerZero message passing solution but any bridge solution can be used.

It is the solution that is used by [Angle Protocol](https://angle.money) to bring agEUR and the ANGLE token cross-chain while keeping a single standard for each token, high security requirements and a smooth experience for bridgers which do not have to deal with several transactions.

For more details, take a look at [Angle Docs](https://docs.angle.money/other-aspects/cross-chain).

## 💻 Setup

### Prerequisites

This repo assumes that on each chain there is what is called a `CoreBorrow` contract that handles the whole access control logic. So before anything, you may want to check that you have a contract that complies with the `ICoreBorrow` interface.

You also obviously need a token natively deployed on a chain. It can work with any token. In this case, the [`ANGLE`](https://etherscan.io/address/0x31429d1856aD1377A8A0079410B297e1a9e214c2) token is used by default.

On top of that, contracts in this setup are upgradeable using a Transparent Proxy pattern, so you need to have a `ProxyAdmin` contract deployed across the different chains you are dealing with.

### Install packages

Before running any script on this repo, you need to install packages, you need to run:

```bash
yarn
```

### Create `.env` file

In order to interact with non local networks, you must create an `.env` that has:

- `MNEMONIC`
- network key (eg. an Alchemy or Infura network key)
- `ETHERSCAN_API_KEY`

For additional keys, you can check the `.env.example` file.

Warning: always keep your confidential information safe.

### Tests

Contracts in this repo rely on Hardhat tests. You can run tests as follows:

```bash
yarn hardhat:test ./test/hardhat/bridgeERC20/tokenSideChainMultiBridge.test.ts
```

You can also check the coverage of the tests with:

```bash
yarn hardhat:coverage
```

## ⚙️ Deploying

### Deployment flow

To build a cross-chain infrastructure for your token, you need to deploy various contracts:

- a `LayerZeroBridgeERC20` contract on the chain on which your token already exists. This contract will route the LayerZero bridge messages from the native chain to the other chains where bridging is to be allowed
- a `TokenSideChainMultiBridge` contract on all the chains on which you want your token to be. This contract is going to be the canonical version of your token on each the desired chains
- a `LayerZeroBridgeTokenERC20` contract on all the chains on which you want your token to be. This contract's role is to receive bridge messages that instruct the `TokenSideChainMultiBridge` token to mint tokens to the desired address. It is also used to send bridge messages and hence burn canonical tokens from the chain where tokens should be bridged. This contract is what effectively allows bridging from one canonical token to another to be done in just one transaction without ever interacting with a bridge token.

### LayerZeroBridgeERC20

To deploy the `LayerZeroBridgeERC20` contract on `CHAIN` (like mainnet), just run:

```bash
yarn deploy CHAIN --tags LayerZeroBridgeERC20
```

Before that, make sure to replace in the associated deployment file in `deploy/LayerZeroBridgeERC20.ts` the `CoreBorrow`, the `ProxyAdmin` and the token address by the addresses you want to rely on.

### TokenSideChainMultiBridge

To deploy the `TokenSideChainMultiBridge` and the associated `LayerZeroBridgeTokenERC20` contract run:

```bash
yarn deploy CHAIN --tags LayerZeroBridgeTokenERC20
```

In the `deploy/1_LayerZeroBridgeTokenERC20.ts` and `deploy/0_angleSideChainMultiBridge.ts`, make sure to specify the correct `CoreBorrow` and `ProxyAdmin` contract. In ths first file, you can also change the total and hourly limits that can be bridged with LayerZero to the given chain.

### Set Sources

The last thing you need to do to be fully operational with your bridge system is to link the contracts you have deployed to one another.

On each chain where you want the token to be supported (including the native chain), you need to call `setTrustedRemote` on the LayerZero bridge contract.

For instance, if your token exists natively on Ethereum, and has been bridged to Polygon and Optimism, then on Ethereum for instance, you need to add at trusted remote the version of the LayerZero contract on Polygon and Optimism, on Polygon you need to do it for Ethereum and Optimism, and last on Optimism, you need to do it for Ethereum and Polygon.

The script at `deploy/LayerZeroSetSources.ts` can help you build the transactions for a given chain provided that you specify the right `LayerZeroBridgeTokenERC20` or `LayerZeroBridgeERC20` on the other chains.

## 🌉 Adding a new chain

To add support for a new chain you just have to deploy on this chain the `TokenSideChainMultiBridge` and the `LayerZeroBridgeTokenERC20`, and then to correctly set trusted remotes across all chains for this new chain.

## 📰 Media

Don't hesitate to reach out on [Twitter 🐦](https://twitter.com/AngleProtocol) or on [Discord](https://discord.gg/4FtNgnpPgE) should you have any question.
