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

interface L2TokenGatewayLike {
    function isOpen() external view returns (uint256);
    function counterpartGateway() external view returns (address);
    function l2Router() external view returns (address);
    function rely(address) external;
    function deny(address) external;
    function close() external;
    function registerToken(address, address) external;
}

interface AuthLike {
    function rely(address usr) external;
}

// A reusable L2 spell to be used by the L2GovernanceRelay to exert admin control over L2TokenGateway
contract L2TokenGatewaySpell {
    L2TokenGatewayLike public immutable l2Gateway;

    constructor(address l2Gateway_) {
        l2Gateway = L2TokenGatewayLike(l2Gateway_);
    }

    function rely(address usr) external { l2Gateway.rely(usr); }
    function deny(address usr) external { l2Gateway.deny(usr); }
    function close() external { l2Gateway.close(); }

    function registerTokens(address[] memory l1Tokens, address[] memory l2Tokens) public { 
        for (uint256 i; i < l2Tokens.length;) {
            l2Gateway.registerToken(l1Tokens[i], l2Tokens[i]);
            AuthLike(l2Tokens[i]).rely(address(l2Gateway));
            unchecked { ++i; }
        }
    }
    
    function init(
        address l2Gateway_,
        address counterpartGateway,
        address l2Router,
        address[] calldata l1Tokens,
        address[] calldata l2Tokens
    ) external {
        // sanity checks
        require(address(l2Gateway) == l2Gateway_, "L2TokenGatewaySpell/l2-gateway-mismatch");
        require(l2Gateway.isOpen() == 1, "L2TokenGatewaySpell/not-open");
        require(l2Gateway.counterpartGateway() == counterpartGateway, "L2TokenGatewaySpell/counterpart-gateway-mismatch");
        require(l2Gateway.l2Router() == l2Router, "L2TokenGatewaySpell/l2-router-mismatch");

        registerTokens(l1Tokens, l2Tokens);
    }
}
