/* ----- TRIGGERS     ----- */
-- Trigger 1
CREATE OR REPLACE FUNCTION user_isa()
RETURNS TRIGGER AS $$
BEGIN
  IF (NEW.email NOT IN (SELECT email FROM Backers)
      AND NEW.email NOT IN (SELECT email FROM Creators)) THEN
    RAISE EXCEPTION 'Not in backer/creator!';
    RETURN NULL;
  ELSE
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS isa_user ON Users;

CREATE CONSTRAINT TRIGGER isa_user
AFTER INSERT ON Users
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION user_isa();

-- Trigger 2
CREATE OR REPLACE FUNCTION valid_pledge()
RETURNS TRIGGER AS $$
DECLARE
  required_amt NUMERIC;
  actual_amt NUMERIC;
BEGIN
-- get the amount into a variable
  actual_amt := NEW.amount;
-- get the reward levels min amount
  SELECT min_amt INTO required_amt
  FROM Rewards r
  WHERE r.name = NEW.name AND r.id = NEW.id;

  IF actual_amt < required_amt THEN
    RAISE NOTICE 'Amount backed does not meet minimum amount for this reward level.';
    RETURN NULL;
  ELSE 
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS pledge_valid ON Backs;

CREATE TRIGGER pledge_valid
BEFORE 
  INSERT
  ON Backs
FOR EACH ROW
  EXECUTE FUNCTION valid_pledge();

-- Trigger 3
CREATE OR REPLACE FUNCTION check_min_reward_level() RETURNS TRIGGER AS $$
DECLARE
    count INT;
BEGIN
    SELECT COUNT(*) INTO count FROM Rewards r WHERE r.id = NEW.id;
    IF (count < 1) THEN RAISE EXCEPTION 'Requires at least 1 reward';
    END IF;
		RETURN NULL;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS min_reward_level_check ON Projects;

CREATE CONSTRAINT TRIGGER min_reward_level_check
AFTER INSERT OR UPDATE ON Projects
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_min_reward_level();

-- Trigger 4
CREATE OR REPLACE FUNCTION check_refund_date() 
RETURNS TRIGGER AS $$
DECLARE
    requestDate DATE;
    projDeadline DATE;
    daysSince INT;
BEGIN
    SELECT b.request INTO requestDate from Backs b WHERE b.id = NEW.pid AND b.email = NEW.email;
    
    IF (requestDate IS NULL) THEN
        RAISE NOTICE 'Cannot approve/reject if refund has not been requested!';
        RETURN NULL;
    END IF;

    SELECT p.deadline INTO projDeadline from Projects p WHERE p.id = NEW.pid;
    daysSince := requestDate - projDeadline;

    IF (daysSince > 90 AND NEW.accepted) THEN
        RAISE NOTICE 'Cannot approve if refund >90 days from deadline';
        RETURN NULL;
    END IF;

    RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS refund_date_check ON Refunds;

CREATE TRIGGER refund_date_check
BEFORE INSERT OR UPDATE ON Refunds
FOR EACH ROW EXECUTE FUNCTION check_refund_date();

-- Trigger 5
CREATE OR REPLACE FUNCTION check_back_before_deadline() RETURNS TRIGGER AS $$
DECLARE
	  backingDate DATE;
    projCreation DATE;
    projDeadline DATE;
BEGIN
    SELECT p.created, p.deadline INTO projCreation, projDeadline FROM Projects p WHERE p.id = NEW.id;
    backingDate := NEW.backing;
    -- check that date is after created date and before deadline
    IF (backingDate <= projCreation OR backingDate > projDeadline) THEN
        RAISE NOTICE 'Date is invalid';
				RETURN NULL;
    END IF;
    
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS back_before_deadline_check ON Backs;

CREATE TRIGGER back_before_deadline_check
BEFORE INSERT OR UPDATE ON Backs
FOR EACH ROW EXECUTE FUNCTION check_back_before_deadline();

-- Trigger 6
CREATE OR REPLACE FUNCTION valid_refund() 
RETURNS TRIGGER AS $$ 
DECLARE 
  funding_goal NUMERIC; 
  pledged_amt NUMERIC; 
  p_deadline DATE; 
BEGIN 
  -- get deadline and goal of the project 
  SELECT goal, deadline INTO funding_goal, p_deadline 
  FROM Projects p 
  WHERE p.id = NEW.id; 
 
  -- check if request date is before p_deadline (inclusive)
  IF (NEW.request <= p_deadline) THEN 
    RAISE NOTICE 'Deadline for project has not passed'; 
    RETURN NULL; 
  END IF; 
 
  -- compute total pledge amt 
  SELECT SUM(amount) INTO pledged_amt  
  FROM Backs b 
  WHERE b.id = NEW.id; 
 
  IF (pledged_amt < funding_goal) THEN 
    RAISE NOTICE 'Pledged amount has not met the funding goal'; 
    RETURN NULL; 
  END IF; 
  RETURN NEW; 
 
