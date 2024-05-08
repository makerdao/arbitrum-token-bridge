// SPDX-License-Identifier: AGPL-3.0-or-later

/// Ngt.sol -- Ngt token

// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico
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

import { ITokenGateway } from "../arbitrum/ITokenGateway.sol";
import { IL1ArbitrumGateway } from "../arbitrum/IL1ArbitrumGateway.sol";
import { ICustomGateway } from "../arbitrum/ICustomGateway.sol";
import { IERC165, ERC165 } from "../arbitrum/ERC165.sol";
import { L1ArbitrumMessenger } from "../arbitrum/L1ArbitrumMessenger.sol";

interface TokenLike {
    function transferFrom(address, address, uint256) external;
}

contract L1TokenGateway is ITokenGateway, IL1ArbitrumGateway, ICustomGateway, ERC165, L1ArbitrumMessenger {
    // --- storage variables ---

    mapping(address => uint256) public wards;
    mapping(address => address) public l1ToL2Token;
    uint256 public isOpen = 1;

    // --- immutables ---

    address public immutable counterpartGateway;
    address public immutable l1Router;
    address public immutable inbox;
    address public immutable escrow;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Closed();
    event DepositInitiated(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _sequenceNumber,
        uint256 _amount
    );
    event WithdrawalFinalized(
        address l1Token,
        address indexed _from,
        address indexed _to,
        uint256 indexed _exitNum,
        uint256 _amount
    );

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "L1TokenGateway/not-authorized");
        _;
    }

    modifier onlyCounterpartGateway() {
        // a message coming from the counterpart gateway was executed by the bridge
        address bridge = address(getBridge(inbox));
        require(msg.sender == bridge, "L1TokenGateway/not-from-bridge");

        // and the outbox reports that the L2 address of the sender is the counterpart gateway
        address l2ToL1Sender = getL2ToL1Sender(inbox);
        require(l2ToL1Sender == counterpartGateway, "L1TokenGateway/only-counterpart-gateway");
        _;
    }

    // --- constructor ---

    constructor(
        address _counterpartGateway,
        address _l1Router,
        address _inbox,
        address _escrow
    ) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        counterpartGateway = _counterpartGateway;
        l1Router = _l1Router;
        inbox = _inbox;
        escrow = _escrow;
    }

    // --- administration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function close() external auth {
        isOpen = 0;
        emit Closed();
    }

    function registerToken(address l1Token, address l2Token) external auth {
        l1ToL2Token[l1Token] = l2Token;
        emit TokenSet(l1Token, l2Token);
    }

    // --- ITokenGateway ---

    /**
     * @notice Calculate the address used when bridging an ERC20 token
     * @param l1Token address of L1 token
     * @return l2Token L2 address of a bridged ERC20 token
     */
    function calculateL2TokenAddress(address l1Token) external view override returns (address l2Token) {
        l2Token = l1ToL2Token[l1Token];
    }

    // --- IL1ArbitrumGateway ---

    // TODO: add unit test for supportsInterface
    
    /**
     * @notice See https://github.com/OffchainLabs/token-bridge-contracts/blob/c9e133600afb4e99ee5370c97a14cc5c666dd62c/contracts/tokenbridge/ethereum/gateway/L1ArbitrumGateway.sol#L331
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        // registering interfaces that is added after arb-bridge-peripherals >1.0.11
        // using function selector instead of single function interfaces to reduce bloat
        return
            interfaceId == this.outboundTransferCustomRefund.selector ||
            super.supportsInterface(interfaceId);
    }

    // --- outbound transfers ---

    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable returns (bytes memory res) {
        res = outboundTransferCustomRefund(l1Token, to, to, amount, maxGas, gasPriceBid, data);
    }

    function outboundTransferCustomRefund(
        address l1Token,
        address refundTo,
        address to,
        uint256 amount,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) public payable returns (bytes memory res) {

        // TODO: should we only allow call from router as per https://docs.arbitrum.io/build-decentralized-apps/token-bridging/bridge-tokens-programmatically/how-to-bridge-tokens-custom-gateway
        // Only allow calls from the router
        // require(msg.sender == router, "Call not received from router");

        require(isOpen == 1, "L1TokenGateway/closed"); // do not allow initiating new xchain messages if bridge is closed
        require(l1ToL2Token[l1Token] != address(0), "L1TokenGateway/invalid-token");
        address from;
        uint256 seqNum;
        bytes memory extraData;
        {
            uint256 maxSubmissionCost;
            (from, maxSubmissionCost, extraData) = parseOutboundData(data);
            require(extraData.length == 0, "L1TokenGateway/extra-data-not-allowed");

            TokenLike(l1Token).transferFrom(from, escrow, amount);

            res = getOutboundCalldata(l1Token, from, to, amount, ""); // override the res field to save on the stack

            seqNum = createOutboundTxCustomRefund(
                refundTo,
                from,
                maxGas,
                gasPriceBid,
                maxSubmissionCost,
                res
            );
        }

        emit DepositInitiated(l1Token, from, to, seqNum, amount);

        res = abi.encode(seqNum);
    }

    function parseOutboundData(bytes memory data)
        internal
        view
        returns (
            address from,
            uint256 maxSubmissionCost,
            bytes memory extraData
        )
    {
        (from, extraData) = msg.sender == l1Router ? abi.decode(data, (address, bytes)) : (msg.sender, data); // router encoded
        (maxSubmissionCost, extraData) = abi.decode(extraData, (uint256, bytes));  // user encoded
    }

    function getOutboundCalldata(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) public pure returns (bytes memory outboundCalldata) {
        outboundCalldata = abi.encodeWithSelector(
            ITokenGateway.finalizeInboundTransfer.selector,
            l1Token,
            from,
            to,
            amount,
            abi.encode("", data)
        );
    }

    function createOutboundTxCustomRefund(
        address refundTo,
        address from,
        uint256 maxGas,
        uint256 gasPriceBid,
        uint256 maxSubmissionCost,
        bytes memory outboundCalldata
    ) internal returns (uint256) {
        return
            sendTxToL2CustomRefund(
                inbox,
                counterpartGateway,
                refundTo,
                from,
                msg.value, // we forward the L1 call value to the inbox
                0, // l2 call value is 0
                L2GasParams({
                    _maxSubmissionCost: maxSubmissionCost,
                    _maxGas: maxGas,
                    _gasPriceBid: gasPriceBid
                }),
                outboundCalldata
            );
    }

    // --- inbound transfers ---

    /**
     * @notice Finalizes a withdrawal via Outbox message; callable only by L2Gateway.outboundTransfer
     * @param l1Token L1 address of token being withdrawn from
     * @param from initiator of withdrawal
     * @param to address the L2 withdrawal call set as the destination.
     * @param amount Token amount being withdrawn
     */
    function finalizeInboundTransfer(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes calldata /* data */
    ) external payable onlyCounterpartGateway {
        require(l1Token != address(0), "L1TokenGateway/invalid-token");

        TokenLike(l1Token).transferFrom(escrow, to, amount);

        emit WithdrawalFinalized(l1Token, from, to, 0, amount);
    }

}
