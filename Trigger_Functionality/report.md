Application Requirements
========================

The database is required to provide certain functionalities as listed below./
Triggers, functions and procedures are implemented to fulfill the requirements, specifically constraints from Part 1 of the project.
The implementation of the triggers/functions are numbered accordingly in Proc.sql.

**Terminology**
- Successful Projects: Fundings exceed the funding goal and deadline has passed
- Success Metric: Ranked by ratio of money funded to the project and the funding goal with larger values indicating a more successful project
- Popularity Metric: Ranked by how fast a project reach their funding goal since the project is created
- Superbacker: The backer is a verified backer and satisfied one or both of the following
    * The backer has backed at least 5 sucessful projects from at least 3 different project type 
    * The backer has funded at least $1500 on sucessful projects and must not have any refund requests

**Application Triggers**
1. Users must be backers, creators or both. There must not be any users that are neither
2. Backers must pledge an amount greater than or equal to minimum amount for the reward level
3. Projects must have at least one reward level
4. Employees can only approve refunds that are requested within 90 days of project deadline
5. Backers can only back a project before the deadline and after it has been created
6. Backers can only request for refund on successful projects

**Application Functionalities**
1. Procedure to add a user which may be a backer, a creator, or both
2. Procedure to add a project and the corresponding reward levels
3. Procedure to help an employee automatically reject refund request where date of request is more than 90 days from deadline
4. Function to find email and name of all superbackers
5. Function to find details of the project for top N most successful project
6. Function to find top N most popular project based on popularity metric