END; 
$$ LANGUAGE plpgsql; 

DROP TRIGGER IF EXISTS refund_valid_check ON Backs;
 
CREATE TRIGGER refund_valid_check 
BEFORE  
  UPDATE 
  ON Backs 
FOR EACH ROW 
  EXECUTE FUNCTION valid_refund();
/* ------------------------ */





/* ----- PROECEDURES  ----- */
/* Procedure #1 */
CREATE OR REPLACE PROCEDURE add_user(
  email TEXT, name    TEXT, cc1  TEXT,
  cc2   TEXT, street  TEXT, num  TEXT,
  zip   TEXT, country TEXT, kind TEXT
) AS $$
-- add declaration here
BEGIN
-- check for invalid kind input.
IF (kind != 'BACKER' AND kind != 'CREATOR' AND kind != 'BOTH') THEN
  RETURN;
END IF;
INSERT INTO Users VALUES (email, name, cc1, cc2);
IF (kind = 'BACKER') THEN
    INSERT INTO Backers VALUES (email, street, num, zip, country);
ELSIF (kind = 'CREATOR') THEN
    INSERT INTO Creators VALUES (email, country);
ELSE
    INSERT INTO Backers VALUES (email, street, num, zip, country);
    INSERT INTO Creators VALUES (email, country);
END IF;
END;
$$ LANGUAGE plpgsql;

/* Procedure #2 */
CREATE OR REPLACE PROCEDURE add_project(
  id      INT,     email TEXT,   ptype    TEXT,
  created DATE,    name  TEXT,   deadline DATE,
  goal    NUMERIC, names TEXT[],
  amounts NUMERIC[]
) AS $$
-- add declaration here
DECLARE
  temp INT := 1;
  length INT := cardinality(names);
BEGIN
  IF length != cardinality(amounts) THEN
    RAISE NOTICE 'Unequal array length';
    RETURN;
  END IF;
  INSERT INTO Projects VALUES (id, email, ptype, created, name, deadline, goal);
  LOOP
    EXIT WHEN temp > length;
    INSERT INTO Rewards VALUES (names[temp], id, amounts[temp]);
    temp := temp + 1;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

/* Procedure #3 */
CREATE OR REPLACE PROCEDURE auto_reject(eid INT , today DATE) 
AS $$
DECLARE
curs CURSOR FOR (SELECT * FROM Backs);
b RECORD;
requestDate DATE;
projDeadline DATE;
daysSince INT;
BEGIN
    OPEN curs;
    LOOP
        FETCH curs INTO b;
        EXIT WHEN NOT FOUND;
        requestDate := b.request;
        daysSince := NULL;
        IF requestDate IS NOT NULL THEN
            SELECT p.deadline INTO projDeadline from Projects p WHERE p.id = b.id;
            daysSince := requestDate - projDeadline;
            IF daysSince > 90 AND NOT EXISTS (SELECT * FROM Refunds r WHERE r.email = b.email AND r.pid = b.id) THEN
                INSERT INTO Refunds VALUES (b.email, b.id, eid, today, False);
            END IF;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
/* ------------------------ */




/* ----- ADDITIONAL FUNCTIONS ----- */
/* Additional function #1 */
-- Find all successful projects in the last month
CREATE OR REPLACE FUNCTION find_successful_projects_in_last_month(
    today DATE
) RETURNS TABLE (id INT, email TEXT, ptype TEXT, created DATE, name TEXT, deadline DATE, goal NUMERIC) AS $$
BEGIN
    RETURN QUERY SELECT * FROM Projects p WHERE (
       SELECT SUM(amount) FROM Backs b WHERE b.id = p.id 
    ) >= p.goal AND p.deadline < today - 30;
		-- I want projects with deadline that has passed i.e. smaller than today - 30
END;
$$ LANGUAGE plpgsql;



/* Additional function #2 */
-- Find the backers who requested for refunds in last month
CREATE OR REPLACE FUNCTION users_with_refunds_in_last_month(
    today DATE
) RETURNS TABLE (email TEXT, name TEXT) AS $$
BEGIN
    RETURN QUERY SELECT u.email AS email, u.name AS name FROM Users u, Refunds r
    WHERE u.email = r.email
    AND r.date > today - 30 AND r.date <= today
    UNION
    SELECT u.email AS email, u.name AS name FROM Users u, Backs b
    WHERE u.email = b.email
    AND b.request IS NOT NULL;
END; $$ LANGUAGE plpgsql;



/* Additional function #3 */
-- Find the date the project meet its funding goal
CREATE OR REPLACE FUNCTION find_date_met(
  INOUT pid INT, OUT goal_date DATE
) RETURNS RECORD AS $$
DECLARE
  curs2 CURSOR FOR (SELECT * FROM Backs b WHERE b.id = pid ORDER BY b.backing ASC);
  r RECORD;
  pgoal INT := (SELECT goal FROM Projects p WHERE p.id = pid);
