-- ============================================================================
-- PHASE 4: EMPLOYEE, SHIFT & DEPARTMENTS CORE MANAGEMENT TABLES
-- ============================================================================

-- Drop dependent tables to avoid constraint blocks during recreation
DROP TABLE IF EXISTS break_logs CASCADE;
DROP TABLE IF EXISTS attendance_logs CASCADE;
DROP TABLE IF EXISTS user_roles CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;
DROP TABLE IF EXISTS password_reset_tokens CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS employees CASCADE;
DROP TABLE IF EXISTS shifts CASCADE;

-- 1. Create SHIFTS Table
CREATE TABLE shifts (
    id SERIAL PRIMARY KEY,
    shift_name VARCHAR(100) UNIQUE NOT NULL,
    shift_start TIME NOT NULL,
    shift_end TIME NOT NULL,
    grace_minutes INT DEFAULT 10,
    night_shift_enabled BOOLEAN DEFAULT FALSE,
    allow_overtime BOOLEAN DEFAULT TRUE,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Create DEPARTMENTS Table
CREATE TABLE departments (
    id SERIAL PRIMARY KEY,
    department_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. Create EMPLOYEES Table
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    employee_code VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    designation VARCHAR(100),
    department_id INT REFERENCES departments(id) ON DELETE SET NULL,
    shift_id INT REFERENCES shifts(id) ON DELETE SET NULL,
    joining_date DATE NOT NULL DEFAULT CURRENT_DATE,
    employment_status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (employment_status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. Recreate USERS Table (incorporating direct employee reference)
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    employee_id INT UNIQUE REFERENCES employees(id) ON DELETE CASCADE,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'PENDING')),
    shift_id INT REFERENCES shifts(id) ON DELETE SET NULL,
    last_login TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. Recreate security, session, and role tables
CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_roles (
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_info TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. Recreate attendance_logs and break_logs using UUID
CREATE TABLE attendance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    check_in_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    check_out_time TIMESTAMP WITH TIME ZONE,
    status VARCHAR(30) DEFAULT 'PRESENT' CHECK (status IN ('ON_TIME', 'LATE', 'ABSENT', 'MISSED_CHECKOUT', 'PRESENT', 'SHIFT_NOT_ASSIGNED', 'BREAK_ACTIVE', 'CHECKED_OUT')),
    shift_id INT REFERENCES shifts(id) ON DELETE SET NULL, -- Case 1: Maintains old history when active shift is changed!
    total_worked_minutes INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_user_daily_log UNIQUE (user_id, date)
);

CREATE TABLE break_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attendance_id UUID NOT NULL REFERENCES attendance_logs(id) ON DELETE CASCADE,
    break_start TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    break_end TIMESTAMP WITH TIME ZONE,
    duration_minutes INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- SEED INITIAL SHIFTS, DEPARTMENTS & ROLES
-- ============================================================================

INSERT INTO roles (id, role_name) VALUES
(1, 'Admin'),
(2, 'HR'),
(3, 'Manager'),
(4, 'Employee')
ON CONFLICT (id) DO UPDATE SET role_name = EXCLUDED.role_name;

SELECT setval('roles_id_seq', (SELECT MAX(id) FROM roles));

INSERT INTO departments (id, department_name, description) VALUES
(1, 'Administration', 'Office operations and security management.'),
(2, 'Human Resources', 'Recruitment, approvals, and employee benefits.'),
(3, 'Engineering', 'Software development and hardware engineering.'),
(4, 'Operations', 'General office staff and administration support.')
ON CONFLICT (id) DO UPDATE SET department_name = EXCLUDED.department_name;

SELECT setval('departments_id_seq', (SELECT MAX(id) FROM departments));

INSERT INTO shifts (id, shift_name, shift_start, shift_end, grace_minutes, night_shift_enabled, allow_overtime, active) VALUES
(1, 'Standard Morning Shift', '09:00:00', '18:00:00', 10, FALSE, TRUE, TRUE),
(2, 'Standard Evening Shift', '14:00:00', '22:00:00', 10, FALSE, TRUE, TRUE),
(3, 'Night Shift Support', '22:00:00', '06:00:00', 10, TRUE, TRUE, TRUE)
ON CONFLICT (id) DO UPDATE SET 
    shift_name = EXCLUDED.shift_name, 
    shift_start = EXCLUDED.shift_start, 
    shift_end = EXCLUDED.shift_end, 
    grace_minutes = EXCLUDED.grace_minutes;

SELECT setval('shifts_id_seq', (SELECT MAX(id) FROM shifts));
