// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.21;

contract ArbSysMock {
    function sendTxToL1(
        address destination,
        bytes calldata calldataForL1
    ) external payable returns (uint256 exitNum) {}
}