BEGIN
  OPEN curs2;
  LOOP
    EXIT WHEN pgoal <= 0;
    FETCH curs2 INTO r;
    EXIT WHEN NOT FOUND;
    pgoal := pgoal - r.amount;
  END LOOP;
  goal_date := NULL;
  IF pgoal <= 0 THEN
    goal_date := r.backing;
  END IF;
  CLOSE curs2;
END;
$$ LANGUAGE plpgsql;



/* Additional function #4 */
-- Helper function for find_top_popular
CREATE OR REPLACE FUNCTION find_top_popular_helper(
  today DATE, ptype TEXT
) RETURNS TABLE(id INT, name TEXT, email TEXT,
                days INT) AS $$
DECLARE
  type TEXT := ptype;
  curs1 CURSOR FOR (SELECT * FROM Projects p WHERE p.ptype = type AND p.created < today);
  r1 RECORD;
  r2 RECORD;
BEGIN
  OPEN curs1;
  LOOP
    FETCH curs1 INTO r1;
    EXIT WHEN NOT FOUND;
    r2 := find_date_met(r1.id);
    IF r2.goal_date IS NOT NULL THEN
      id := r1.id;
      name := r1.name;
      email := r1.email;
      days := r2.goal_date::date - r1.created::date;
      RETURN NEXT;
    END IF;
  END LOOP;
  CLOSE curs1;
END;
$$ LANGUAGE plpgsql;
/* ------------------------ */





/* ----- FUNCTIONS    ----- */
/* Function #1  */
CREATE OR REPLACE FUNCTION find_superbackers(
  today DATE
) RETURNS TABLE(email TEXT, name TEXT) AS $$
BEGIN
    RETURN QUERY SELECT u.email, u.name FROM Verifies v, Users u WHERE 
    u.email = v.email
    AND
    ((
        -- Verified user has backed at least 5 successful projects with the deadline of the project within 30 days of the given date (in the past) from at least 3 different project types
        (
        -- Number of successful projects backed by a verified user in the past month must be 5 or more
        SELECT COUNT(*) FROM find_successful_projects_in_last_month(today) p, Backs b
        WHERE b.id = p.id
        AND b.email = v.email
        ) > 4
        AND
        (
        -- Number of unique project types of successful projects backed by a verified user in the past month must be 3 or more
        SELECT COUNT(DISTINCT ptype) FROM find_successful_projects_in_last_month(today) p, Backs b
        WHERE b.id = p.id
        AND b.email = v.email
        ) > 2
    )
    OR
    (
        (
        -- Total backed amount of a verified user in the past month for successful projects must be >= 1500
        SELECT SUM (amount) FROM find_successful_projects_in_last_month(today) p, Backs b
        WHERE b.id = p.id
        AND b.email = v.email
        ) >= 1500
        AND
        -- No refund request or accepted/rejected refunds
        NOT EXISTS (
            SELECT * FROM users_with_refunds_in_last_month(today) ur
            WHERE ur.email = v.email
        )
    ))
		ORDER BY u.email ASC;
END;
$$ LANGUAGE plpgsql;



/* Function #2  */
CREATE OR REPLACE FUNCTION find_top_success(
  n INT, today DATE, project_type TEXT
) RETURNS TABLE(id INT, name TEXT, email TEXT,
                amount NUMERIC) AS $$
  WITH successful_projects AS (
    SELECT id, email, name, deadline, goal, (
      SELECT SUM(b.amount) FROM Backs b WHERE b.id = p.id
    ) AS pledged_amount 
    FROM Projects p
    WHERE (
      p.deadline < today
      AND
      p.ptype = project_type
      AND
      p.goal <= (
        SELECT SUM(b.amount)
        FROM Backs b
        WHERE b.id = p.id
      )
    )
  ), sortedResults AS (
    SELECT id, name, email, pledged_amount, (pledged_amount / p.goal) AS funding_ratio, deadline
    FROM successful_projects p
    ORDER BY funding_ratio DESC, deadline DESC, id ASC
    LIMIT n
  )

  SELECT id, name, email, pledged_amount as amount
  FROM sortedResults;

$$ LANGUAGE sql;



/* Function #3  */
CREATE OR REPLACE FUNCTION find_top_popular(
  n INT, today DATE, ptype TEXT
) RETURNS TABLE(id INT, name TEXT, email TEXT,
                days INT) AS $$
BEGIN
  RETURN QUERY SELECT * FROM find_top_popular_helper(today, ptype)
  ORDER BY days ASC, id ASC
  LIMIT n;
END;
$$ LANGUAGE plpgsql;
/* ------------------------ */
