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
import { ArbitrumDomain } from "dss-test/domains/ArbitrumDomain.sol";

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
        l1Domain.selectFork();

        // Note that ArbitrumDomain is required for l2Domain (instead of Domain) in order to override the custom OpCodes used in ArbSys
        ArbitrumDomain l2Domain = new ArbitrumDomain(config, getChain(vm.envOr("L2", string("arbitrum_one"))), l1Domain);
        l2Domain.selectFork();

       (,address deployer, ) = vm.readCallers();
        address l2Gateway = deps.readAddress(".l2Gateway");
        address l1Token = deps.readAddressArray(".l1Tokens")[0];
        address l2Token = deps.readAddressArray(".l2Tokens")[0];

        uint256 amount = 0.01 ether;

        vm.startBroadcast();
        GemLike(l2Token).approve(l2Gateway, type(uint256).max);

        // Note that outboundTransfer can only succeed if --skip-simulation was used due to usage of custom Arb OpCodes in ArbSys
        GatewayLike(l2Gateway).outboundTransfer({
            l1Token: l1Token, 
            to:      deployer, 
            amount:  amount, 
            data:    ""
        });
        vm.stopBroadcast();

        // The message can be relayed manually on https://retryable-dashboard.arbitrum.io/
    }
}