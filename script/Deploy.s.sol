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
import { TokenGatewayDeploy, L2TokenGatewayInstance } from "deploy/TokenGatewayDeploy.sol";
import { ChainLog } from "deploy/mocks/ChainLog.sol";
import { L1Escrow } from "deploy/mocks/L1Escrow.sol";
import { L1GovernanceRelay } from "deploy/mocks/L1GovernanceRelay.sol";
import { L2GovernanceRelay } from "deploy/mocks/L2GovernanceRelay.sol";
import { GemMock } from "test/mocks/GemMock.sol";

interface L1RouterLike {
    function counterpartGateway() external view returns (address);
}

contract Deploy is Script {
    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    uint256 l1PrivKey = vm.envUint("L1_PRIVATE_KEY");
    uint256 l2PrivKey = vm.envUint("L2_PRIVATE_KEY");
    address l1Deployer = vm.addr(l1PrivKey);
    address l2Deployer = vm.addr(l2PrivKey);

    function run() external {
        StdChains.Chain memory l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        StdChains.Chain memory l2Chain = getChain(string(vm.envOr("L2", string("arbitrum_one"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        Domain l1Domain = new Domain(config, l1Chain);
        Domain l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();

        address l1Router = l2Domain.readConfigAddress("l1Router");
        address inbox = l2Domain.readConfigAddress("inbox");

        ChainLog chainlog;
        address owner;
        address escrow;
        address l1GovRelay;
        address l2GovRelay;
        address[] memory l1Tokens;
        address[] memory l2Tokens;

        if (LOG.code.length > 0) {
            chainlog = ChainLog(LOG);
            owner = chainlog.getAddress("MCD_PAUSE_PROXY");
            escrow = chainlog.getAddress("ARBITRUM_ESCROW");
            l1GovRelay = chainlog.getAddress("ARBITRUM_GOV_RELAY");
            l1Tokens = l1Domain.readConfigAddresses("tokens");
            l2Tokens = l2Domain.readConfigAddresses("tokens");
            l2GovRelay = L1GovernanceRelay(payable(l1GovRelay)).l2GovernanceRelay();
        } else {
            owner = l1Deployer;
            vm.startBroadcast(l1PrivKey);
            chainlog = new ChainLog();
            escrow = address(new L1Escrow());
            chainlog.setAddress("ARBITRUM_ESCROW", escrow);
            vm.stopBroadcast();

            l2Domain.selectFork();
            address l2GovRelay_ = vm.computeCreateAddress(l2Deployer, vm.getNonce(l2Deployer));

            l1Domain.selectFork();
            vm.startBroadcast(l1PrivKey);
            l1GovRelay = address(new L1GovernanceRelay(inbox, l2GovRelay_));

            if (l1Domain.hasConfigKey("tokens")) {
                l1Tokens = l1Domain.readConfigAddresses("tokens");
            } else {
                uint256 count = l2Domain.hasConfigKey("tokens") ? l2Domain.readConfigAddresses("tokens").length : 2;
                l1Tokens = new address[](count);
                for (uint256 i; i < count; ++i) {
                    l1Tokens[i] = address(new GemMock(1_000_000_000 ether));
                }
            }

            chainlog.setAddress("ARBITRUM_GOV_RELAY", l1GovRelay);
            vm.stopBroadcast();

            l2Domain.selectFork();
            vm.startBroadcast(l2PrivKey);
            l2GovRelay = address(new L2GovernanceRelay(l1GovRelay));
            require(l2GovRelay == l2GovRelay_, "l2GovRelay address mismatch");

            if (l2Domain.hasConfigKey("tokens")) {
                l2Tokens = l2Domain.readConfigAddresses("tokens");
            } else {
                uint256 count = l1Domain.hasConfigKey("tokens") ? l1Domain.readConfigAddresses("tokens").length : 2;
                l2Tokens = new address[](count);
                for (uint256 i; i < count; ++i) {
                    l2Tokens[i] = address(new GemMock(0));
                    GemMock(l2Tokens[i]).rely(l2GovRelay);
                    GemMock(l2Tokens[i]).deny(l2Deployer);
                }
            }
            vm.stopBroadcast();
        }

        // L1 deployment

        l2Domain.selectFork();
        address l2Gateway = vm.computeCreateAddress(l2Deployer, vm.getNonce(l2Deployer));

        l1Domain.selectFork();
        vm.startBroadcast(l1PrivKey);
        address l1Gateway = TokenGatewayDeploy.deployL1Gateway(l1Deployer, owner, l2Gateway, l1Router, inbox, escrow);
        vm.stopBroadcast();
        address l2Router = L1RouterLike(l1Router).counterpartGateway();

        // L2 deployment

        l2Domain.selectFork();
        vm.startBroadcast(l2PrivKey);
        L2TokenGatewayInstance memory l2GatewayInstance = TokenGatewayDeploy.deployL2Gateway(l2Deployer, l2GovRelay, l1Gateway, l2Router);
        require(l2GatewayInstance.gateway == l2Gateway, "l2Gateway address mismatch");
        vm.stopBroadcast();

        // Export contract addresses

        ScriptTools.exportContract("deployed", "chainlog", address(chainlog));
        ScriptTools.exportContract("deployed", "owner", owner);
        ScriptTools.exportContract("deployed", "l1Router", l1Router);
        ScriptTools.exportContract("deployed", "l2Router", l2Router);
        ScriptTools.exportContract("deployed", "inbox", inbox);
        ScriptTools.exportContract("deployed", "escrow", escrow);
        ScriptTools.exportContract("deployed", "l1GovRelay", l1GovRelay);
        ScriptTools.exportContract("deployed", "l2GovRelay", l2GovRelay);
        ScriptTools.exportContract("deployed", "l1Gateway", l1Gateway);
        ScriptTools.exportContract("deployed", "l2Gateway", l2Gateway);
        ScriptTools.exportContract("deployed", "l2GatewaySpell", l2GatewayInstance.spell);
        ScriptTools.exportContracts("deployed", "l1Tokens", l1Tokens);
        ScriptTools.exportContracts("deployed", "l2Tokens", l2Tokens);
    }
}
