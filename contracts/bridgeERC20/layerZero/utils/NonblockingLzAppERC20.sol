// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../../../interfaces/external/layerZero/ILayerZeroReceiver.sol";
import "../../../interfaces/external/layerZero/ILayerZeroUserApplicationConfig.sol";
import "../../../interfaces/external/layerZero/ILayerZeroEndpoint.sol";
import "../../../interfaces/ICoreBorrow.sol";
import "../../../external/ExcessivelySafeCall.sol";

/// @title NonblockingLzAppERC20
/// @author Angle Labs, Inc., forked from https://github.com/LayerZero-Labs/solidity-examples/
/// @notice Base contract for bridging an ERC20 token using LayerZero
abstract contract NonblockingLzAppERC20 is Initializable, ILayerZeroReceiver, ILayerZeroUserApplicationConfig {
    using ExcessivelySafeCall for address;

    /// @notice Layer Zero endpoint
    ILayerZeroEndpoint public lzEndpoint;

    /// @notice Maps chainIds to failed messages to retry them
    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;

    /// @notice Maps chainIds to their OFT address
    mapping(uint16 => bytes) public trustedRemoteLookup;

    /// @notice Reference to the `CoreBorrow` contract to fetch access control
    address public coreBorrow;

    // =================================== EVENTS ==================================

    event SetTrustedRemote(uint16 _srcChainId, bytes _srcAddress);
    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload, bytes reason);

    // =================================== ERRORS ==================================

    error NotGovernor();
    error NotGovernorOrGuardian();
    error InvalidEndpoint();
    error InvalidSource();
    error InvalidCaller();
    error InvalidPayload();
    error ZeroAddress();

    // ================================ CONSTRUCTOR ================================

    //solhint-disable-next-line
    function __LzAppUpgradeable_init(address _endpoint, address _coreBorrow) internal {
        if (_endpoint == address(0) || _coreBorrow == address(0)) revert ZeroAddress();
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
        coreBorrow = _coreBorrow;
    }

    // ================================= MODIFIERS =================================

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernorOrGuardian() {
        if (!ICoreBorrow(coreBorrow).isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    // ===================== EXTERNAL PERMISSIONLESS FUNCTIONS =====================

    /// @notice Receives a message from the LZ endpoint and process it
    /// @param _srcChainId ChainId of the source chain - LayerZero standard
    /// @param _srcAddress Sender of the source chain
    /// @param _nonce Nounce of the message
    /// @param _payload Data: recipient address and amount
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) public virtual override {
        // lzReceive must be called by the endpoint for security
        if (msg.sender != address(lzEndpoint)) revert InvalidEndpoint();

        bytes memory trustedRemote = trustedRemoteLookup[_srcChainId];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from untrusted remote.
        if (_srcAddress.length != trustedRemote.length || keccak256(_srcAddress) != keccak256(trustedRemote))
            revert InvalidSource();

        _blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    /// @notice Retries a message that previously failed and was stored
    /// @param _srcChainId ChainId of the source chain - LayerZero standard
    /// @param _srcAddress Sender of the source chain
    /// @param _nonce Nounce of the message
    /// @param _payload Data: recipient address and amount
    function retryMessage(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) public payable virtual {
        // assert there is message to retry
        bytes32 payloadHash = failedMessages[_srcChainId][_srcAddress][_nonce];
        if (payloadHash == bytes32(0) || keccak256(_payload) != payloadHash) revert InvalidPayload();
        // clear the stored message
        failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);
        // execute the message. revert if it fails again
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    // ============================= INTERNAL FUNCTIONS ============================

    /// @notice Handles message receptions in a non blocking way
    /// @param _srcChainId ChainId of the source chain - LayerZero standard
    /// @param _srcAddress Sender of the source chain
    /// @param _nonce Nounce of the message
    /// @param _payload Data: recipient address and amount
    /// @dev public for the needs of try / catch but effectively internal
    function nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) public virtual {
        // only internal transaction
        if (msg.sender != address(this)) revert InvalidCaller();
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    /// @notice Handles message receptions in a non blocking way
    /// @param _srcChainId ChainId of the source chain - LayerZero standard
    /// @param _srcAddress Sender of the source chain
    /// @param _nonce Nounce of the message
    /// @param _payload Data: recipient address and amount
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual;

    /// @notice Handles message receptions in a blocking way
    /// @param _srcChainId ChainId of the source chain - LayerZero standard
    /// @param _srcAddress Sender of the source chain
    /// @param _nonce Nounce of the message
    /// @param _payload Data: recipient address and amount
    function _blockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal {
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(this.nonblockingLzReceive.selector, _srcChainId, _srcAddress, _nonce, _payload)
        );
        if (!success) {
            failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(_payload);
            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, reason);
        }
    }

    /// @notice Sends a message to the LZ endpoint and process it
    /// @param _dstChainId L0 defined chain id to send tokens too
    /// @param _payload Data: recipient address and amount
    /// @param _refundAddress Address LayerZero refunds if too much message fee is sent
    /// @param _zroPaymentAddress Set to address(0x0) if not paying in ZRO (LayerZero Token)
    /// @param _adapterParams Flexible bytes array to indicate messaging adapter services in L0
    function _lzSend(
        uint16 _dstChainId,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) internal virtual {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];
        if (trustedRemote.length == 0) revert InvalidSource();
        //solhint-disable-next-line
        lzEndpoint.send{ value: msg.value }(
            _dstChainId,
            trustedRemote,
            _payload,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    // ============================ GOVERNANCE FUNCTIONS ===========================

    /// @notice Sets the corresponding address on an other chain.
    /// @param _srcChainId ChainId of the source chain - LayerZero standard
    /// @param _srcAddress Address on the source chain
    /// @dev Used for both receiving and sending message
    /// @dev There can only be one trusted source per chain
    /// @dev Allows owner to set it multiple times.
    function setTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external onlyGovernorOrGuardian {
        trustedRemoteLookup[_srcChainId] = _srcAddress;
        emit SetTrustedRemote(_srcChainId, _srcAddress);
    }

    /// @notice Fetches the default LZ config
    function getConfig(
        uint16 _version,
        uint16 _chainId,
        address,
        uint256 _configType
    ) external view returns (bytes memory) {
        return lzEndpoint.getConfig(_version, _chainId, address(this), _configType);
    }

    /// @notice Overrides the default LZ config
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint256 _configType,
        bytes calldata _config
    ) external override onlyGovernorOrGuardian {
        lzEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    /// @notice Overrides the default LZ config
    function setSendVersion(uint16 _version) external override onlyGovernorOrGuardian {
        lzEndpoint.setSendVersion(_version);
    }

    /// @notice Overrides the default LZ config
    function setReceiveVersion(uint16 _version) external override onlyGovernorOrGuardian {
        lzEndpoint.setReceiveVersion(_version);
    }

    /// @notice Unpauses the receive functionalities
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress)
        external
        override
        onlyGovernorOrGuardian
    {
        lzEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    // =============================== VIEW FUNCTIONS ==============================

    /// @notice Checks if the `_srcAddress` corresponds to the trusted source
    function isTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool) {
        bytes memory trustedSource = trustedRemoteLookup[_srcChainId];
        return keccak256(trustedSource) == keccak256(_srcAddress);
    }

    uint256[46] private __gap;
}
