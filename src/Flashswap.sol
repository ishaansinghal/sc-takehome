// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
/// NOTE You may import more dependencies as needed
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {PoolAddress, Path, CallbackValidation, TickMath} from "./dependencies/Uniswap.sol";
import {IFlashswapCallback} from "./interfaces/IFlashswapCallback.sol";

/// @title Flashswap
/// @notice Enables a "multi-hop flashswap" using Uniswap.
contract Flashswap is IUniswapV3SwapCallback {
    address internal constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    struct ExactOutputParams {
        bytes path; // Uniswap multi-hop swap path
        address recipient; 
        uint256 amountOut;
        bytes data; // Data passed to the caller's own callback control flow
    }

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        bytes data;
    }

    /// TODO Implement this callback function. See the interface for more
    /// descriptions.
    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(amount0Delta > 0 || amount1Delta > 0);

        (bytes memory path, address payer, bytes memory expectedData, uint256 originalAmtOut) = abi.decode(data, (bytes, address, bytes, uint256));

        (address tokenIn, address tokenOut, uint24 fee) = Path.decodeFirstPool(path);
        CallbackValidation.verifyCallback(FACTORY, tokenIn, tokenOut, fee);

        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        if (Path.hasMultiplePools(path)) {

            bytes memory nextPath = Path.skipToken(path);
            (address nextTokenIn, address nextTokenOut, uint24 nextFee) = Path.decodeFirstPool(nextPath);

            IUniswapV3Pool nextPool = _getPool(nextTokenIn, nextTokenOut, nextFee);
            require(address(nextPool) != address(0), "Flashswap: Next pool not found");

            bool zeroForOne = nextTokenIn != nextPool.token0();

            bytes memory nextData = abi.encode(nextPath, payer, expectedData, originalAmtOut);

            nextPool.swap(
                msg.sender, zeroForOne, -int256(amountToPay), zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1, nextData
            );

        } else {
            IFlashswapCallback(payer).flashSwapCallback(originalAmtOut, amountToPay, address(_getPool(tokenIn, tokenOut, fee)), expectedData);
        }
    }

    /// TODO Implement this function.
    /// @notice This is the entrypoint for the caller.
    /// @param params See `ExactOutputParams`.
    function exactOutput(ExactOutputParams calldata params) external {
    
        address recipient = params.recipient == address(0) ? address(this) : params.recipient;

        (address tokenIn, address tokenOut, uint24 fee) = Path.decodeFirstPool(params.path);

        IUniswapV3Pool pool = _getPool(tokenIn, tokenOut, fee);
        require(address(pool) != address(0), "Pool not found");

        bool zeroForOne = tokenIn != pool.token0();

        bytes memory data = abi.encode(params.path, msg.sender, params.data, params.amountOut);

        pool.swap(
            recipient,
            zeroForOne,
            -int256(params.amountOut),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            data
        );
    }

    /// NOTE: This implementation is optional.
    /// @notice Instead of having the user specify the exact ouptut amount they
    /// want in the swap, they can specify the exact input amount.
    /// @param params See `ExactInputParams`.
    function exactInput(ExactInputParams calldata params) external {}

    /// @dev Returns the pool for the given token pair and fee. The pool contract may or may not exist.
    function _getPool(address tokenA, address tokenB, uint24 fee) private pure returns (IUniswapV3Pool) {
        return IUniswapV3Pool(PoolAddress.computeAddress(FACTORY, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }
}