// SPDX-FileCopyrightText: © 2024 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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

pragma solidity >=0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { L1TokenGatewayInstance } from "./L1TokenGatewayInstance.sol";
import { L2TokenGatewayInstance } from "./L2TokenGatewayInstance.sol";
import { L2TokenGatewaySpell } from "./L2TokenGatewaySpell.sol";
import { L1TokenGateway } from "src/L1TokenGateway.sol";
import { L2TokenGateway } from "src/L2TokenGateway.sol";

library TokenGatewayDeploy {
    function deployL1Gateway(
        address deployer,
        address owner,
        address l2Gateway,
        address l1Router,
        address inbox
    ) internal returns (L1TokenGatewayInstance memory l1GatewayInstance) {
        l1GatewayInstance.gatewayImp = address(new L1TokenGateway(l2Gateway, l1Router, inbox));
        l1GatewayInstance.gateway = address(new ERC1967Proxy(l1GatewayInstance.gatewayImp, abi.encodeCall(L1TokenGateway.initialize, ())));
        ScriptTools.switchOwner(l1GatewayInstance.gateway, deployer, owner);
    }

    function deployL2Gateway(
        address deployer,
        address owner,
        address l1Gateway,
        address l2Router
    ) internal returns (L2TokenGatewayInstance memory l2GatewayInstance) {
        l2GatewayInstance.gatewayImp = address(new L2TokenGateway(l1Gateway, l2Router));
        l2GatewayInstance.gateway = address(new ERC1967Proxy(l2GatewayInstance.gatewayImp, abi.encodeCall(L2TokenGateway.initialize, ())));
        l2GatewayInstance.spell = address(new L2TokenGatewaySpell(l2GatewayInstance.gateway));
        ScriptTools.switchOwner(l2GatewayInstance.gateway, deployer, owner);
    }
}
