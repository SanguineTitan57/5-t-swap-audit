// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/TSwapPool.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    TSwapPool pool;
    ERC20Mock weth;
    ERC20Mock poolToken;

    address liquidityProvider = makeAddr("lp");
    address swapper = makeAddr("swapper");

    // Ghost Variables - variables that only exist in our Handler
    int256 public actualDeltaY;
    int256 public expectedDeltaY;

    int256 public actualDeltaX;
    int256 public expectedDeltaX;

    int256 public startingX;
    int256 public startingY;

    constructor(TSwapPool _pool) {
        pool = _pool;
        weth = ERC20Mock(_pool.getWeth());
        poolToken = ERC20Mock(_pool.getPoolToken());
    }

    function deposit(uint256 wethAmount) public {
        // ensure pool has the minimum ETH reserve to accept deposits
        uint256 minimumAmount = pool.getMinimumWethDepositAmount();
        uint256 poolWethBalance = weth.balanceOf(address(pool));
        if (poolWethBalance < minimumAmount) return;

        uint256 maxOutput = (poolWethBalance * 99) / 100; // 99% to leave room for fee
        // Bound between min and pool weth's balance
        wethAmount = bound(wethAmount, minimumAmount, maxOutput);

        startingY = int256(poolToken.balanceOf(address(pool)));
        startingX = int256(weth.balanceOf(address(pool)));

        expectedDeltaX = int256(wethAmount);
        expectedDeltaY = int256(pool.getPoolTokensToDepositBasedOnWeth(wethAmount));

        vm.startPrank(liquidityProvider);
        weth.mint(liquidityProvider, wethAmount);
        poolToken.mint(liquidityProvider, uint256(expectedDeltaY));
        weth.approve(address(pool), type(uint256).max);
        poolToken.approve(address(pool), type(uint256).max);

        // Deposit
        pool.deposit(wethAmount, 0, uint256(expectedDeltaY), uint64(block.timestamp));
        vm.stopPrank();

        uint256 endingY = poolToken.balanceOf(address(pool));
        uint256 endingX = weth.balanceOf(address(pool));

        // sell tokens == x == poolTokens
        actualDeltaY = int256(endingY) - int256(startingY);
        actualDeltaX = int256(endingX) - int256(startingX);
    }

    function swapPoolTokenForWethBasedOnOutputWeth(uint256 outputWeth) public {
        if (weth.balanceOf(address(pool)) <= pool.getMinimumWethDepositAmount()) {
            return;
        }
        outputWeth = bound(outputWeth, pool.getMinimumWethDepositAmount(), type(uint64).max);
        if (outputWeth >= weth.balanceOf(address(pool))) {
            return;
        }
        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(
            outputWeth, poolToken.balanceOf(address(pool)), weth.balanceOf(address(pool))
        );

        startingY = int256(poolToken.balanceOf(address(pool)));
        startingX = int256(weth.balanceOf(address(pool)));

        expectedDeltaX = int256(-1) * int256(outputWeth);
        expectedDeltaY = int256(poolTokenAmount);

        if (poolToken.balanceOf(swapper) < poolTokenAmount) {
            poolToken.mint(swapper, poolTokenAmount - poolToken.balanceOf(swapper) + 1);
        }
        vm.startPrank(swapper);
        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        vm.stopPrank();

        uint256 endingY = poolToken.balanceOf(address(pool));
        uint256 endingX = weth.balanceOf(address(pool));

        actualDeltaY = int256(endingY) - int256(startingY);
        actualDeltaX = int256(endingX) - int256(startingX);
    }
}
