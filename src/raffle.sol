// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title A sample raffle contract
 * @author Muazu Fadhilullahi
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRF v2.5
 */
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract Raffle is VRFConsumerBaseV2Plus {
    error Raffle__Not_Enough_Funds();
    error Raffle__TransferFailed();
    error Raffle__Raffle_Not_Open();
    error Raffle__upkeepNotNeeded(uint256 balance, uint256 numOfPlayers, uint256 raffleState);

    enum raffleState {
        OPEN,
        DETERMINING_WINNER
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    // @dev The duration of the lottery in sec
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callBackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimStamp;
    address private s_recentWinner;
    raffleState private s_raffleState;

    event enteredRaffle(address indexed player);
    event winnerPicked(address indexed winner);
    event requestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callBackGasLimit = callBackGasLimit;

        s_lastTimStamp = block.timestamp;
        s_raffleState = raffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__Not_Enough_Funds();
        }
        if (s_raffleState != raffleState.OPEN) {
            revert Raffle__Raffle_Not_Open();
        }
        s_players.push(payable(msg.sender));
        emit enteredRaffle(msg.sender);
    }

    // When should the winner be picked
    /**
     * @dev This is the function that the Chainlink nodes will call to see if the lottery is ready to have a winner picked.
     * The following should be true in order for upKeepNeeded to be true:
     * 1. The time interval has passed between raffle draws
     * 2. The lottery is open
     * 3. The contract has ETH
     * 4. Implicitly, your subscription has LINK
     * @param - ignored
     * @return upKeepNeeded - true if it's time to start the lottery
     * @return - ignored
     */
    function checkUpkeep(bytes memory)
        /**
         * checkData
         */
        public
        view
        returns (bool upKeepNeeded, bytes memory)
    /**
     * performData
     */
    {
        bool timeHasPassed = (block.timestamp - s_lastTimStamp) > i_interval;
        bool isOpen = s_raffleState == raffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upKeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upKeepNeeded, "0x0"); // 0x0 stands for null
    }

    // Be automatically called when checkUpkeep conditions are met and requests random number
    function performUpkeep(bytes calldata)
        /**
         * perform data
         */
        external
    {
        // check if enough time has passed
        (bool upKeepNeeded, ) = checkUpkeep("");
        if (!upKeepNeeded) {
            revert Raffle__upkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        s_raffleState = raffleState.DETERMINING_WINNER;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash, // max gas price, passed in constructor, bytes32
            subId: i_subscriptionId, // subscription id, passed in contructor, uint 256
            requestConfirmations: REQUEST_CONFIRMATIONS, // number of confirmations before getting result, uint 16
            callbackGasLimit: i_callBackGasLimit, // gas limit,  passed in constructor, uint32
            numWords: NUM_WORDS, // number of random numbers wanted, uint32, constant
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit requestedRaffleWinner(requestId);
    }

    // gets the random number from the request made
    function fulfillRandomWords(uint256, /* requestId */ uint256[] calldata randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_players = new address payable[](0);
        s_lastTimStamp = block.timestamp;
        s_raffleState = raffleState.OPEN;
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit winnerPicked(s_recentWinner);
    }

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
    function getRaffleState() external view returns (raffleState){
        return s_raffleState;
    }
    function getPlayer (uint256 indexOfPlayer) external view returns (address){
        return s_players[indexOfPlayer];
    }
    function getlastTimeStamp() external view returns (uint256){
        return s_lastTimStamp;
    }
    function getRecentWinner() external view returns (address){
        return s_recentWinner;
    }
}
