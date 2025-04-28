-- Enhanced Library Management System
-- A comprehensive digital library management system with subscription-based access
-- Created: April 28, 2025

SET FOREIGN_KEY_CHECKS=0;
DROP TABLE IF EXISTS Users, Resources, Authors, Categories, ResourceTypes, Loans, 
    Subscriptions, Plans, Payments, Reviews, AuthorResources, ResourceCategories;
SET FOREIGN_KEY_CHECKS=1;

-- Core Tables
CREATE TABLE Users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(15),
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

CREATE TABLE Authors (
    author_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    biography TEXT,
    email VARCHAR(100) UNIQUE
);

CREATE TABLE Categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    parent_category_id INT,
    description TEXT,
    FOREIGN KEY (parent_category_id) REFERENCES Categories(category_id)
);

CREATE TABLE ResourceTypes (
    type_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    description TEXT,
    loan_period INT NOT NULL -- in days
);

CREATE TABLE Resources (
    resource_id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    type_id INT NOT NULL,
    isbn VARCHAR(20) UNIQUE,
    publication_year INT,
    physical_copies INT DEFAULT 0,
    digital_copies INT DEFAULT 0,
    is_digital BOOLEAN DEFAULT FALSE,
    peer_reviewed BOOLEAN DEFAULT FALSE,
    content_url VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (type_id) REFERENCES ResourceTypes(type_id)
);

CREATE TABLE Plans (
    plan_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    duration INT NOT NULL, -- in months
    max_physical_loans INT NOT NULL,
    max_digital_loans INT NOT NULL,
    description TEXT
);

CREATE TABLE Subscriptions (
    subscription_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    plan_id INT NOT NULL,
    start_date TIMESTAMP NOT NULL,
    end_date TIMESTAMP NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    auto_renewal BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    FOREIGN KEY (plan_id) REFERENCES Plans(plan_id)
);

CREATE TABLE Loans (
    loan_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    resource_id INT NOT NULL,
    loan_date TIMESTAMP NOT NULL,
    due_date TIMESTAMP NOT NULL,
    return_date TIMESTAMP,
    status ENUM('active', 'returned', 'overdue') NOT NULL,
    fine_amount DECIMAL(10, 2) DEFAULT 0.00,
    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    FOREIGN KEY (resource_id) REFERENCES Resources(resource_id)
);

CREATE TABLE Payments (
    payment_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    payment_type ENUM('subscription', 'fine', 'deposit') NOT NULL,
    payment_method VARCHAR(50) NOT NULL,
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('pending', 'completed', 'failed') NOT NULL,
    FOREIGN KEY (user_id) REFERENCES Users(user_id)
);

CREATE TABLE Reviews (
    review_id INT AUTO_INCREMENT PRIMARY KEY,
    resource_id INT NOT NULL,
    user_id INT NOT NULL,
    rating INT CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (resource_id) REFERENCES Resources(resource_id),
    FOREIGN KEY (user_id) REFERENCES Users(user_id)
);

-- Junction Tables
CREATE TABLE AuthorResources (
    author_id INT NOT NULL,
    resource_id INT NOT NULL,
    role ENUM('primary', 'contributor', 'editor') NOT NULL,
    PRIMARY KEY (author_id, resource_id),
    FOREIGN KEY (author_id) REFERENCES Authors(author_id),
    FOREIGN KEY (resource_id) REFERENCES Resources(resource_id)
);

CREATE TABLE ResourceCategories (
    resource_id INT NOT NULL,
    category_id INT NOT NULL,
    PRIMARY KEY (resource_id, category_id),
    FOREIGN KEY (resource_id) REFERENCES Resources(resource_id),
    FOREIGN KEY (category_id) REFERENCES Categories(category_id)
);

-- Views
CREATE VIEW v_available_resources AS
SELECT 
    r.resource_id,
    r.title,
    rt.name AS resource_type,
    r.is_digital,
    (r.physical_copies + r.digital_copies - 
        (SELECT COUNT(*) FROM Loans 
         WHERE resource_id = r.resource_id 
         AND status = 'active')
    ) AS available_copies
