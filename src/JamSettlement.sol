// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./JamBalanceManager.sol";
import "./base/JamSigning.sol";
import "./base/JamTransfer.sol";
import "./interfaces/IJamBalanceManager.sol";
import "./interfaces/IJamSettlement.sol";
import "./interfaces/IWETH.sol";
import "./libraries/JamInteraction.sol";
import "./libraries/JamOrder.sol";
import "./libraries/JamHooks.sol";
import "./libraries/ExecInfo.sol";
import "./libraries/common/BMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/// @title JamSettlement
/// @notice The settlement contract executes the full lifecycle of a trade on chain.
/// Solvers figure out what "interactions" to pass to this contract such that the user order is fulfilled.
/// The contract ensures that only the user agreed price can be executed and otherwise will fail to execute.
/// As long as the trade is fulfilled, the solver is allowed to keep any potential excess.
contract JamSettlement is IJamSettlement, ReentrancyGuard, JamSigning, JamTransfer, ERC721Holder, ERC1155Holder {

    IJamBalanceManager public immutable balanceManager;

    constructor(address _permit2, address _daiAddress) {
        balanceManager = new JamBalanceManager(address(this), _permit2, _daiAddress);
    }

    receive() external payable {}

    function runInteractions(JamInteraction.Data[] calldata interactions) internal returns (bool result) {
        for (uint i; i < interactions.length; ++i) {
            // Prevent calls to balance manager
            require(interactions[i].to != address(balanceManager));
            bool execResult = JamInteraction.execute(interactions[i]);

            // Return false only if interaction was meant to succeed but failed.
            if (!execResult && interactions[i].result) return false;
        }
        return true;
    }

    /// @inheritdoc IJamSettlement
    function settle(
        JamOrder.Data calldata order,
        Signature.TypedSignature calldata signature,
        JamInteraction.Data[] calldata interactions,
        JamHooks.Def calldata hooks,
        ExecInfo.SolverData calldata solverData
    ) external payable nonReentrant {
        validateOrder(order, hooks, signature, solverData.curFillPercent);
        require(runInteractions(hooks.beforeSettle), "BEFORE_SETTLE_HOOKS_FAILED");
        balanceManager.transferTokens(
            IJamBalanceManager.TransferData(
                order.taker, solverData.balanceRecipient, order.sellTokens, order.sellAmounts,
                order.sellNFTIds, order.sellTokenTransfers, solverData.curFillPercent
            )
        );
        _settle(order, interactions, hooks, solverData.curFillPercent);
    }

    /// @inheritdoc IJamSettlement
    function settleWithTakerPermits(
        JamOrder.Data calldata order,
        Signature.TypedSignature calldata signature,
        Signature.TakerPermitsInfo calldata takerPermitsInfo,
        JamInteraction.Data[] calldata interactions,
        JamHooks.Def calldata hooks,
        ExecInfo.SolverData calldata solverData
    ) external payable nonReentrant {
        validateOrder(order, hooks, signature, solverData.curFillPercent);
        require(runInteractions(hooks.beforeSettle), "BEFORE_SETTLE_HOOKS_FAILED");
        balanceManager.transferTokensWithPermits(
            IJamBalanceManager.TransferData(
                order.taker, solverData.balanceRecipient, order.sellTokens, order.sellAmounts,
                order.sellNFTIds, order.sellTokenTransfers, solverData.curFillPercent
            ), takerPermitsInfo
        );
        _settle(order, interactions, hooks, solverData.curFillPercent);
    }

    /// @inheritdoc IJamSettlement
    function settleInternal(
        JamOrder.Data calldata order,
        Signature.TypedSignature calldata signature,
        JamHooks.Def calldata hooks,
        ExecInfo.MakerData calldata makerData
    ) external payable nonReentrant {
        validateOrder(order, hooks, signature, makerData.curFillPercent);
        require(runInteractions(hooks.beforeSettle), "BEFORE_SETTLE_HOOKS_FAILED");
        balanceManager.transferTokens(
            IJamBalanceManager.TransferData(
                order.taker, msg.sender, order.sellTokens, order.sellAmounts,
                order.sellNFTIds, order.sellTokenTransfers, makerData.curFillPercent
            )
        );
        _settleInternal(order, hooks, makerData);
    }

    /// @inheritdoc IJamSettlement
    function settleInternalWithTakerPermits(
        JamOrder.Data calldata order,
        Signature.TypedSignature calldata signature,
        Signature.TakerPermitsInfo calldata takerPermitsInfo,
        JamHooks.Def calldata hooks,
        ExecInfo.MakerData calldata makerData
    ) external payable nonReentrant {
        validateOrder(order, hooks, signature, makerData.curFillPercent);
        require(runInteractions(hooks.beforeSettle), "BEFORE_SETTLE_HOOKS_FAILED");
        balanceManager.transferTokensWithPermits(
            IJamBalanceManager.TransferData(
                order.taker, msg.sender, order.sellTokens, order.sellAmounts,
                order.sellNFTIds, order.sellTokenTransfers, makerData.curFillPercent
            ), takerPermitsInfo
        );
        _settleInternal(order, hooks, makerData);
    }

    function _settle(
        JamOrder.Data calldata order,
        JamInteraction.Data[] calldata interactions,
        JamHooks.Def calldata hooks,
        uint16 curFillPercent
    ) private {
        if (order.receiver == address(this)){
            uint256[] memory initialReceiverBalances = getInitialBalances(
                order.buyTokens,order.buyNFTIds, order.buyTokenTransfers, order.receiver
            );
            require(runInteractions(interactions), "INTERACTIONS_FAILED");
            verifyBalances(
                order.buyTokens, order.buyAmounts, initialReceiverBalances, order.buyNFTIds, order.buyTokenTransfers, order.receiver
            );
            require(hooks.afterSettle.length > 0, "AFTER_SETTLE_HOOKS_REQUIRED");
        } else {
            require(runInteractions(interactions), "INTERACTIONS_FAILED");
            transferTokensFromContract(
                order.buyTokens, order.buyAmounts, order.buyNFTIds, order.buyTokenTransfers, order.receiver, curFillPercent
            );
        }
        require(runInteractions(hooks.afterSettle), "AFTER_SETTLE_HOOKS_FAILED");
        emit Settlement(order.nonce);
    }

    function _settleInternal(
        JamOrder.Data calldata order,
        JamHooks.Def calldata hooks,
        ExecInfo.MakerData calldata makerData
    ) private {
        uint256[] calldata buyAmounts = validateIncreasedAmounts(makerData.increasedBuyAmounts, order.buyAmounts);
        balanceManager.transferTokens(
            IJamBalanceManager.TransferData(
                msg.sender, order.receiver, order.buyTokens, buyAmounts,
                order.buyNFTIds, order.buyTokenTransfers, makerData.curFillPercent
            )
        );
        require(runInteractions(hooks.afterSettle), "AFTER_SETTLE_HOOKS_FAILED");
        emit Settlement(order.nonce);
    }
}