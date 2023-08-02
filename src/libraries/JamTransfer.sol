// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

library JamTransfer {

    struct Initial {
        address balanceRecipient;
    }

    struct Indices {
        uint256 permit2BatchInd;
        uint256 curNFTsInd;
    }
}