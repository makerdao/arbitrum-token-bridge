// SPDX-License-Identifier: AGPL-3.0-or-later

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

import { Vm } from "forge-std/Vm.sol";
import { Domain } from "dss-test/domains/Domain.sol";

interface InboxLike {
    function calculateRetryableSubmissionFee(uint256,uint256) external view returns (uint256);
}

interface L1GatewayLike {
    function inbox() external view returns (address);
}

contract RetryableTickets {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Domain  public immutable l1Domain;
    Domain  public immutable l2Domain;
    address public immutable inbox;
    address public immutable l1Gateway;
    address public immutable l2Gateway;

    constructor(
        Domain  l1Domain_,
        Domain  l2Domain_,
        address l1Gateway_,
        address l2Gateway_
    ) {
        l1Domain  = l1Domain_;
        l2Domain  = l2Domain_;
        l1Gateway = l1Gateway_;
        l2Gateway = l2Gateway_;

        uint256 fork = vm.activeFork();
        l1Domain.selectFork();
        inbox = L1GatewayLike(l1Gateway).inbox();
        vm.selectFork(fork);
    }

    function getSubmissionFee(bytes memory l2Calldata) external returns (uint256 fee) {
        uint256 fork = vm.activeFork();
        l1Domain.selectFork();

        fee = InboxLike(inbox).calculateRetryableSubmissionFee(l2Calldata.length, 0);

        vm.selectFork(fork);
    }

    function getMaxGas(bytes memory l2Calldata) external returns (uint256 maxGas) {
        bytes memory data = abi.encodeWithSignature(
            "estimateRetryableTicket(address,uint256,address,uint256,address,address,bytes)", 
            l1Gateway,
            1 ether,
            l2Gateway,
            0,
            l2Gateway,
            l2Gateway,
            l2Calldata
        );

        uint256 fork = vm.activeFork();
        l2Domain.selectFork();

        // this call MUST be executed via RPC, see https://docs.arbitrum.io/build-decentralized-apps/nodeinterface/overview
        bytes memory res = vm.rpc("eth_estimateGas", string(abi.encodePacked(
            "[{\"to\": \"", 
            vm.toString(address(0xc8)), // NodeInterface
            "\", \"data\": \"",    
            vm.toString(data),
            "\"}]"
        )));
        maxGas = vm.parseUint(vm.toString(res));

        vm.selectFork(fork);
    }

    function getGasPriceBid() external returns (uint256 gasPrice) {
        uint256 fork = vm.activeFork();
        l2Domain.selectFork();

        bytes memory res = vm.rpc("eth_gasPrice", "[]");
        gasPrice = vm.parseUint(vm.toString(res));

        vm.selectFork(fork);
    }
}
