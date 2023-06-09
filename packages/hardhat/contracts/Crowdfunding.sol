// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 < 0.9.0;

import "./Project.sol";

contract Crowdfunding {
    /// @dev Initializes a project
    event ProjectCreation(
        address projectContractAddress,
        address creator,
        uint256 minContribution,
        uint256 projectDeadline,
        uint256 targetAmount,
        uint256 currentAmount,
        uint256 noOfContributors,
        string title,
        string desc,
        uint256 currentState
    );

    event ContributionReceived(
        address projectAddress,
        uint256 contributedAmount,
        address indexed contributor
    );

    Project[] private projects;

    /// @notice External functions

    /// @dev Get list of projects
    /// @return array
    function returnAllProjects() external view returns (Project[] memory) {
        return projects;
    }

    /// @notice Public functions

    /// @dev Anyone can contribute to a project
    /// @param _projectAddress The project address where funds are deposited
    function contribute(address _projectAddress) public payable {
        uint256 minContributionAmount = Project(_projectAddress)
            .minimumContribution();
        Project.State projectState = Project(_projectAddress).state();
        require(projectState == Project.State.Open, "Invalid state");
        require(
            msg.value >= minContributionAmount,
            "Contribution amount is too low!"
        );
        Project(_projectAddress).contribute{value: msg.value}(msg.sender); // Send fund txn to _projectAddress
        emit ContributionReceived(_projectAddress, msg.value, msg.sender); // Trigger logging event
    }

    /// @dev Anyone is allowed to create a project funding request
    /// @param minimumContribution Minumum accepted ETH per transaction
    /// @param deadline Amount of seconds until the project stops accepting investments
    /// @param targetContribution Amount of ETH the project requires to start development
    /// @param projectTitle Title of infrastructure project
    /// @param projectDesc Description of infrastructure project
    function createProject (
        uint256 minimumContribution,
        uint256 deadline,
        uint256 targetContribution,
        string memory projectTitle,
        string memory projectDesc
    )
        public
    {
		deadline += block.timestamp;
        require(deadline > block.timestamp, "Deadline must be in the future");

        Project newProject = new Project (
            msg.sender,
            minimumContribution,
            deadline,
            targetContribution,
            projectTitle,
            projectDesc
        );
        projects.push(newProject);

        emit ProjectCreation (
            address(newProject),
            msg.sender,
            minimumContribution,
            deadline,
            targetContribution,
            0,
            0,
            projectTitle,
            projectDesc,
            0
        );
    }
}