FROM Resources r
JOIN ResourceTypes rt ON r.type_id = rt.type_id;

CREATE VIEW v_active_loans AS
SELECT 
    l.loan_id,
    u.name AS borrower,
    r.title,
    l.loan_date,
    l.due_date,
    l.status,
    CASE 
        WHEN l.status = 'overdue' 
        THEN DATEDIFF(CURRENT_TIMESTAMP, l.due_date) * 0.50
        ELSE 0 
    END AS current_fine
FROM Loans l
JOIN Users u ON l.user_id = u.user_id
JOIN Resources r ON l.resource_id = r.resource_id
WHERE l.status IN ('active', 'overdue');

CREATE VIEW v_subscription_status AS
SELECT 
    u.user_id,
    u.name,
    p.name AS plan_name,
    s.start_date,
    s.end_date,
    s.is_active,
    p.max_physical_loans - COALESCE(
        (SELECT COUNT(*) FROM Loans 
         WHERE user_id = u.user_id 
         AND status = 'active'
         AND resource_id IN (SELECT resource_id FROM Resources WHERE is_digital = FALSE)
        ), 0) AS remaining_physical_loans,
    p.max_digital_loans - COALESCE(
        (SELECT COUNT(*) FROM Loans 
         WHERE user_id = u.user_id 
         AND status = 'active'
         AND resource_id IN (SELECT resource_id FROM Resources WHERE is_digital = TRUE)
        ), 0) AS remaining_digital_loans
FROM Users u
LEFT JOIN Subscriptions s ON u.user_id = s.user_id AND s.is_active = TRUE
LEFT JOIN Plans p ON s.plan_id = p.plan_id;

-- Triggers
DELIMITER //

CREATE TRIGGER tr_update_resource_availability
AFTER INSERT ON Loans
FOR EACH ROW
BEGIN
    UPDATE Resources r
    SET r.physical_copies = CASE 
        WHEN r.is_digital = FALSE 
        THEN r.physical_copies - 1
        ELSE r.physical_copies
    END,
    r.digital_copies = CASE 
        WHEN r.is_digital = TRUE 
        THEN r.digital_copies - 1
        ELSE r.digital_copies
    END
    WHERE r.resource_id = NEW.resource_id;
END//

CREATE TRIGGER tr_check_subscription
BEFORE INSERT ON Loans
FOR EACH ROW
BEGIN
    DECLARE user_plan_id INT;
    DECLARE is_digital BOOLEAN;
    DECLARE current_physical_loans INT;
    DECLARE current_digital_loans INT;
    DECLARE max_physical_loans INT;
    DECLARE max_digital_loans INT;
    
    -- Get user's active plan
    SELECT p.plan_id, p.max_physical_loans, p.max_digital_loans
    INTO user_plan_id, max_physical_loans, max_digital_loans
    FROM Subscriptions s
    JOIN Plans p ON s.plan_id = p.plan_id
    WHERE s.user_id = NEW.user_id 
    AND s.is_active = TRUE
    AND CURRENT_TIMESTAMP BETWEEN s.start_date AND s.end_date
    LIMIT 1;
    
    -- Check if user has active subscription
    IF user_plan_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'User does not have an active subscription';
    END IF;
    
    -- Get resource type
    SELECT is_digital INTO is_digital
    FROM Resources
    WHERE resource_id = NEW.resource_id;
    
    -- Count current loans
    SELECT 
        COUNT(CASE WHEN r.is_digital = FALSE THEN 1 END),
        COUNT(CASE WHEN r.is_digital = TRUE THEN 1 END)
    INTO current_physical_loans, current_digital_loans
    FROM Loans l
    JOIN Resources r ON l.resource_id = r.resource_id
    WHERE l.user_id = NEW.user_id 
    AND l.status = 'active';
    
    -- Check limits
    IF is_digital = FALSE AND current_physical_loans >= max_physical_loans THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Physical loan limit reached';
    ELSEIF is_digital = TRUE AND current_digital_loans >= max_digital_loans THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Digital loan limit reached';
    END IF;
END//

