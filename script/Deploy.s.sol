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
import { TokenGatewayDeploy, L2TokenGatewayInstance } from "deploy/TokenGatewayDeploy.sol";
import { ChainLog } from "deploy/mocks/ChainLog.sol";
import { L1Escrow } from "deploy/mocks/L1Escrow.sol";
import { L1GovernanceRelay } from "deploy/mocks/L1GovernanceRelay.sol";
import { L2GovernanceRelay } from "deploy/mocks/L2GovernanceRelay.sol";
import { GemMock } from "test/mocks/GemMock.sol";

interface L1RouterLike {
    function counterpartGateway() external view returns (address);
    function inbox() external view returns (address);
}

interface L1DaiGatewayLike {
    function l1Router() external view returns (address);
}

contract Deploy is Script {

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    struct Tokens {
        address l1Nst;
        address l1Ngt;
        address l2Nst;
        address l2Ngt;
    } 

    function run() external {

        uint256 l1 = vm.createFork(vm.envString("ETH_RPC_URL"));
        uint256 l2 = vm.createFork(vm.envString("ARB_RPC_URL"));

        (,address deployer, ) = vm.readCallers();

        vm.selectFork(l1);
       
        ChainLog chainlog;
        address owner;
        address l1Router;
        address inbox;
        address escrow;
        address l1GovRelay;
        address l2GovRelay;
        Tokens memory tokens;
        if (LOG.code.length > 0) {
            chainlog = ChainLog(LOG);
            owner = chainlog.getAddress("MCD_PAUSE_PROXY");
            l1Router = L1DaiGatewayLike(chainlog.getAddress("ARBITRUM_DAI_BRIDGE")).l1Router();
            inbox = L1RouterLike(l1Router).inbox();
            escrow = chainlog.getAddress("ARBITRUM_ESCROW");
            l1GovRelay = chainlog.getAddress("ARBITRUM_GOV_RELAY");
            tokens.l1Nst = chainlog.getAddress("NST");
            tokens.l1Ngt = chainlog.getAddress("NGT");

            vm.selectFork(l2);
            l2GovRelay = L1GovernanceRelay(payable(l1GovRelay)).l2GovernanceRelay();
            // TODO: deploy actual L2 token contracts { l2Nst, l2Ngt }
        } else {
            owner = deployer;
            vm.startBroadcast();
            chainlog = new ChainLog();
            l1Router = vm.envAddress("L1_ROUTER");
            inbox = L1RouterLike(l1Router).inbox();
            escrow = address(new L1Escrow());
            chainlog.setAddress("ARBITRUM_ESCROW", escrow);
            vm.stopBroadcast();

            vm.selectFork(l2);
            address l2GovRelay_ = vm.computeCreateAddress(deployer, vm.getNonce(deployer));

            vm.selectFork(l1);
            vm.startBroadcast();
            l1GovRelay = address(new L1GovernanceRelay(inbox, l2GovRelay_));
            tokens.l1Nst = address(new GemMock(1_000_000_000 ether));
            tokens.l1Ngt = address(new GemMock(1_000_000_000 ether));
            chainlog.setAddress("ARBITRUM_GOV_RELAY", l1GovRelay);
            chainlog.setAddress("NST", tokens.l1Nst);
            chainlog.setAddress("NGT", tokens.l1Ngt);
            vm.stopBroadcast();

            vm.selectFork(l2);
            vm.startBroadcast();
            l2GovRelay = address(new L2GovernanceRelay(l1GovRelay));
            require(l2GovRelay == l2GovRelay_, "l2GovRelay address mismatch");
            tokens.l2Nst = address(new GemMock(0));
            tokens.l2Ngt = address(new GemMock(0));
            GemMock(tokens.l2Nst).rely(l2GovRelay);
            GemMock(tokens.l2Ngt).rely(l2GovRelay);
            GemMock(tokens.l2Nst).deny(deployer);
            GemMock(tokens.l2Ngt).deny(deployer);
            vm.stopBroadcast();
        }

        // L1 deployment

        vm.selectFork(l2);
        address l2Gateway = vm.computeCreateAddress(deployer, vm.getNonce(deployer));

        vm.selectFork(l1);
        vm.startBroadcast();
        address l1Gateway = TokenGatewayDeploy.deployL1Gateway(deployer, owner, l2Gateway, l1Router, inbox, escrow);
        vm.stopBroadcast();
        address l2Router = L1RouterLike(l1Router).counterpartGateway();

        // L2 deployment

        vm.selectFork(l2);
        vm.startBroadcast();
        L2TokenGatewayInstance memory l2GatewayInstance = TokenGatewayDeploy.deployL2Gateway(deployer, owner, l1Gateway, l2Router);
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
        ScriptTools.exportContract("deployed", "l1Nst", tokens.l1Nst);
        ScriptTools.exportContract("deployed", "l2Nst", tokens.l2Nst);
        ScriptTools.exportContract("deployed", "l1Ngt", tokens.l1Ngt);
        ScriptTools.exportContract("deployed", "l2Ngt", tokens.l2Ngt);
    }
}