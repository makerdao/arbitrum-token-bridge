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
import { RetryableTickets } from "script/utils/RetryableTickets.sol";

interface GemLike {
    function approve(address, uint256) external;
}

interface GatewayLike {
    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable returns (bytes memory);
    function getOutboundCalldata(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external pure returns (bytes memory);
}

// Test deployment in config.json
contract Deposit is Script {
    using stdJson for string;

    uint256 l1PrivKey = vm.envUint("L1_PRIVATE_KEY");
    uint256 l2PrivKey = vm.envUint("L2_PRIVATE_KEY");
    address l1Deployer = vm.addr(l1PrivKey);
    address l2Deployer = vm.addr(l2PrivKey);

    function run() external {
        StdChains.Chain memory l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        StdChains.Chain memory l2Chain = getChain(string(vm.envOr("L2", string("arbitrum_one"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        string memory deps   = ScriptTools.loadDependencies();
        Domain l1Domain = new Domain(config, l1Chain);
        Domain l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();
       
        address l1Gateway = deps.readAddress(".l1Gateway");
        address l2Gateway = deps.readAddress(".l2Gateway");
        address l1Token = deps.readAddressArray(".l1Tokens")[0];

        RetryableTickets retryable = new RetryableTickets(l1Domain, l2Domain, l1Gateway, l2Gateway);

        uint256 amount = 1 ether;
        bytes memory finalizeDepositCalldata = GatewayLike(l1Gateway).getOutboundCalldata({
            l1Token: l1Token, 
            from:    l1Deployer,
            to:      l2Deployer, 
            amount:  amount,
            data:    ""
        });
        uint256 maxGas = retryable.getMaxGas(finalizeDepositCalldata) * 150 / 100;
        uint256 gasPriceBid = retryable.getGasPriceBid() * 200 / 100;
        uint256 maxSubmissionCost = retryable.getSubmissionFee(finalizeDepositCalldata) * 250 / 100;
        uint256 l1CallValue = maxSubmissionCost + maxGas * gasPriceBid;

        vm.startBroadcast(l1PrivKey);
        GemLike(l1Token).approve(l1Gateway, type(uint256).max);
        GatewayLike(l1Gateway).outboundTransfer{value: l1CallValue}({
            l1Token:     l1Token, 
            to:          l2Deployer, 
            amount:      amount, 
            maxGas:      maxGas, 
            gasPriceBid: gasPriceBid,
            data:        abi.encode(maxSubmissionCost, bytes(""))
        });
        vm.stopBroadcast();
    }
}
