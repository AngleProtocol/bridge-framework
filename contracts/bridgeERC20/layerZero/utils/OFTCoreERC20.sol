// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "./NonblockingLzAppERC20.sol";
import "../../../interfaces/external/layerZero/IOFTCore.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

/// @title OFTCoreERC20
/// @author Forked from https://github.com/LayerZero-Labs/solidity-examples/blob/main/contracts/token/oft/OFTCore.sol
/// but with slight modifications to add return values to the `_creditTo` and `_debitFrom` functions
/// @notice Base contract for bridging using LayerZero
abstract contract OFTCoreERC20 is NonblockingLzAppERC20, ERC165Upgradeable, IOFTCore {
    /// @notice Amount of additional gas specified
    uint256 public constant NO_EXTRA_GAS = 0;
    /// @notice Packet type for token transfer
    uint16 public constant PT_SEND = 0;

    /// @notice Whether custom adapter parameters should be used or not
    bool public useCustomAdapterParams;

    // ===================== EXTERNAL PERMISSIONLESS FUNCTIONS =====================

    /// @inheritdoc IOFTCore
    function sendWithPermit(
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable virtual;

    /// @inheritdoc IOFTCore
    function sendFrom(
        address _from,
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) public payable virtual {
        _checkAdapterParams(_dstChainId, PT_SEND, _adapterParams, NO_EXTRA_GAS);
        _amount = _debitFrom(_dstChainId, _toAddress, _amount);
        _send(_from, _dstChainId, _toAddress, _amount, _refundAddress, _zroPaymentAddress, _adapterParams);
    }

    /// @inheritdoc IOFTCore
    function send(
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) public payable virtual {
        sendFrom(msg.sender, _dstChainId, _toAddress, _amount, _refundAddress, _zroPaymentAddress, _adapterParams);
    }

    /// @inheritdoc IOFTCore
    function sendCredit(
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) public payable virtual {
        _checkAdapterParams(_dstChainId, PT_SEND, _adapterParams, NO_EXTRA_GAS);
        _amount = _debitCreditFrom(_dstChainId, _toAddress, _amount);
        _send(msg.sender, _dstChainId, _toAddress, _amount, _refundAddress, _zroPaymentAddress, _adapterParams);
    }

    /// @inheritdoc IOFTCore
    function withdraw(uint256 amount, address recipient) external virtual returns (uint256);

    // ============================ GOVERNANCE FUNCTION ============================

    /// @notice Toggles the value of the `useCustomAdapterParams`
    function toggleUseCustomAdapterParams() public virtual onlyGovernorOrGuardian {
        useCustomAdapterParams = !useCustomAdapterParams;
    }

    // ============================= INTERNAL FUNCTIONS ============================

    /// @notice Internal function to send `_amount` amount of token to (`_dstChainId`, `_toAddress`)
    /// @param _dstChainId the destination chain identifier
    /// @param _toAddress can be any size depending on the `dstChainId`.
    /// @param _amount the quantity of tokens in wei
    /// @param _refundAddress the address LayerZero refunds if too much message fee is sent
    /// @param _zroPaymentAddress set to address(0x0) if not paying in ZRO (LayerZero Token)
    /// @param _adapterParams is a flexible bytes array to indicate messaging adapter services
    /// @dev Accounting and checks should be performed beforehand
    function _send(
        address _from,
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) internal {
        bytes memory payload = abi.encode(PT_SEND, _toAddress, _amount);
        _lzSend(_dstChainId, payload, _refundAddress, _zroPaymentAddress, _adapterParams, msg.value);
        emit SendToChain(_dstChainId, _from, _toAddress, _amount);
    }

    /// @inheritdoc NonblockingLzAppERC20
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal virtual override {
        // decode and load the toAddress
        (uint16 packetType, bytes memory toAddressBytes, uint256 amount) = abi.decode(
            _payload,
            (uint16, bytes, uint256)
        );
        if (packetType != PT_SEND) revert InvalidParams();
        address to;
        //solhint-disable-next-line
        assembly {
            to := mload(add(toAddressBytes, 20))
        }
        amount = _creditTo(_srcChainId, to, amount);

        emit ReceiveFromChain(_srcChainId, to, amount);
    }

    /// @notice Checks the adapter parameters given during the smart contract call
    function _checkAdapterParams(
        uint16 _dstChainId,
        uint16 _pkType,
        bytes memory _adapterParams,
        uint256 _extraGas
    ) internal virtual {
        if (useCustomAdapterParams) _checkGasLimit(_dstChainId, _pkType, _adapterParams, _extraGas);
        else if (_adapterParams.length != 0) revert InvalidParams();
    }

    /// @notice Makes accountability when bridging from this contract using canonical token
    /// @param _dstChainId ChainId of the destination chain - LayerZero standard
    /// @param _toAddress Recipient on the destination chain
    /// @param _amount Amount to bridge
    function _debitFrom(
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _amount
    ) internal virtual returns (uint256);

    /// @notice Makes accountability when bridging from this contract's credit
    /// @param _dstChainId ChainId of the destination chain - LayerZero standard
    /// @param _toAddress Recipient on the destination chain
    /// @param _amount Amount to bridge
    function _debitCreditFrom(
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _amount
    ) internal virtual returns (uint256);

    /// @notice Makes accountability when bridging to this contract
    /// @param _srcChainId ChainId of the source chain - LayerZero standard
    /// @param _toAddress Recipient on this chain
    /// @param _amount Amount to bridge
    function _creditTo(
        uint16 _srcChainId,
        address _toAddress,
        uint256 _amount
    ) internal virtual returns (uint256);

    // =============================== VIEW FUNCTIONS ==============================

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IOFTCore).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IOFTCore
    function estimateSendFee(
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint256 _amount,
        bool _useZro,
        bytes memory _adapterParams
    ) public view virtual override returns (uint256 nativeFee, uint256 zroFee) {
        // mock the payload for send()
        bytes memory payload = abi.encode(PT_SEND, _toAddress, _amount);
        return lzEndpoint.estimateFees(_dstChainId, address(this), payload, _useZro, _adapterParams);
    }

    uint256[49] private __gap;
}
