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

import { L2TokenGateway } from "src/l2/L2TokenGateway.sol";

interface AuthLike {
    function rely(address usr) external;
    function deny(address usr) external;
}

// A reusable L2 spell to be used by the L2GovernanceRelay to exert admin control over L2TokenGateway
contract L2TokenGatewaySpell {
    L2TokenGateway public immutable l2Gateway;
    constructor(address l2Gateway_) {
        l2Gateway = L2TokenGateway(l2Gateway_);
    }

    function rely(address usr) external { l2Gateway.rely(usr); }
    function deny(address usr) external { l2Gateway.deny(usr); }
    function close() external { l2Gateway.close(); }
    function registerToken(address l1Token, address l2Token) external { l2Gateway.registerToken(l1Token, l2Token); }
    function registerTokens(address[] calldata l1Tokens, address[] calldata l2Tokens) external { l2Gateway.registerTokens(l1Tokens, l2Tokens); }

    // Additional methods to grant the l2Gateway admin access to a collection of l2Tokens. 
    // These methods are included here so as to avoid having to deploy additional L2 spells to support these operations
    function relyGateway(address[] calldata l2Tokens) external {
        for(uint256 i; i < l2Tokens.length;) {
            AuthLike(l2Tokens[i]).rely(address(l2Gateway));
            unchecked { ++i; }
        }
    }
    function denyGateway(address[] calldata l2Tokens) external {
        for(uint256 i; i < l2Tokens.length;) {
            AuthLike(l2Tokens[i]).deny(address(l2Gateway));
            unchecked { ++i; }
        }
    }
}
