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

import "forge-std/Script.sol";

import { ScriptTools } from "dss-test/ScriptTools.sol";
import { Domain } from "dss-test/domains/Domain.sol";
import { BridgedDomain } from "dss-test/domains/BridgedDomain.sol";

interface GemLike {
    function approve(address, uint256) external;
}

interface GatewayLike {
    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes memory);
}

// Test deployment in config.json
contract Withdraw is Script {
    using stdJson for string;

    function run() external {
        string memory config = ScriptTools.readInput("config"); // loads from FOUNDRY_SCRIPT_CONFIG
        string memory deps = ScriptTools.loadDependencies(); // loads from FOUNDRY_SCRIPT_DEPS
        
        Domain l1Domain = new Domain(config, getChain(string(vm.envOr("L1", string("mainnet")))));
        Domain l2Domain = new Domain(config, getChain(vm.envOr("L2", string("arbitrum_one"))));
        l2Domain.selectFork();

       (,address deployer, ) = vm.readCallers();
        address l1Gateway = deps.readAddress(".l1Gateway");
        address l2Gateway = deps.readAddress(".l2Gateway");
        address nst = deps.readAddress(".l1Nst");
        address l2Nst = deps.readAddress(".l2Nst");

        uint256 amount = 1 ether;
        vm.startBroadcast();
        GemLike(l2Nst).approve(l2Gateway, type(uint256).max);
        GatewayLike(l2Gateway).outboundTransfer({
            l1Token: nst, 
            to:      deployer, 
            amount:  amount, 
            data:    ""
        });
        vm.stopBroadcast();
    }
}