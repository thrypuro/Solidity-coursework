// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Dice {
    // players and owner info
    address owner;
    address [2] public players;
    
    // 10 minutes in Unix eppoch 
    uint256 DECAY = 300000 * 2;

    // When both players have entered the game, this will be set to True
    bool game_started = false;

    // Takes the lucky numbers of the Users to calculate the seed, player_A_value ^ player_B_value ^ latest_block_hash
    uint256 random_value = 0;

    /*
        Stores information of each Players current and older
        solutionHash : Hash committed by the player
        commitTime : Timestamp when the block for the transaction was mined
        deposit : How much the player has deposited to play the game
        revealed : has the Player revealed the secret to get their hash?

    */
    struct Player {
        bytes32 solutionHash;
        uint commitTime;
        uint256 deposit;
        bool revealed;
    }

    // This maps the address of the player to their corresponding structs
    mapping(address => Player) public comm;

    // prng constants   https://en.wikipedia.org/wiki/Permuted_congruential_generator
    uint64 state = 0x4d595df4d0f33173;
    uint64 multiplier = 6364136223846793005;
    uint64 increment = 1442695040888963407;
    
    // events
    event Player_entered(address ad);
    event Player_winner(address ad);

    // Ensures that the contract know who the owner is once the contract is created
    constructor() {
        owner = msg.sender;
    }

    // ----------------- Game Functions -----------------------

    // Order in which the Player must player
    // enter_game -> reveal -> start_game 

    /*
     This is how players first enter the game, they have to deposit 4 ether to play, (3 to play and 1 for any gas prices incurred)
    
     User has to input a hash to play the game
   */
    function enter_game(bytes32 userhash) public payable {
        require(msg.value >= 4 ether, "Need 4 ether to play the game");
        require(!game_started,"A game is already in session");
        require(comm[msg.sender].commitTime == 0, "You have already Commited");

        // Add players to the array, if player A has joined, we add Player B to array
        if (players[0]==address(0)){
        players[0] = msg.sender;
        }
        else { 
            players[1] = msg.sender;
            game_started = true;
            
            }
        // Set the struct of the player
        comm[msg.sender].commitTime = block.timestamp;
        comm[msg.sender].solutionHash = userhash;
        comm[msg.sender].revealed = false;
        comm[msg.sender].deposit += msg.value; // if player has previously player we dont want to overwrite if they havent deposited!
        emit Player_entered(msg.sender);

    }
    
    
    /**
        Reveal phase of Commitment Scheme 
        Ask for a  Secret nonce and a secret number, this is now hashed and compared to the preprocessed hash
        H( address | _secret  | _secret_number)
        where, H() is the sha256 function
        Security : This is the same as bruteforcing a 64 byte secret, which takes more than the age of the universe to compute

    **/
    function reveal(bytes32 _secret,uint256 _secret_number) public onlyPlayers_and_game_start {
        // make sure someone can't reveal again
        require(!comm[msg.sender].revealed, "You have already revealed your answer");
        // encode the input before hashing it
        bytes32 solutionHash = sha256(abi.encode(msg.sender,_secret,_secret_number));
        // Important step to make sure the hashes match
        require(solutionHash==comm[msg.sender].solutionHash,"Hashes do not match! Try again!");
        // Once revealed, part of the seed is constructed
        comm[msg.sender].revealed = true;
        random_value ^= _secret_number;
        }
        
    
    /**
      Game start, steps innolve
      1) Generate the seed and get random number
      2) Get the winner and loser through the index
      3) Calculate the money won or lost
      4) Recalculate the balances
      5) Reset the game to be played again
    **/
    function start_game() public onlyPlayers_and_game_start {
        // Make sure both players have revealed their commitment
        require(comm[players[0]].revealed && comm[players[1]].revealed, "One of the players have not revealed!");
        
        // We use the latest blockhash as an additional value for the seed, 
        uint256 blockHashNow = uint256(blockhash(block.number-1));
        uint64 seed = uint64( (random_value^blockHashNow));
        // Use our PRNG to generate a number from (1 - 6)
        uint8 lucky_number =  random(seed);
        uint8 index = (lucky_number-1)/3; // ranges from 0 - 5, 0-2 returns 0, 3-5 returns 1 as there is no floating point
        
        // Get the winner and loser addresses 
        address winner = players[index];
        address loser =  players[(index+1)%players.length];

        // Calculate ether that will be won or lost
        uint256 money_won_or_lost = ((lucky_number-1)%3 + 1)* ( 1 ether);
        comm[winner].deposit += money_won_or_lost;
        comm[winner].deposit -= 70 * 10000 gwei; // charge the player for gas
        comm[loser].deposit -= money_won_or_lost;
        comm[loser].deposit -= 70 * 10000 gwei; // charge player for gas
        
        // the caller of this functions get the gas + small reward
        comm[msg.sender].deposit += 140 * 10000 gwei;

        // restart and log winner
        restart();
        emit Player_winner(winner);
    }
    
    /*
    ----------- Other functions ----------
        Withdrawing money after a game
        Backing out if you don't wish to play
        Timeout if the other player 

    */

    /*
    Withdraw your funds from the contract
    Safe way to withdraw funds avoiding Reintrancy bugs
    */
    function Withdraw() public {
        require(players[0] != msg.sender || players[1] != msg.sender, "Cannot withdraw if you are one of the player, back out first!");

        uint256 b = comm[msg.sender].deposit;
        comm[msg.sender].deposit = 0;
        payable(msg.sender).transfer(b);
    }

    // if the first player wants to back out and no longer wants to play the game
    function player_A_back_out() public{
        require(!game_started, "Both player's have enter the game, cannot backout unless there is a timedout");
        require(players[0]== msg.sender);
        reset(msg.sender);
        players[0] = address(0);
    }

    /*
     Request a Timeout if the game isn't over even after 10 minutes have passed 
    */
    function request_timeout() public onlyPlayers_and_game_start {
        require(comm[msg.sender].commitTime + DECAY  < block.timestamp );
        restart();
    }
    /*
    If both players are stalling and the game can't move on, the owner can intervene and restart the game
    Potentially have it open to everyone on the chain, but I am unsure how to prevent it from DDosing the contract
    */
    function owner_timeout() public onlyOwner{
        restart();
    }

    // helper function to restart the game
    function restart() private {
        reset(players[0]);
        reset(players[1]);
        players[0] = address(0);
        players[1] = address(0);
        game_started = false;
        random_value = 0;
    }

    // helper function to reset the Player info struct except their deposit
    function reset(address a) private{
        comm[a].solutionHash = bytes32(0);
        comm[a].commitTime = 0;
        comm[a].revealed = false;
    }

    // ----------------- Psuedo Random Number generator ----------------------- 

    // prng info : https://en.wikipedia.org/wiki/Permuted_congruential_generator

    // Bitwise circular rotation of a 32 bit number
    function rotr32(uint32 x, uint8 r) private pure returns(uint32) {
        uint32 y =  uint32((x << ((32-r) & 31)));
        return x >> r | y;
    }

    // Main part of the PCG
    function pcg64() private returns(uint32) {
        uint64 x = state;
        uint8 count = uint8(state>>59);
        // due to the nature of multiplication we need to do this to ensure there is no revertion
        state = uint64(uint(x) * uint(multiplier) + uint(increment));
        x ^= x>>18;
        return rotr32(uint32(x>>27),count);
    }

    function random(uint64 seed) public  returns(uint8)  {
        state = seed+increment;
        /* 
        This is a common technique in prngs to ensure unpredictable randomness 
        */
        for(uint16 i=0; i<2; i++){
        pcg64();
        }
        return uint8 (pcg64()%6 + 1);
    }
    // ----------------------- Getters ----------------------------


    function getPlayer() public view returns(string memory){
        require(players[0] == msg.sender || players[1] == msg.sender, "You are not playing the game");
        if (players[0]==msg.sender){
            return "Hello, Player A!";
        }
        else {
            return "Hello, Player B!";
        }
    }
    
    

    // ----------------------- Modifiers ----------------------------

    modifier onlyOwner {
    require(msg.sender == owner);
    _;
    }
    modifier onlyPlayers_and_game_start {
    require(msg.sender == players[0] || msg.sender == players[1]);
    require(game_started);
    _;
    }

}