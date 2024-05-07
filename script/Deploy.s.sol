// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8;

import "forge-std/Script.sol";
import "src/ERC20Airdropper.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();
        ERC20Airdropper airdropper = new ERC20Airdropper(
            Dropper(address(0x2871e49a08AceE842C8F225bE7BFf9cC311b9F43))
        );
        console.log(address(airdropper));
        vm.stopBroadcast();
    }
}
