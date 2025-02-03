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

interface TokenGatewayLike {
    function finalizeInboundTransfer(address, address, address, uint256, bytes calldata) external;
}  

contract Auxiliar {
    function extractFrom(bytes calldata data) external pure returns (address from, bytes memory extraData) {
        (from, extraData) = abi.decode(data, (address, bytes));
    }

    function extractSubmission(bytes calldata data) external pure returns (uint256 submission, bytes memory extraData) {
        (submission, extraData) = abi.decode(data, (uint256, bytes));
    }

    function getL1DataHash(address l1Token, address from, address to, uint256 amount, bytes calldata data) external pure returns (bytes32) {
        return keccak256(abi.encodeCall(TokenGatewayLike.finalizeInboundTransfer, (
            l1Token,
            from,
            to,
            amount,
            abi.encode("", data)
        )));
    }

    function getL2DataHash(address l1Token, address from, address to, uint256 amount, bytes calldata data) external pure returns (bytes32) {
        return keccak256(abi.encodeCall(TokenGatewayLike.finalizeInboundTransfer, (
            l1Token,
            from,
            to,
            amount,
            abi.encode(0, data)
        )));
    }

    function applyL1ToL2Alias(address l1Address) external pure returns (address l2Address) {
        unchecked {
            l2Address = address(uint160(l1Address) + uint160(0x1111000000000000000000000000000000001111));
        }
    }
}
