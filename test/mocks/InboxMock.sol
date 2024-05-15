// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.21;

contract OutboxMock {
    address public l2ToL1Sender;
    function setL2ToL1Sender(address _l2ToL1Sender) external {
        l2ToL1Sender = _l2ToL1Sender;
    }
}

contract BridgeMock {
    address public immutable activeOutbox;
    constructor() {
        activeOutbox = address(new OutboxMock());
    }
}

contract InboxMock {
    address public immutable bridge;
    constructor() {
        bridge = address(new BridgeMock());
    }
    function createRetryableTicket(
        address _to,
        uint256 _l2CallValue,
        uint256 _maxSubmissionCost,
        address _refundTo,
        address _user,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) payable external returns (uint256) {}
}