-- Stored Procedures
CREATE PROCEDURE sp_lend_resource(
    IN p_user_id INT,
    IN p_resource_id INT
)
BEGIN
    DECLARE v_loan_period INT;
    
    -- Get loan period for resource type
    SELECT rt.loan_period INTO v_loan_period
    FROM Resources r
    JOIN ResourceTypes rt ON r.type_id = rt.type_id
    WHERE r.resource_id = p_resource_id;
    
    -- Create loan record
    INSERT INTO Loans (
        user_id, 
        resource_id, 
        loan_date, 
        due_date, 
        status
    )
    VALUES (
        p_user_id, 
        p_resource_id, 
        CURRENT_TIMESTAMP, 
        DATE_ADD(CURRENT_TIMESTAMP, INTERVAL v_loan_period DAY),
        'active'
    );
END//

CREATE PROCEDURE sp_return_resource(
    IN p_loan_id INT
)
BEGIN
    DECLARE v_resource_id INT;
    DECLARE v_is_digital BOOLEAN;
    
    -- Get resource information
    SELECT l.resource_id, r.is_digital 
    INTO v_resource_id, v_is_digital
    FROM Loans l
    JOIN Resources r ON l.resource_id = r.resource_id
    WHERE l.loan_id = p_loan_id;
    
    -- Update loan status
    UPDATE Loans
    SET status = 'returned',
        return_date = CURRENT_TIMESTAMP,
        fine_amount = CASE 
            WHEN CURRENT_TIMESTAMP > due_date 
            THEN DATEDIFF(CURRENT_TIMESTAMP, due_date) * 0.50
            ELSE 0 
        END
    WHERE loan_id = p_loan_id;
    
    -- Update resource availability
    UPDATE Resources
    SET physical_copies = CASE 
            WHEN is_digital = FALSE 
            THEN physical_copies + 1
            ELSE physical_copies
        END,
        digital_copies = CASE 
            WHEN is_digital = TRUE 
            THEN digital_copies + 1
            ELSE digital_copies
        END
    WHERE resource_id = v_resource_id;
END//

CREATE PROCEDURE sp_manage_subscription(
    IN p_user_id INT,
    IN p_plan_id INT,
    IN p_action VARCHAR(10)
)
BEGIN
    IF p_action = 'activate' THEN
        -- Deactivate any existing active subscription
        UPDATE Subscriptions 
        SET is_active = FALSE 
        WHERE user_id = p_user_id AND is_active = TRUE;
        
        -- Create new subscription
        INSERT INTO Subscriptions (
            user_id, 
            plan_id, 
            start_date, 
            end_date, 
            is_active
        )
        SELECT 
            p_user_id,
            p_plan_id,
            CURRENT_TIMESTAMP,
            DATE_ADD(CURRENT_TIMESTAMP, INTERVAL duration MONTH),
            TRUE
        FROM Plans 
        WHERE plan_id = p_plan_id;
        
    ELSEIF p_action = 'deactivate' THEN
        UPDATE Subscriptions
        SET is_active = FALSE
        WHERE user_id = p_user_id AND is_active = TRUE;
    END IF;
END//

DELIMITER ;

-- Sample Data
INSERT INTO ResourceTypes (name, description, loan_period) VALUES
('Book', 'Physical and digital books', 14),
('Research Paper', 'Academic research papers', 30),
('Educational Kit', 'Learning materials and equipment', 7),
('Audiobook', 'Audio format books', 14);

INSERT INTO Categories (name, description) VALUES
('Fiction', 'Fictional literature'),
('Non-Fiction', 'Non-fictional literature'),
('Academic', 'Academic materials'),
('Children', 'Materials for children');

INSERT INTO Plans (name, price, duration, max_physical_loans, max_digital_loans, description) VALUES
('Basic', 9.99, 1, 2, 3, 'Basic membership with limited access'),
('Premium', 19.99, 1, 5, 10, 'Premium membership with extended access'),
('Academic', 29.99, 1, 10, 20, 'Academic membership for research purposes');

-- Test Queries
-- Test available resources
SELECT * FROM v_available_resources;

-- Test subscription status
SELECT * FROM v_subscription_status;

-- Test active loans
SELECT * FROM v_active_loans;