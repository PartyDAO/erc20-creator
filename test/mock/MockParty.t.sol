// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

contract MockParty {
    struct GovernanceValues {
        uint40 voteDuration;
        uint40 executionDelay;
        uint16 passThresholdBps;
        uint96 totalVotingPower;
    }

    function getGovernanceValues()
        external
        pure
        returns (GovernanceValues memory)
    {
        return
            GovernanceValues({
                voteDuration: 1 days,
                executionDelay: 1 days,
                passThresholdBps: 5000,
                totalVotingPower: 1e18
            });
    }

    function tokenCount() external pure returns (uint256) {
        return 100;
    }

    receive() external payable {}
}
