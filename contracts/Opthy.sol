// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";


contract DoublyLinkedNode {
    address private _parent;
    address private _child;
    
    constructor(address parent, address child){
        if (parent != address(0x0)) {
            _parent = parent;
        } else {
            _parent = address(this);
        }

        if (child != address(0x0)) {
            _child = child;
        } else {
            _child = address(this);
        }
    }

    function addChild(address newChild) internal {
        DoublyLinkedNode(_child).changeParent(newChild);
        _child=newChild;
    }

    function changeParent(address parent) public {
        require(msg.sender == _parent,"Only the parent can ask to be changed");
        _parent=parent;
    }

    function delist() internal {
        DoublyLinkedNode(_parent).removeChild();
        DoublyLinkedNode(_child).changeParent(_parent);
        _parent = address(this);
        _child = address(this);        
    }

    function removeChild() public {
        require(msg.sender == _child,"Only the child can ask to be removed");
        _child=DoublyLinkedNode(_child).Child();
    }
    
    function Parent() public view returns(address) {
        return _parent;
    }
    
    function Child() public view returns(address) {
        return _child;
    }
}

//Opthys is a registry of the opthys, it's also the guard of the Circular Doubly Linked List
contract Opthys is DoublyLinkedNode(address(0x0),address(0x0)) {
    using SafeERC20 for IERC20;


    event NewOpthy(address indexed opthy, address indexed creator);
    function newOpthy(bool ISell_, uint32 duration_, IERC20 token0_, IERC20 token1_, uint128 r0_, uint128 r1_, uint128 amount0_) public returns(address) {
        require(amount0_ > 0, "Amount0 must be a non zero quantity");
        
        address holder;
        address seller;
        if (ISell_) {
            // holder = address(0x0);
            seller = msg.sender;
        } else {
            holder = msg.sender;
            // seller = address(0x0);
        }

        Opthy o = new Opthy(duration_, holder, seller,  token0_, token1_, r0_, r1_, address(this), Child());
        addChild(address(o));
        
        token0_.safeTransferFrom(msg.sender, address(o), amount0_);
        (uint256 b0, uint256 b1) = o.balance();
        require(b0 != b1, "Tokens must be two distinct ERC20 tokens");
    
        emit NewOpthy(address(o), msg.sender);
        
        return address(o);
    }

    struct opthy { 
        address opthy;
        
        uint32 phase;
        uint32 duration;
        
        address holder;
        address seller;
        uint256 expiration;
        
        IERC20  token0;
        IERC20  token1;
        
        uint256 balance0;
        uint256 balance1;

        uint128 r0;
        uint128 r1;
    }
    
    //Covert the Doubly Linked List representation to an array
    function getOpthys() public view returns(opthy[] memory){
        uint256 length = 0;
        for (address c=this.Child(); c != address(this); c=DoublyLinkedNode(c).Child()) {
            length++;
        }
        
        uint256 i = 0;
        opthy[] memory ll = new opthy[](length);
        for (address c=this.Child(); c != address(this); c=DoublyLinkedNode(c).Child()) {
            Opthy o = Opthy(c);
            (uint256 balance0, uint256 balance1) = o.balance();
            ll[i] = opthy(c,o.phase(),o.duration(),o.holder(),o.seller(),o.expiration(),o.token0(),o.token1(),balance0,balance1,o.r0(),o.r1());
            i++;
        }
    
        return ll;
    }
}

