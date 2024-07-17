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
import { L2GovernanceRelay } from "deploy/mocks/L2GovernanceRelay.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { DomainExtended, ScriptToolsExtended } from "./DeployL1.s.sol";

interface L1RouterLike {
    function counterpartGateway() external view returns (address);
}

contract DeployL2 is Script {
    using DomainExtended for Domain;
    using stdJson for string;

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    address l1GovRelay;
    address l2GovRelay;
    address l1Gateway;
    address l2Gateway;
    address l1Router;
    address[] l2Tokens;

    function run() external {
        StdChains.Chain memory l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        StdChains.Chain memory l2Chain = getChain(string(vm.envOr("L2", string("arbitrum_one"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        string memory deps   = ScriptTools.loadDependencies();
        Domain l1Domain = new Domain(config, l1Chain);
        Domain l2Domain = new Domain(config, l2Chain);

        (,address deployer, ) = vm.readCallers();

        l1GovRelay = deps.readAddress(".l1GovRelay");
        l2GovRelay = deps.readAddress(".l2GovRelay");
        l1Gateway = deps.readAddress(".l1Gateway");
        l2Gateway = deps.readAddress(".l2Gateway");
        l1Router = deps.readAddress(".l1Router");

        l1Domain.selectFork();
        address l2Router = L1RouterLike(l1Router).counterpartGateway();

        l2Domain.selectFork();
        vm.startBroadcast();
        L2TokenGatewayInstance memory l2GatewayInstance = TokenGatewayDeploy.deployL2Gateway(deployer, l2GovRelay, l1Gateway, l2Router);
        require(l2GatewayInstance.gateway == l2Gateway, "l2Gateway address mismatch");
        vm.stopBroadcast();

        if (LOG.code.length > 0) {
            l2Tokens = l2Domain.readConfigAddresses("tokens");
        } else {
            vm.startBroadcast();
            address l2GovRelay_ = address(new L2GovernanceRelay(l1GovRelay));
            require(l2GovRelay == l2GovRelay_, "l2GovRelay address mismatch");

            if (l2Domain.hasConfigKey("tokens")) {
                l2Tokens = l2Domain.readConfigAddresses("tokens");
            } else {
                uint256 count = l1Domain.hasConfigKey("tokens") ? l1Domain.readConfigAddresses("tokens").length : 2;
                l2Tokens = new address[](count);
                for (uint256 i; i < count; ++i) {
                    l2Tokens[i] = address(new GemMock(0));
                    GemMock(l2Tokens[i]).rely(l2GovRelay);
                    GemMock(l2Tokens[i]).deny(deployer);
                }
            }
            vm.stopBroadcast();
        }

        // Export contract addresses

        // TODO: load the existing json so this is not required
        ScriptTools.exportContract("deployed", "chainlog", deps.readAddress(".chainlog"));
        ScriptTools.exportContract("deployed", "owner", deps.readAddress(".owner"));
        ScriptTools.exportContract("deployed", "l1Router", deps.readAddress(".l1Router"));
        ScriptTools.exportContract("deployed", "inbox", deps.readAddress(".inbox"));
        ScriptTools.exportContract("deployed", "escrow", deps.readAddress(".escrow"));
        ScriptTools.exportContract("deployed", "l1GovRelay", deps.readAddress(".l1GovRelay"));
        ScriptTools.exportContract("deployed", "l2GovRelay", deps.readAddress(".l2GovRelay"));
        ScriptTools.exportContract("deployed", "l1Gateway", deps.readAddress(".l1Gateway"));
        ScriptTools.exportContract("deployed", "l2Gateway", deps.readAddress(".l2Gateway"));
        ScriptToolsExtended.exportContracts("deployed", "l1Tokens", deps.readAddressArray(".l1Tokens"));

        ScriptTools.exportContract("deployed", "l2Router", l2Router);
        ScriptToolsExtended.exportContracts("deployed", "l2Tokens", l2Tokens);
        ScriptTools.exportContract("deployed", "l2GatewaySpell", l2GatewayInstance.spell);
    }
}
