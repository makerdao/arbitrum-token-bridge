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
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { TokenGatewayInit, GatewaysConfig, MessageParams } from "deploy/TokenGatewayInit.sol";
import { L2TokenGatewayInstance } from "deploy/L2TokenGatewayInstance.sol";
import { L2TokenGatewaySpell } from "deploy/L2TokenGatewaySpell.sol";
import { L2GovernanceRelay } from "deploy/mocks/L2GovernanceRelay.sol";
import { RetryableTickets } from "script/utils/RetryableTickets.sol";

contract Init is Script {
    using stdJson for string;

    uint256 l1PrivKey = vm.envUint("L1_PRIVATE_KEY");

    function run() external {
        StdChains.Chain memory l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        StdChains.Chain memory l2Chain = getChain(string(vm.envOr("L2", string("arbitrum_one"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        string memory deps   = ScriptTools.loadDependencies();
        Domain l1Domain = new Domain(config, l1Chain);
        Domain l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();

        DssInstance memory dss = MCD.loadFromChainlog(deps.readAddress(".chainlog"));

        address l1GovRelay = deps.readAddress(".l1GovRelay");
        address l2GovRelay = deps.readAddress(".l2GovRelay");
        RetryableTickets retryable = new RetryableTickets(l1Domain, l2Domain, l1GovRelay, l2GovRelay);

        address l1Gateway = deps.readAddress(".l1Gateway");
        GatewaysConfig memory cfg; 
        cfg.l1Router = deps.readAddress(".l1Router");
        cfg.inbox = deps.readAddress(".inbox");
        cfg.l1Tokens = deps.readAddressArray(".l1Tokens");
        cfg.l2Tokens = deps.readAddressArray(".l2Tokens");

        bytes memory initCalldata = abi.encodeCall(L2GovernanceRelay.relay, (
            deps.readAddress(".l2GatewaySpell"), 
            abi.encodeCall(L2TokenGatewaySpell.init, (
                deps.readAddress(".l2Gateway"),
                l1Gateway,
                deps.readAddress(".l2Router"),
                cfg.l1Tokens,
                cfg.l2Tokens
            ))
        ));
        cfg.xchainMsg = MessageParams({
            maxGas:            retryable.getMaxGas(initCalldata) * 150 / 100,
            gasPriceBid:       retryable.getGasPriceBid() * 200 / 100,
            maxSubmissionCost: retryable.getSubmissionFee(initCalldata) * 250 / 100
        });

        L2TokenGatewayInstance memory l2GatewayInstance = L2TokenGatewayInstance({
            spell:   deps.readAddress(".l2GatewaySpell"),
            gateway: deps.readAddress(".l2Gateway")
        });

        vm.startBroadcast(l1PrivKey);
        uint256 minGovRelayBal = cfg.xchainMsg.maxSubmissionCost + cfg.xchainMsg.maxGas * cfg.xchainMsg.gasPriceBid;
        if (l1GovRelay.balance < minGovRelayBal) {
            (bool success,) = l1GovRelay.call{value: minGovRelayBal - l1GovRelay.balance}("");
            require(success, "l1GovRelay topup failed");
        }

        TokenGatewayInit.initGateways(dss, l1Gateway, l2GatewayInstance, cfg);
        vm.stopBroadcast();
    }
}
