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
import { TokenGatewayDeploy } from "deploy/TokenGatewayDeploy.sol";
import { ChainLog } from "deploy/mocks/ChainLog.sol";
import { L1Escrow } from "deploy/mocks/L1Escrow.sol";
import { L1GovernanceRelay } from "deploy/mocks/L1GovernanceRelay.sol";
import { GemMock } from "test/mocks/GemMock.sol";

// TODO: Add to dss-test/ScriptTools.sol
library ScriptToolsExtended {
    VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));
    function exportContracts(string memory name, string memory label, address[] memory addr) internal {
        name = vm.envOr("FOUNDRY_EXPORTS_NAME", name);
        string memory json = vm.serializeAddress(ScriptTools.EXPORT_JSON_KEY, label, addr);
        ScriptTools._doExport(name, json);
    }
}

// TODO: Add to dss-test/domains/Domain.sol
library DomainExtended {
    using stdJson for string;
    function hasConfigKey(Domain domain, string memory key) internal view returns (bool) {
        bytes memory raw = domain.config().parseRaw(string.concat(".domains.", domain.details().chainAlias, ".", key));
        return raw.length > 0;
    }
    function readConfigAddresses(Domain domain, string memory key) internal view returns (address[] memory) {
        return domain.config().readAddressArray(string.concat(".domains.", domain.details().chainAlias, ".", key));
    }
}

contract DeployL1 is Script {
    using DomainExtended for Domain;

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    ChainLog chainlog;
    address owner;
    address escrow;
    address l1GovRelay;
    address l2GovRelay;
    address[] l1Tokens;

    function run() external {
        StdChains.Chain memory l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        StdChains.Chain memory l2Chain = getChain(string(vm.envOr("L2", string("arbitrum_one"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        Domain l1Domain = new Domain(config, l1Chain);
        Domain l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();

        address L2_DEPLOYER = vm.envAddress("L2_DEPLOYER");
        (,address deployer, ) = vm.readCallers();
        address l1Router = l2Domain.readConfigAddress("l1Router");
        address inbox = l2Domain.readConfigAddress("inbox");

        if (LOG.code.length > 0) {
            chainlog = ChainLog(LOG);
            owner = chainlog.getAddress("MCD_PAUSE_PROXY");
            escrow = chainlog.getAddress("ARBITRUM_ESCROW");
            l1GovRelay = chainlog.getAddress("ARBITRUM_GOV_RELAY");
            l2GovRelay = L1GovernanceRelay(payable(l1GovRelay)).l2GovernanceRelay();
            l1Tokens = l1Domain.readConfigAddresses("tokens");
        } else {
            owner = deployer;
            vm.startBroadcast();
            chainlog = new ChainLog();
            escrow = address(new L1Escrow());
            chainlog.setAddress("ARBITRUM_ESCROW", escrow);
            vm.stopBroadcast();

            l2Domain.selectFork();
            l2GovRelay = vm.computeCreateAddress(L2_DEPLOYER, vm.getNonce(L2_DEPLOYER) + 4); // {deploy gateway, deploy l2Spell, rely, deny} => 4 nonces to skip

            l1Domain.selectFork();
            vm.startBroadcast();
            l1GovRelay = address(new L1GovernanceRelay(inbox, l2GovRelay));
            chainlog.setAddress("ARBITRUM_GOV_RELAY", l1GovRelay);

            if (l1Domain.hasConfigKey("tokens")) {
                l1Tokens = l1Domain.readConfigAddresses("tokens");
            } else {
                uint256 count = l2Domain.hasConfigKey("tokens") ? l2Domain.readConfigAddresses("tokens").length : 2;
                l1Tokens = new address[](count);
                for (uint256 i; i < count; ++i) {
                    l1Tokens[i] = address(new GemMock(1_000_000_000 ether));
                }
            }
            vm.stopBroadcast();
        }

        l2Domain.selectFork();
        address l2Gateway = vm.computeCreateAddress(L2_DEPLOYER, vm.getNonce(L2_DEPLOYER));

        l1Domain.selectFork();
        vm.startBroadcast();
        address l1Gateway = TokenGatewayDeploy.deployL1Gateway(deployer, owner, l2Gateway, l1Router, inbox, escrow);
        vm.stopBroadcast();

        // Export contract addresses

        ScriptTools.exportContract("deployed", "chainlog", address(chainlog));
        ScriptTools.exportContract("deployed", "owner", owner);
        ScriptTools.exportContract("deployed", "l1Router", l1Router);
        ScriptTools.exportContract("deployed", "inbox", inbox);
        ScriptTools.exportContract("deployed", "escrow", escrow);
        ScriptTools.exportContract("deployed", "l1GovRelay", l1GovRelay);
        ScriptTools.exportContract("deployed", "l2GovRelay", l2GovRelay);
        ScriptTools.exportContract("deployed", "l1Gateway", l1Gateway);
        ScriptTools.exportContract("deployed", "l2Gateway", l2Gateway);
        ScriptToolsExtended.exportContracts("deployed", "l1Tokens", l1Tokens);
    }
}
