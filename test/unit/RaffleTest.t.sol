// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Raffle} from "src/raffle.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";


contract RaffleTest is Test, CodeConstants {

    Raffle public raffle;
    HelperConfig public helperConfig;
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;
    uint256 entranceFee;
    uint interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    event enteredRaffle(address indexed player);
    event winnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator; // Now this will work
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }
    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.raffleState.OPEN);
    }
    modifier skipFork {
        if(block.chainid != LOCAL_CHAIN_ID){
            return;
        }
        _;
    }
    function testRaffleRevertsWhenYouDontPayEnough() public {
        // Arrange
        vm.prank(PLAYER);
        // Assert / Act
        vm.expectRevert(Raffle.Raffle__Not_Enough_Funds.selector);
        raffle.enterRaffle();
    }
    function testRaffleRecordsPlayersWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: entranceFee}();
        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }
    function testEnteringRaffleEmitsEvent() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit enteredRaffle(PLAYER);
        // Assert
        raffle.enterRaffle{value: entranceFee}();
    }
    function testDontAllowPlayersToEnterWhenRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        // Act
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__Raffle_Not_Open.selector);
        raffle.enterRaffle{value: entranceFee}();
        // Assert
    }
    function testCheckUpkeepReturnsFalseIfItHasNoBalanece() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }
    function testCheckUpkeepReturnsFalseIfRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }
    function testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }
    function testUpkeepReturnsTrueWhenParametersAreGood () public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act / Assert
        raffle.checkUpkeep("");
    }
    function testUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 upkeepBalance = 0;
        uint256 numPlayers = 0;
        Raffle.raffleState rState = raffle.getRaffleState();
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        upkeepBalance += entranceFee;
        numPlayers += 1;

        // Act / Assert
        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle__upkeepNotNeeded.selector, upkeepBalance, numPlayers, rState));
        raffle.performUpkeep("");
    }
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequest() public {
        //  Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        
        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Raffle.raffleState raffleState = raffle.getRaffleState();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // Assert
        assert(uint(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 requestId) public skipFork {
        // Arrange / Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(requestId, address(raffle));
    }
    modifier raffleEnteredAndTimeHasPassed {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }
    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEnteredAndTimeHasPassed skipFork  {
        // Arrange
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);
        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++){
            address newPlayer = address(uint160(i));
            hoax(newPlayer, STARTING_PLAYER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimeStamp = raffle.getlastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.raffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getlastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);
        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(endingTimeStamp > startingTimeStamp);
        assert(winnerBalance >= winnerStartingBalance + prize);


    }
    
}