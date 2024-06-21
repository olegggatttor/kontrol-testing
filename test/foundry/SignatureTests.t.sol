// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../../src/libraries/Signature.sol";
import "./utils/MakerWallet.sol";
import "../../src/JamSettlement.sol";
import "./utils/Utils.sol";

import {KontrolCheats} from "kontrol-cheatcodes/KontrolCheats.sol";

contract SignatureTests is Test, Utils, KontrolCheats {

    address internal maker;
    JamSettlement internal jam;

    function setUp() public {
        vm.chainId(1);

        maker = address(new EIP1271Wallet());
        jam = new JamSettlement(PERMIT2, DAI_ADDRESS);
    }

    function _notBuiltinAddress(address addr) internal view {
        vm.assume(addr != address(this));
        vm.assume(addr != address(vm));
        vm.assume(addr != address(jam));
        vm.assume(addr != address(maker));
        vm.assume(addr > address(9));
    }

    function testValidEIP712Signature(bytes calldata toHash) public {
        (address signer, uint256 signingKey) = makeAddrAndKey("someSigner");

        bytes32 message = keccak256(toHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, message);
        bytes memory rsv_sig = abi.encodePacked(r, s, v);
        Signature.TypedSignature memory sig = Signature.TypedSignature(Signature.Type.EIP712, rsv_sig);

        jam.validateSignature(signer, message, sig);
    }

    function testValidETHSIGHSignature() public {
        (address signer, uint256 signingKey) = makeAddrAndKey("someSigner");

        bytes32 message = keccak256("Order Hash");
        bytes32 eth_sign_message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, eth_sign_message);
        bytes memory rsv_sig = abi.encodePacked(r,s,v);
        Signature.TypedSignature memory sig = Signature.TypedSignature(Signature.Type.ETHSIGN, rsv_sig);

        jam.validateSignature(signer, message, sig);
    }

    function testValidEIP1271Signature() public {
        (address signer, uint256 signingKey) = makeAddrAndKey("someSigner");
        IEIP1271Wallet(maker).addSigner(signer);

        bytes32 message = keccak256("Order Hash");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, message);
        bytes memory rsv_sig = abi.encodePacked(r, s, v);
        Signature.TypedSignature memory sig = Signature.TypedSignature(Signature.Type.EIP1271, rsv_sig);

        jam.validateSignature(maker, message, sig);
    }

    function testEIP712InvalidSignature() public {
        (address signer, uint256 signingKey) = makeAddrAndKey("someSigner");

        bytes32 message = keccak256("Order Hash");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, message);
        bytes memory rsv_sig = abi.encodePacked(r, s, v);
        Signature.TypedSignature memory sig = Signature.TypedSignature(Signature.Type.EIP712, rsv_sig);

        vm.expectRevert("Invalid EIP712 order signature");
        jam.validateSignature(makeAddr("anotherSigner"), message, sig);
    }

}
