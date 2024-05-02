// SPDX-License-Identifier: AGPL-3.0-or-later

/// Ngt.sol -- Ngt token

// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico
// Copyright (C) 2024 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
