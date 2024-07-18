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

    uint256 l1PrivKey = vm.envUint("L1_PRIVATE_KEY");
    uint256 l2PrivKey = vm.envUint("L2_PRIVATE_KEY");
    address l1Deployer = vm.addr(l1PrivKey);

    function run() external {
        StdChains.Chain memory l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        StdChains.Chain memory l2Chain = getChain(string(vm.envOr("L2", string("arbitrum_one"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        string memory deps   = ScriptTools.loadDependencies();

        Domain l1Domain = new Domain(config, l1Chain);
        l1Domain.selectFork();

        // Note that l2Domain must be an ArbitrumDomain (instead of a Domain) so that ArbSys is overwritten with a dummy contract that doesn't use custom Arbitrum OpCodes
        ArbitrumDomain l2Domain = new ArbitrumDomain(config, l2Chain, l1Domain);
        l2Domain.selectFork();

        address l2Gateway = deps.readAddress(".l2Gateway");
        address l1Token = deps.readAddressArray(".l1Tokens")[0];
        address l2Token = deps.readAddressArray(".l2Tokens")[0];

        uint256 amount = 0.01 ether;

        vm.startBroadcast(l2PrivKey);
        GemLike(l2Token).approve(l2Gateway, type(uint256).max);

        // Note that outboundTransfer can only succeed if --skip-simulation was used due to usage of custom Arb OpCodes in ArbSys
        GatewayLike(l2Gateway).outboundTransfer({
            l1Token: l1Token, 
            to:      l1Deployer, 
            amount:  amount, 
            data:    ""
        });
        vm.stopBroadcast();

        // The message can be relayed manually on https://retryable-dashboard.arbitrum.io/
    }
}
