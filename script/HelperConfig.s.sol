// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "src/raffle.sol"; 
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants {

    /** Mock Contract Values */
    uint96 public constant MOCK_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_GAS_PRICE = 1e9;
    int256 public constant MOCK_WEI_PER_UNIT_LINK = 4e15;

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is Script, CodeConstants {

    error HelperConfig__InvalidChainId(uint256 chainId);

    constructor() {
    networkConfigs[SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfigByChainId (uint256 chainId) public returns (NetworkConfig memory){
        if (networkConfigs[chainId].vrfCoordinator != address(0)){
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID){
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId(chainId);
        }
    }
    
    
    function getConfig() external returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    struct NetworkConfig {
        uint256 entranceFee;
        uint interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint32 callbackGasLimit;
        uint256 subscriptionId;
        address link;
        address account;
    }

    NetworkConfig public localNetworkConfig;
    mapping (uint256 chainId => NetworkConfig) networkConfigs;

    function getSepoliaEthConfig() public pure returns(NetworkConfig memory){
        return NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30, // 30 SECS
            vrfCoordinator: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, // keyHash
            callbackGasLimit: 500000,
            subscriptionId: 0,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            account: 0xb9545338653C85E2fc54699a59d312c1381B7643
        });
    }

    function getOrCreateAnvilEthConfig() public returns(NetworkConfig memory){
        // check to see if an active network config is set
        if (localNetworkConfig.vrfCoordinator != address(0)){
            return localNetworkConfig;
        }
        // deploy mocks
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorMock = new VRFCoordinatorV2_5Mock(MOCK_BASE_FEE, MOCK_GAS_PRICE, MOCK_WEI_PER_UNIT_LINK);
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();
        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30, // 30 SECS
            vrfCoordinator: address(vrfCoordinatorMock),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, // doesn't matter
            callbackGasLimit: 500000,
            subscriptionId: 0, // change later
            link: address(linkToken),
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        });
        return localNetworkConfig;

    }
}