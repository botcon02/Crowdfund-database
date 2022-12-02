DROP TABLE IF EXISTS Users, Creators, Backers, Projects, RewardLevel, Funds, Updates, Employees, Verifies, RefundRequests CASCADE;

/*
Users are allowed to change email, ON UPDATE CASCADE included for
foreign keys with email as a constraint.
eid/pid should not be changed and ON UPDATE RESTRICT (default)
*/

CREATE TABLE Users (
  email TEXT PRIMARY KEY,
  uname TEXT NOT NULL,
  cc1   TEXT NOT NULL,
  cc2   TEXT
);

CREATE TABLE Creators (
  country TEXT NOT NULL,
  email   TEXT PRIMARY KEY,
  FOREIGN KEY (email) REFERENCES Users
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Backers (
  country TEXT NOT NULL,
  street  TEXT NOT NULL,
  house   TEXT NOT NULL,
  zipcode TEXT NOT NULL,
  email   TEXT PRIMARY KEY,
  FOREIGN KEY (email) REFERENCES Users
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Projects (
  pid           SERIAL PRIMARY KEY,
  pname         TEXT NOT NULL,
  fund_goal     INT NOT NULL CHECK (fund_goal > 0),
  deadline      DATE NOT NULL,
  start_date    DATE NOT NULL,
  creator_email TEXT NOT NULL,
  -- Foreign key for our Updates aggregation
	UNIQUE (pid, creator_email),
	-- Ensures that every project has a creator
  FOREIGN KEY (creator_email) REFERENCES Creators (email)
    ON UPDATE CASCADE
);

CREATE TABLE RewardLevel (
  pid         INT,
  level       TEXT,
  requirement INT NOT NULL CHECK (requirement > 0),
  PRIMARY KEY (pid, level),
  FOREIGN KEY (pid) REFERENCES Projects (pid)
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Funds (
  pid          INT,
	level        TEXT NOT NULL,
  backer_email TEXT NOT NULL,
	amount       INT NOT NULL CHECK (amount > 0),
	-- Backers can only back a project at one reward level.
	UNIQUE (pid, backer_email),
	PRIMARY KEY (pid, level, backer_email),
	FOREIGN KEY (pid, level) REFERENCES RewardLevel (pid, level),
	FOREIGN KEY (backer_email) REFERENCES Backers (email) ON UPDATE CASCADE
);

CREATE TABLE Updates (
	-- A project only has one creator.
  pid           INT,
	creator_email TEXT,
	update_date   TIMESTAMP,
	update_description TEXT,
	-- Captures aggregation relationship in ERD
  PRIMARY KEY (pid, creator_email, update_date),
  FOREIGN KEY (pid, creator_email) REFERENCES Projects (pid, creator_email)
);

CREATE TABLE Employees (
  eid    SERIAL PRIMARY KEY,
  name   TEXT NOT NULL,
  salary INT NOT NULL CHECK (salary > 0)
);

-- Keep track of latest verification.
CREATE TABLE Verifies (
  eid         INT REFERENCES Employees (eid) NOT NULL,
  uemail      TEXT REFERENCES Users (email) ON UPDATE CASCADE,
  verify_date DATE NOT NULL,
  PRIMARY KEY (uemail)
);

CREATE TABLE RefundRequests (
  backer_email  TEXT,
  pid           INT,
  eid           INT CHECK (status <> 'pending' AND eid IS NOT NULL),
	-- Status of a request is either pending, rejected or approved.
  status        TEXT NOT NULL DEFAULT 'pending'
		CHECK (status = 'pending' OR status = 'rejected' OR status = 'approved'),
  requestedDate TIMESTAMP NOT NULL,
  processedDate TIMESTAMP
		CHECK ((status = 'pending' AND processedDate IS NULL)
			OR (status <> 'pending' AND processedDate IS NOT NULL)),
  PRIMARY KEY (pid, backer_email),
  FOREIGN KEY (pid, backer_email) REFERENCES Funds (pid, backer_email),
  FOREIGN KEY (eid) REFERENCES Employees(eid)
);
