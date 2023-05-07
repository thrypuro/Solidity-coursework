// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./customLib.sol";

contract Token {
    using customLib for uint256;
    using customLib for address;

    // The address of the contract owner
    address internal owner; 
    // The total token supply
    uint256 internal total_Supply;
    // The token name
    string internal name;
    // The token symbol
    string internal symbol;
    // The token price in wei
    uint128 internal token_price;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed to, uint256 value);
    event Sell(address indexed from, uint256 value);


    // mapping that maps addresses to balances
    mapping(address => uint256) public balances;

    // Constructor function that sets the owner, name, symbol, and token price
    // of the token contract.
    constructor( string memory _name, string memory _symbol) {
        owner = msg.sender;
        name = _name; 
        symbol = _symbol;
        total_Supply = 0;
        token_price = 600;
    }

    // return the total supply of the token
    function totalSupply() public view returns (uint256) {
        return total_Supply;
    }

    // function that returns balances of an address
    function balanceOf(address _account) public view returns (uint256) {
        return balances[_account];
    }

    // a view function that returns a string with the token’s name
    function getName() public view returns (string memory) {
        return name;
    }
    // a view function that returns a string with the token’s symbol
    function getSymbol() public view returns (string memory) {
        return symbol;
    }

    // a view function that returns the token’s price in wei
    function getPrice() public view returns (uint128) {
        return token_price;
    }
    

    
    // a function that transfers tokens from the sender to another address
    function transfer(address to, uint256 value) public returns (bool) {
        require(to != address(0), "Invalid address to transfer to");

        // value cannot be zero
        require(value != 0, "Cannot transfer zero tokens");
        require(balanceOf(msg.sender) >= value, "Not enough balance to transfer");
        balances[msg.sender] -= value;
        balances[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

  
    // a function that enables only the owner to mint tokens to specified address 
    function mint(address to, uint256 value) public onlyOwner returns (bool) {
        require(to != address(0), "Invalid address to mint to");
        // make sure balance is not overflowing
        require (balanceOf(to) + value >= balanceOf(to), "Overflow");
        // value cannot be zero
        require(value != 0, "Cannot mint zero tokens");
        balances[to] += value;

        total_Supply += value;

        emit Mint(to, value);
        return true;
    }

    // a function that enables the token owners to sell their tokens 
    function sell(uint256 value) public payable returns (bool) {
        // value cannot be zero
        require(value != 0, "Cannot sell zero tokens");
        require(balanceOf(msg.sender) >= value, "Not enough balance to sell");

        // amount = token_price * value 
        uint256 amount = token_price * value;

        // make sure the contract has enough balance to pay the seller
        require(address(this).balance >= amount, "Not enough balance to pay the seller");

        // reduce the balance of the seller
        balances[msg.sender] -= value;

        // reduce the total supply
        total_Supply -= value;
        // transfer from the contract to the sender
        bool success = amount.customSend(msg.sender);
        emit Sell(msg.sender, value);
        return success;

    }

    // close() a function that enables only the owner to destroy the contract; the contract’s balance in wei, at the moment of destruction, should be transferred to the owner address 
    function close() public onlyOwner {
        selfdestruct(payable(owner));
    }


    // fallback function to let the contract receive ether
    fallback() external payable {
        // 

    }

    // receive function to let the contract receive ether
    receive() external payable {
        // 
    }

    



   // ----------------------- Modifiers ----------------------------

    modifier onlyOwner {
    require(msg.sender == owner);
    _;
    }
  


}