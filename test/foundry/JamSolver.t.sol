// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "../../src/JamSolver.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract JamSolverTest is Test {
    JamSolver solverContract;
    address internal settlement;
    address internal solver;
    ERC20PresetMinterPauser internal token1;
    ERC20PresetMinterPauser internal token2;
    uint256 MAX_AMOUNT = 10000000;

    function setUp() public {
        solver = address(2);
        settlement = address(4);
        token1 = new ERC20PresetMinterPauser('token1', 'TOK1');
        token2 = new ERC20PresetMinterPauser('token2', 'TOK2');
        token1.mint(address(this), MAX_AMOUNT);
        token2.mint(address(this), MAX_AMOUNT);
        vm.prank(solver);

        // TODO: tests validating settlement sender and deployer origin
        solverContract = new JamSolver(settlement);
    }

    function _notBuiltinAddress(address addr) internal view {
        vm.assume(addr != address(this));
        vm.assume(addr != address(vm));
        vm.assume(addr > address(9));
    } 

    function testWithdrawTokens(uint256 amount1, uint256 amount2) public {
        vm.assume(amount1 < MAX_AMOUNT);
        vm.assume(amount2 < MAX_AMOUNT);
        token1.transfer(address(solverContract), amount1);
        token2.transfer(address(solverContract), amount2);
        address[] memory withdrawTokens = new address[](2);
        withdrawTokens[0] = address(token1);
        withdrawTokens[1] = address(token2);
        vm.prank(solver);
        solverContract.withdrawTokens(withdrawTokens, solver);
        assertEq(token1.balanceOf(solver), amount1);
        assertEq(token2.balanceOf(solver), amount2);
    }

    function testWithdrawEth(uint256 ethAmount) public {
        vm.assume(ethAmount < 100 ether);
        vm.deal(address(solverContract), ethAmount);
        vm.prank(solver);
        solverContract.withdraw(solver);
        assertEq(address(solver).balance, ethAmount);
    }

    function testOwnership(address random) public {
        _notBuiltinAddress(random);
        vm.prank(random);
        vm.expectRevert();
        solverContract.withdraw(solver);

        vm.prank(random);
        vm.expectRevert();
        solverContract.withdrawTokens(new address[](0), random);
    }
}