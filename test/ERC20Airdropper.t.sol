// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "src/ERC20Airdropper.sol";

contract ERC20AirdropperTest is Test {
    event ERC20Created(
        address indexed token,
        string name,
        string symbol,
        uint256 totalSupply
    );
    event Airdropped(
        address indexed token,
        ERC20Airdropper.Recipient[] recipients
    );

    ERC20Airdropper airdropper;

    function setUp() public {
        airdropper = new ERC20Airdropper();
    }

    function testCreateToken() public {
        string memory name = "Test Token";
        string memory symbol = "TTT";
        uint256 totalSupply = 1000e18;

        ERC20Airdropper.Recipient[]
            memory recipients = new ERC20Airdropper.Recipient[](3);
        recipients[0] = ERC20Airdropper.Recipient(vm.addr(1), 100e18);
        recipients[1] = ERC20Airdropper.Recipient(vm.addr(2), 200e18);
        recipients[2] = ERC20Airdropper.Recipient(vm.addr(3), 300e18);

        address expectedToken = vm.computeCreateAddress(address(airdropper), 1);
        vm.expectEmit(true, true, true, true);
        emit ERC20Created(expectedToken, name, symbol, totalSupply);
        vm.expectEmit(true, true, true, true);
        emit Airdropped(expectedToken, recipients);

        ERC20 token = airdropper.createToken(
            name,
            symbol,
            totalSupply,
            recipients
        );

        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
        assertEq(token.totalSupply(), totalSupply);

        assertEq(token.balanceOf(recipients[0].addr), 100e18);
        assertEq(token.balanceOf(recipients[1].addr), 200e18);
        assertEq(token.balanceOf(recipients[2].addr), 300e18);
        assertEq(token.balanceOf(address(this)), 400e18);
    }

    function testCreateToken_noRecipients() public {
        string memory name = "Test Token";
        string memory symbol = "TTT";
        uint256 totalSupply = 1000e18;

        ERC20Airdropper.Recipient[]
            memory recipients = new ERC20Airdropper.Recipient[](0);

        ERC20 token = airdropper.createToken(
            name,
            symbol,
            totalSupply,
            recipients
        );

        assertEq(token.balanceOf(address(this)), totalSupply);
    }

    function testCreateToken_noRemainingBalance() public {
        string memory name = "Test Token";
        string memory symbol = "TTT";
        uint256 totalSupply = 1000e18;

        ERC20Airdropper.Recipient[]
            memory recipients = new ERC20Airdropper.Recipient[](3);
        recipients[0] = ERC20Airdropper.Recipient(vm.addr(1), 200e18);
        recipients[1] = ERC20Airdropper.Recipient(vm.addr(2), 300e18);
        recipients[2] = ERC20Airdropper.Recipient(vm.addr(3), 500e18);

        ERC20 token = airdropper.createToken(
            name,
            symbol,
            totalSupply,
            recipients
        );

        assertEq(token.balanceOf(recipients[0].addr), 200e18);
        assertEq(token.balanceOf(recipients[1].addr), 300e18);
        assertEq(token.balanceOf(recipients[2].addr), 500e18);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testCreateToken_totalAmountsExceedsTotalSupply() public {
        string memory name = "Test Token";
        string memory symbol = "TTT";
        uint256 totalSupply = 1000e18;

        ERC20Airdropper.Recipient[]
            memory recipients = new ERC20Airdropper.Recipient[](3);
        recipients[0] = ERC20Airdropper.Recipient(vm.addr(1), 200e18);
        recipients[1] = ERC20Airdropper.Recipient(vm.addr(2), 300e18);
        recipients[2] = ERC20Airdropper.Recipient(vm.addr(3), 600e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(airdropper),
                500e18, // Remaining balance in airdropper
                600e18 // Amount to transfer to last recipient
            )
        );
        airdropper.createToken(name, symbol, totalSupply, recipients);
    }
}
