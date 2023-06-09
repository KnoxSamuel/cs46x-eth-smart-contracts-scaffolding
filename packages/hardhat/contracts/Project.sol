// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 < 0.9.0;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

bytes32 constant CREDITOR = keccak256("CREDITOR"); //0xcc20a4f09ce3d2c408dc66f828762d80f08534a1cab249f5b63f81750890f4e3
bytes32 constant END_USER = keccak256("END_USER"); //0xf7cea1877766b75e590cddc6205fa80d6ad49a9b2a8f34843a3ae02d1ec9d7c5

contract Project is AccessControlEnumerable {
    /// @dev Initializes project information
    constructor(
        address _creator,
        uint256 _minimumContribution,
        uint256 _deadline,
        uint256 _targetContribution,
        string memory _projectTitle,
        string memory _projectDesc
    ) {
        creator = payable(_creator);
        minimumContribution = _minimumContribution;
        deadline = _deadline + block.timestamp;
        targetContribution = _targetContribution;
        projectTitle = _projectTitle;
        projectDesc = _projectDesc;
        raisedAmount = 0;

        AccessControlEnumerable._grantRole(DEFAULT_ADMIN_ROLE, creator);
    }

    /// @dev Project State
    enum State {
        Open,
        Expired,
        Successful
    }

    /// @notice Structs
    struct WithdrawRequest {
        string description;
        uint256 amount;
        uint256 noOfVotes;
        mapping(address => bool) voters;
        bool isApproved;
        address payable recipient;
    }

    /// @notice Variables
    address payable public creator; // Owner's address of the project
    uint256 public minimumContribution; // The minumum a user can contribute to a project each transaction
    uint256 public deadline;
    uint256 public targetContribution; // Project's crowdfunding goal to start development
    uint256 public completedAt;
    uint256 public raisedAmount; // Count of total amount crowdfunded
    uint256 public noOfContributers;
    string public projectTitle;
    string public projectDesc;
    State public state = State.Open;

    mapping(address => uint256) public contributors;
    mapping(uint256 => WithdrawRequest) public withdrawRequests;

    uint256 public noOfWithdrawRequests = 0;

    /// @notice Modifiers

    /// @dev Modifier that runs before the function it is used in executes, verify user is owner
    modifier isCreator() {
        require(
            msg.sender == creator,
            "You don't have access to perform this operation!"
        );
        _;
    }

    /// @dev Modifier that runs before the function it is used in executes, to verify project state
    modifier atState(State _state) {
        require(state == _state, "Invalid state!");
        _;
    }

    /// @notice Events

    /// @dev Event that will be emitted whenever funding transaction is received
    event FundingReceived(
        address contributor,
        uint256 amount,
        uint256 currentTotal
    );

    /// @dev Event that will be emitted whenever a withdraw request is created by the project owner
    event WithdrawRequestCreated(
        uint256 requestId,
        string description,
        uint256 amount,
        uint256 noOfVotes,
        bool isApproved,
        address recipient
    );

    /// @dev Event that will be emitted whenever a contributor votes for a withdraw request
    event WithdrawRequestVote(address voter, uint256 totalVote);

    /// @dev Event that will be emitted whenever an approved withdraw request is sent to owner
    event AmountWithdrawSuccessful(
        uint256 requestId,
        string description,
        uint256 amount,
        uint256 noOfVotes,
        bool isApproved,
        address recipient
    );

    /// @dev Public Functions

    /// @dev Any user can contribute to a project.
    function contribute(address _contributor) public payable atState(State.Open) {
        require(
            msg.value >= minimumContribution,
            "Contribution amount is too low!"
        );

        if (contributors[_contributor] == 0) {
            noOfContributers++;
            AccessControlEnumerable._grantRole(END_USER, _contributor);
        }
        if (msg.value >= 100 ether) {
            AccessControlEnumerable._grantRole(CREDITOR, _contributor);
        }

        contributors[_contributor] += msg.value;
        raisedAmount += msg.value;
        emit FundingReceived(_contributor, msg.value, raisedAmount);
        checkFundingCompleteOrExpired();
    }

    /// @dev Get the contract's current balance.
    /// @return uint
    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /// @dev Get contract information.
    /// @return projectOwner 
    /// @return minContribution 
    /// @return projectDeadline 
    /// @return goalAmount 
    /// @return timeOfCompletion 
    /// @return currentAmount 
    /// @return title 
    /// @return desc 
    /// @return currentState 
    /// @return balance 
    function getProjectDetails()
        public
        view
        returns (
            address payable projectOwner,
            uint256 minContribution,
            uint256 projectDeadline,
            uint256 goalAmount,
            uint256 timeOfCompletion,
            uint256 currentAmount,
            string memory title,
            string memory desc,
            State currentState,
            uint256 balance
        )
    {
        projectOwner = creator;
        minContribution = minimumContribution;
        projectDeadline = deadline;
        goalAmount = targetContribution;
        timeOfCompletion = completedAt;
        currentAmount = raisedAmount;
        title = projectTitle;
        desc = projectDesc;
        currentState = state;
        balance = address(this).balance;
    }

    /// @dev Contributors can get refund if a project ends before reaching goal.
    /// @return boolean
    function requestRefund() public atState(State.Expired) returns (bool) {
        require(hasRole(END_USER, msg.sender));
        require(
            contributors[msg.sender] > 0,
            "You don't have any assets contributed to this project!"
        );
        uint256 refundAmount = contributors[msg.sender]; // this prevents against reentrancy attacks
        contributors[msg.sender] = 0; 
        payable(msg.sender).transfer(refundAmount);
        return true;
    }

    /// @dev Project funding must be complete & owner must request contributors to withdraw some amount.
    /// @param _description Memo attached to request
    /// @param _amount The amount of ETH owner requested
    /// @param _recipient The address where owner wants withdrawal 
    function createWithdrawRequest(
        string memory _description,
        uint256 _amount,
        address payable _recipient
    )
        public
        isCreator
        atState(State.Successful)
    {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        require(_amount <= getContractBalance(), "Requested amount exceeds contract balance!");

        WithdrawRequest storage newRequest = withdrawRequests[
            noOfWithdrawRequests
        ];
        noOfWithdrawRequests++;

        newRequest.description = _description;
        newRequest.amount = _amount;
        newRequest.noOfVotes = 0;
        newRequest.isApproved = false;
        newRequest.recipient = _recipient;

        emit WithdrawRequestCreated(
            noOfWithdrawRequests,
            _description,
            _amount,
            0,
            false,
            _recipient
        );
    }

    /// @dev Contributors are allowed to vote once for each WithdrawRequest.
    /// @param _requestId Index of the withdraw request
    function voteWithdrawRequest(uint256 _requestId) public {
        require(!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)); // owner can't vote on their project
        require(hasRole(CREDITOR, msg.sender)); // only "big" lenders (contributed >100ETH in one txn) can vote on withdraw requests
        require(
            contributors[msg.sender] > 100 ether,
            "Only CREDITORS are allowed to vote on WithdrawRequests!"
        );
        WithdrawRequest storage requestDetails = withdrawRequests[_requestId];
        require(
            requestDetails.voters[msg.sender] == false,
            "You have already voted!"
        );
        requestDetails.voters[msg.sender] = true;
        requestDetails.noOfVotes += 1;
        emit WithdrawRequestVote(msg.sender, requestDetails.noOfVotes);
    }

    /// @dev Owner can withdraw the requested amount after quorum is met.
    /// @param _requestId Index of the withdraw request
    function withdrawRequestedAmount(uint256 _requestId)
        public
        isCreator
        atState(State.Successful)
    {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        WithdrawRequest storage requestDetails = withdrawRequests[_requestId];
        require(
            requestDetails.isApproved == false,
            "This withdrawal request was already approved."
        );
        require(requestDetails.noOfVotes > 0, "No CREDITOR has voted for this request.");
        require(
            requestDetails.noOfVotes >= (noOfContributers * 2) / 3,
            "More than 66% of CREDITORS need to approve this request."
        );
        requestDetails.isApproved = true;
        requestDetails.recipient.transfer(requestDetails.amount);

        emit AmountWithdrawSuccessful(
            _requestId,
            requestDetails.description,
            requestDetails.amount,
            requestDetails.noOfVotes,
            true,
            requestDetails.recipient
        );
    }

    /// @dev Internal Functions
    
    /// @dev TODO-DEBUG: Seems that project state is set to `Successful` after one contribution
    /// @dev Sets project state if expired or funded
    function checkFundingCompleteOrExpired() internal {
        if (raisedAmount >= targetContribution) {	// if the project has raised enough funds
            completedAt = block.timestamp;
            state = State.Successful;
        } else if (block.timestamp > deadline) { // if current time has passed the deadline
            completedAt = block.timestamp;
            state = State.Expired;
        }
        //completedAt = block.timestamp;
    }
}
