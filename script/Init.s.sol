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
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { TokenGatewayInit, GatewaysConfig, MessageParams } from "deploy/TokenGatewayInit.sol";
import { L2TokenGatewayInstance } from "deploy/L2TokenGatewayInstance.sol";
import { L2TokenGatewaySpell } from "deploy/L2TokenGatewaySpell.sol";
import { L2GovernanceRelay } from "deploy/mocks/L2GovernanceRelay.sol";

interface InboxLike {
    function calculateRetryableSubmissionFee(uint256,uint256) external view returns (uint256);
}

contract Init is Script {
    using stdJson for string;

    Domain l1Domain;
    ArbitrumDomain l2Domain;

    address inbox;
    address l1GovRelay;
    address l2GovRelay;

    function getSubmissionFee(bytes memory spellCalldata) internal returns (uint256 fee) {
        uint256 fork = vm.activeFork();
        l1Domain.selectFork();

        fee = InboxLike(inbox).calculateRetryableSubmissionFee(spellCalldata.length, 0);

        vm.selectFork(fork);
    }

    function getMaxGas(bytes memory spellCalldata) internal returns (uint256 maxGas) {
        bytes memory data = abi.encodeWithSignature(
            "estimateRetryableTicket(address,uint256,address,uint256,address,address,bytes)", 
            l1GovRelay,
            1 ether,
            l2GovRelay,
            0,
            l2GovRelay,
            l2GovRelay,
            spellCalldata
        );

        uint256 fork = vm.activeFork();
        l2Domain.selectFork();

        // this call MUST be executed via RPC, see https://docs.arbitrum.io/build-decentralized-apps/nodeinterface/overview
        bytes memory res = vm.rpc("eth_estimateGas", string(abi.encodePacked(
            "[{\"to\": \"", 
            vm.toString(address(0xc8)), // NodeInterface
            "\", \"data\": \"",    
            vm.toString(data)
            ,
            "\"}]"
        )));
        maxGas = vm.parseUint(vm.toString(res));

        vm.selectFork(fork);
    }

    function getGasPriceBid() internal returns (uint256 gasPrice) {
        uint256 fork = vm.activeFork();
        l2Domain.selectFork();

        bytes memory res = vm.rpc("eth_gasPrice", "[]");
        gasPrice = vm.parseUint(vm.toString(res));

        vm.selectFork(fork);
    }

    function run() external {
        string memory config = ScriptTools.readInput("config"); // loads from FOUNDRY_SCRIPT_CONFIG
        string memory deps = ScriptTools.loadDependencies(); // loads from FOUNDRY_SCRIPT_DEPS
        
        l1Domain = new Domain(config, getChain(string(vm.envOr("L1", string("mainnet")))));
        l1Domain.selectFork();
        l2Domain = new ArbitrumDomain(config, getChain(vm.envOr("L2", string("arbitrum_one"))), l1Domain);
        getGasPriceBid();
       
        DssInstance memory dss = MCD.loadFromChainlog(deps.readAddress(".chainlog"));

        inbox = deps.readAddress(".inbox");
        l1GovRelay = deps.readAddress(".l1GovRelay");
        l2GovRelay = deps.readAddress(".l2GovRelay");

        GatewaysConfig memory cfg; 
        cfg.counterpartGateway = deps.readAddress(".l2Gateway");
        cfg.l1Router = deps.readAddress(".l1Router");
        cfg.inbox = inbox;
        cfg.l1Tokens = new address[](2);
        cfg.l1Tokens[0] = deps.readAddress(".l1Nst");
        cfg.l1Tokens[1] = deps.readAddress(".l1Ngt");
        cfg.l2Tokens = new address[](2);
        cfg.l2Tokens[0] = deps.readAddress(".l2Nst");
        cfg.l2Tokens[1] = deps.readAddress(".l2Ngt");

        bytes memory registerTokensCalldata = abi.encodeCall(L2GovernanceRelay.relay, (
            deps.readAddress(".l2GatewaySpell"), 
            abi.encodeCall(L2TokenGatewaySpell.registerTokens, (cfg.l1Tokens, cfg.l2Tokens))
        ));
        cfg.xchainMsg = MessageParams({
            maxGas:            getMaxGas(registerTokensCalldata) * 150 / 100,
            gasPriceBid:       getGasPriceBid() * 200 / 100,
            maxSubmissionCost: getSubmissionFee(registerTokensCalldata) * 300 / 100
        });

        L2TokenGatewayInstance memory l2GatewayInstance = L2TokenGatewayInstance({
            spell:   deps.readAddress(".l2GatewaySpell"),
            gateway: deps.readAddress(".l2Gateway")
        });

        vm.startBroadcast();
        uint256 minGovRelayBal = cfg.xchainMsg.maxSubmissionCost + cfg.xchainMsg.maxGas * cfg.xchainMsg.gasPriceBid;
        if (l1GovRelay.balance < minGovRelayBal) {
            (bool success,) = l1GovRelay.call{value: minGovRelayBal - l1GovRelay.balance}("");
            require(success, "l1GovRelay topup failed");
        }

        TokenGatewayInit.initGateways(dss, deps.readAddress(".l1Gateway"), l2GatewayInstance, cfg);
        vm.stopBroadcast();
    }
}