//TODO: block.timestamp for the scope of the hackathon can be trusted, in production would be unsafe to trust (and other solutions may appear as well)
contract Opthy is DoublyLinkedNode {
    using SafeERC20 for IERC20;
    
    //All fields are constant after agreement
    
    //phase during hagglig it's a positive serial number, after agreement becomes constant zero
    uint32 public phase;
    //duration is the quantity of seconds the opthy contract is alive after agreement
    uint32 public duration;
    
    //holder contains the zero address while still haggling on opthy details, if proposed by the seller
    address public holder;
    //seller contains the zero address while still haggling on opthy details, if proposed by the holder
    address public seller;
    //expiration during haggling is the creation-timestamp/last-modified-timestamp, while in opthy lifetime it contains the timestamp at which the opthy expires
    uint256 public expiration;
    
    //tokens used in the opthy
    //token0 is the token in which holder pay the fee to the seller and the token that the seller deposits
    IERC20 public token0;
    //token1 is the token that the holder can swap for token0 after agreement
    IERC20 public token1;
    
    //Inequality for checking that the contract contains at least the seller's liquidity:
    // balance0 >= r0 (at agreement)
    // r1 * balance0 + r0 * balance1 >= r0*r1 (until expiration)
    // Idea: say the opthy is a put opthy of 1 WETH for 1000DAI, then r0=1000 and r1=1
    //       (each value is in its decimals representation, so the same as would be memorized in its ERC20)
    uint128 public r0;
    uint128 public r1;

    constructor(uint32 duration_, address holder_, address seller_, IERC20 token0_, IERC20 token1_, uint128 r0_, uint128 r1_, address parent_, address child_) 
    DoublyLinkedNode(parent_, child_) {
        
        //This contract is created, registred and funded by another contract, so some test are there
            
        phase       =   1;
        
        require(duration_ > 0, "Duration must be a non zero quantity");
        duration    =   duration_;
        
        require(holder_ == address(0x0) || seller_ == address(0x0), "Only one between holder and seller can be specified");
        holder      =   holder_;
        seller      =   seller_;

        expiration = block.timestamp + duration;  //Safe for the hackathon, unsafe for production//////////////////////////////////////////////
        
        require(address(token0_) != address(0x0) && address(token1_) != address(0x0), "Token addresses must be valid ERC20 addresses");
        require(address(token0_) != address(token1_), "Tokens must be two distinct ERC20 tokens");
        token0      =   token0_;
        token1      =   token1_;
        
        require(r0_ > 0 && r1_ > 0, "Reserve constants must be a non zero quantity");
        r0          =   r0_;
        r1          =   r1_;
    }
    
    function getOwner() public view returns(address) {
        return seller!=address(0x0)?seller:holder;
    }
    
    event Update(address indexed creator, uint32 phase);
    function update(uint32 duration_, uint128 amount0_, uint128 r0_, uint128 r1_) public {
        require(phase > 0, "Phase mismatch");
        phase++;
        
        address owner = getOwner();
        require(msg.sender == owner, "You're not the owner");
        
        require(duration_ > 0, "Duration must be a non zero quantity");
        duration = duration_;
        
        expiration = block.timestamp + duration;  //Safe for the hackathon, unsafe for production//////////////////////////////////////////////
        
        require(r0_ > 0 && r1_ > 0, "Reserve constants must be a non zero quantity");
        r0 = r0_;
        r1 = r1_;
        
        if (amount0_ > 0) {
            token0.safeTransferFrom(msg.sender, address(this), amount0_);
        }
        
        emit Update(owner, phase);
    }
    
    
    event Agree(address indexed counterparty, uint256 expiration);
    function agree(uint128 amount0_, uint32 phase_) public {
        require(phase > 0 && phase == phase_, "Phase mismatch");
        phase = 0;
        
        // require(msg.sender != getOwner(), "You can't be the holder and the seller of the same opthy"); //commented out to simplify testing
        require(amount0_ > 0, "Amount0 must be a non zero quantity");
        
        if (seller == address(0x0)) {
            seller = msg.sender;
        } else {
            holder = msg.sender;
        }
        expiration = block.timestamp + duration;  //Safe for the hackathon, unsafe for production//////////////////////////////////////////////
        
        token0.safeTransferFrom(msg.sender, address(this), amount0_);
        require(token0.balanceOf(address(this)) >= r0, "Insufficient liquidity");
        
        emit Agree(msg.sender, expiration);
    }
    
    
    event Swap(address indexed holder, uint128 amount0In, uint128 amount1In, uint128 amount0Out, uint128 amount1Out);
    function swap(uint128 amount0In_, uint128 amount1In_, uint128 amount0Out_, uint128 amount1Out_) public {
        require(phase == 0, "Opthy still in haggling phase");
        require(msg.sender == holder, "You're not the opthy holder");
        require(block.timestamp < expiration, "Opthy expired");  //Safe for the hackathon, unsafe for production///////////////////////////////
        require(amount0Out_ > 0 || amount1Out_ > 0, "At least one output must be a non zero quantity");
        
        //Transfer inputs
        if (amount0In_ > 0) {
            token0.safeTransferFrom(holder, address(this), amount0In_);
        }
        if (amount1In_ > 0) {
            token1.safeTransferFrom(holder, address(this), amount1In_);
        }
        
        //Transfer outputs
        if (amount0Out_ > 0) {
            token0.safeTransfer(holder, amount0Out_);    
        }
        if (amount1Out_ > 0) {
            token1.safeTransfer(holder, amount1Out_);
        }
        
        //Check if there is at least the seller's liquidity
        (uint256 balance0, uint256 balance1) = balance();
        require(r1 * balance0 + r0 * balance1 >= uint256(r0)*uint256(r1), "Insufficient liquidity");

        emit Swap(holder, amount0In_, amount1In_, amount0Out_, amount1Out_);
    }
    
    
    event Reclaim(address indexed owner, uint256 balance0, uint256 balance1);
    function reclaim() public {
        require(block.timestamp >= expiration,"Opthy not yet expired");  //Safe for the hackathon, unsafe for production////////////////////////
        address owner = getOwner();
        require(msg.sender == owner, "You're not the owner");

        (uint256 balance0, uint256 balance1) = balance();
        
        if (balance0 > 0) {
            token0.safeTransfer(owner, balance0);
        }
        
        if (balance1 > 0) {
            token1.safeTransfer(owner, balance1);
        }
        
        super.delist();
        
        emit Reclaim(owner, balance0, balance1);
    }
    
    
    function balance() public view returns(uint256,uint256) {
        return (token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    }
}