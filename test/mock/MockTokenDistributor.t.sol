// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import {ITokenDistributor} from "party-protocol/contracts/distribution/ITokenDistributor.sol";

contract MockTokenDistributor {
    function createErc20Distribution(
        address token,
        address party,
        address payable feeRecipient,
        uint16 feeBps
    ) external returns (ITokenDistributor.DistributionInfo memory info) {}

    function createNativeDistribution(
        address party,
        address payable feeRecipient,
        uint16 feeBps
    )
        external
        payable
        returns (ITokenDistributor.DistributionInfo memory info)
    {}
}
