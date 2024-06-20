// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
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

interface IBridge {
    function activeOutbox() external view returns (address);
}

interface IInbox {
    function bridge() external view returns (address);
    function createRetryableTicket(
        address destAddr,
        uint256 arbTxCallValue,
        uint256 maxSubmissionCost,
        address submissionRefundAddress,
        address valueRefundAddress,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable returns (uint256);
    function createRetryableTicketNoRefundAliasRewrite(
        address destAddr,
        uint256 arbTxCallValue,
        uint256 maxSubmissionCost,
        address submissionRefundAddress,
        address valueRefundAddress,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
  ) external payable returns (uint256);
}

interface IOutbox {
    function l2ToL1Sender() external view returns (address);
}

interface L2GovernanceRelayLike {
    function relay(address target, bytes calldata targetData) external;
}

abstract contract L1CrossDomainEnabled {
    IInbox public immutable inbox;

    event TxToL2(address indexed from, address indexed to, uint256 indexed seqNum, bytes data);

    constructor(address _inbox) {
        inbox = IInbox(_inbox);
    }

    modifier onlyL2Counterpart(address l2Counterpart) {
        // a message coming from the counterpart gateway was executed by the bridge
        address bridge = inbox.bridge();
        require(msg.sender == bridge, "NOT_FROM_BRIDGE");

        // and the outbox reports that the L2 address of the sender is the counterpart gateway
        address l2ToL1Sender = IOutbox(IBridge(bridge).activeOutbox()).l2ToL1Sender();
        require(l2ToL1Sender == l2Counterpart, "ONLY_COUNTERPART_GATEWAY");
        _;
    }

    function sendTxToL2(
        address target,
        address user,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes memory data
    ) internal returns (uint256) {
        uint256 seqNum = inbox.createRetryableTicket{value: msg.value}(
            target,
            0, // we always assume that l2CallValue = 0
            maxSubmissionCost,
            user,
            user,
            maxGas,
            gasPriceBid,
            data
        );
        emit TxToL2(user, target, seqNum, data);
        return seqNum;
    }

    function sendTxToL2NoAliasing(
        address target,
        address user,
        uint256 l1CallValue,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes memory data
    ) internal returns (uint256) {
        uint256 seqNum = inbox.createRetryableTicketNoRefundAliasRewrite{value: l1CallValue}(
            target,
            0, // we always assume that l2CallValue = 0
            maxSubmissionCost,
            user,
            user,
            maxGas,
            gasPriceBid,
            data
        );
        emit TxToL2(user, target, seqNum, data);
        return seqNum;
    }
}

// Relay a message from L1 to L2GovernanceRelay
// Sending L1->L2 message on arbitrum requires ETH balance. That's why this contract can receive ether.
// Excessive ether can be reclaimed by governance by calling reclaim function.

contract L1GovernanceRelay is L1CrossDomainEnabled {
    // --- Auth ---
    mapping(address => uint256) public wards;

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "L1GovernanceRelay/not-authorized");
        _;
    }

    address public immutable l2GovernanceRelay;

    event Rely(address indexed usr);
    event Deny(address indexed usr);

    constructor(address _inbox, address _l2GovernanceRelay) L1CrossDomainEnabled(_inbox) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        l2GovernanceRelay = _l2GovernanceRelay;
    }

    // Allow contract to receive ether
    receive() external payable {}

    // Allow governance to reclaim stored ether
    function reclaim(address receiver, uint256 amount) external auth {
        (bool sent, ) = receiver.call{value: amount}("");
        require(sent, "L1GovernanceRelay/failed-to-send-ether");
    }

  // Forward a call to be repeated on L2
    function relay(
        address target,
        bytes calldata targetData,
        uint256 l1CallValue,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 maxSubmissionCost
    ) external payable auth {
        bytes memory data = abi.encodeWithSelector(
            L2GovernanceRelayLike.relay.selector,
            target,
            targetData
        );

        sendTxToL2NoAliasing(
            l2GovernanceRelay,
            l2GovernanceRelay, // send any excess ether to the L2 counterpart
            l1CallValue,
            maxSubmissionCost,
            maxGas,
            gasPriceBid,
            data
        );
    }
}
