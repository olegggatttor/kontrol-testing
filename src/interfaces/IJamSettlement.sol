// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../libraries/JamInteraction.sol";
import "../libraries/JamOrder.sol";
import "../libraries/JamHooks.sol";
import "../libraries/Signature.sol";

interface IJamSettlement {
    /// @dev Settle a jam order.
    /// Pulls sell tokens into the contract and ensures that after running interactions the minimum of buy
    /// tokens can be sent to the receiver.
    /// @param order user signed order
    /// @param interactions list of interactions to settle the order
    /// @param hooks pre and post interactions
    /// @param balanceRecipient address to receive the initial user's tokens (usually it's solver's contract address)

    function settle(
        JamOrder.Data calldata order,
        Signature.TypedSignature calldata signature,
        JamInteraction.Data[] calldata interactions,
        JamHooks.Def calldata hooks,
        address balanceRecipient
    ) external;
}