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

import { DssInstance } from "dss-test/MCD.sol";
import { L2TokenGatewayInstance } from "./L2TokenGatewayInstance.sol";
import { L2TokenGatewaySpell } from "./L2TokenGatewaySpell.sol";

interface GatewayLike {
    function registerTokens(address[] calldata, address[] calldata) external;
    function l1ToL2Token(address) external returns (address);
}

interface L1RelayLike {
    function relay(
        address target,
        bytes calldata targetData,
        uint256 l1CallValue,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 maxSubmissionCost
    ) external payable;
}

interface EscrowLike {
    function approve(address, address, uint256) external;
}

// TODO: add immutable checks
struct GatewaysConfig {
    address[] l1Tokens;
    address[] l2Tokens;
    uint256 maxGas;
    uint256 gasPriceBid;
    uint256 maxSubmissionCost;
}

library TokenGatewayInit {
    function addTokens(
        DssInstance memory            dss,
        address                       l1Gateway_,
        L2TokenGatewayInstance memory l2GatewayInstance,
        GatewaysConfig memory         cfg
    ) internal {
        require(cfg.l1Tokens.length == cfg.l2Tokens.length, "TokenGatewayInit/token-arrays-mismatch");

        GatewayLike l1Gateway = GatewayLike(l1Gateway_);
        L1RelayLike l1GovRelay = L1RelayLike(dss.chainlog.getAddress("ARBITRUM_GOV_RELAY"));
        EscrowLike escrow = EscrowLike(dss.chainlog.getAddress("ARBITRUM_ESCROW"));

        uint256 l1CallValue = cfg.maxSubmissionCost + cfg.maxGas * cfg.gasPriceBid;

        // not strictly necessary (as the retryable ticket creation would otherwise fail) 
        // but makes the eth balance requirement more explicit
        require(address(l1GovRelay).balance >= l1CallValue, "TokenGatewayInit/insufficient-relay-balance");


        for(uint256 i; i < cfg.l1Tokens.length; ++i) {
            (address l1Token, address l2Token) = (cfg.l1Tokens[i], cfg.l2Tokens[i]);
            require(l1Token != address(0), "TokenGatewayInit/invalid-l1-token");
            require(l2Token != address(0), "TokenGatewayInit/invalid-l2-token");
            require(l1Gateway.l1ToL2Token(l1Token) == address(0), "TokenGatewayInit/existing-l1-token");

            escrow.approve(l1Token, l1Gateway_, type(uint256).max);
        }

        l1Gateway.registerTokens(cfg.l1Tokens, cfg.l2Tokens);
        l1GovRelay.relay({
            target:            l2GatewayInstance.spell,
            targetData:        abi.encodeCall(L2TokenGatewaySpell.registerTokens, (cfg.l1Tokens, cfg.l2Tokens)),
            l1CallValue:       l1CallValue,
            maxGas:            cfg.maxGas,
            gasPriceBid:       cfg.gasPriceBid,
            maxSubmissionCost: cfg.maxSubmissionCost
        });
    }

    function initGateways(
        DssInstance memory            dss,
        address                       l1Gateway_,
        L2TokenGatewayInstance memory l2GatewayInstance,
        GatewaysConfig memory         cfg
    ) internal {
        addTokens(dss, l1Gateway_, l2GatewayInstance, cfg);

        // TODO add l1Gateway to chainlog
    }
}
