-- ============================================================================
-- INITIAL DATABASE SCHEMA DRAFT - ATTENDANCE MANAGEMENT SYSTEM
-- ============================================================================

-- Enable UUID extension if we want UUID support, though standard INT/BIGINT is fine.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. ROLES TABLE (Admin, HR Manager, Employee)
CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. SHIFTS TABLE (Flexible/Standard Shift configurations)
CREATE TABLE shifts (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    grace_period_minutes INT DEFAULT 15,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. EMPLOYEES TABLE
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    employee_code VARCHAR(20) UNIQUE NOT NULL, -- e.g. EMP001
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role_id INT NOT NULL REFERENCES roles(id),
    shift_id INT REFERENCES shifts(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. ATTENDANCE RECORDS TABLE
CREATE TABLE attendance_records (
    id BIGSERIAL PRIMARY KEY,
    employee_id INT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    work_date DATE NOT NULL DEFAULT CURRENT_DATE,
    clock_in TIMESTAMP WITH TIME ZONE,
    clock_out TIMESTAMP WITH TIME ZONE,
    clock_in_ip VARCHAR(45),
    clock_out_ip VARCHAR(45),
    status VARCHAR(20) DEFAULT 'ABSENT', -- ABSENT, PRESENT, LATE, HALFDAY, LEAVE
    is_suspicious BOOLEAN DEFAULT FALSE,
    suspicious_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Ensure unique attendance record per employee per day
    CONSTRAINT unique_employee_daily_attendance UNIQUE (employee_id, work_date)
);

-- Index for date queries
CREATE INDEX idx_attendance_date ON attendance_records(work_date);
CREATE INDEX idx_attendance_employee ON attendance_records(employee_id);

-- 5. BREAKS TABLE
CREATE TABLE breaks (
    id BIGSERIAL PRIMARY KEY,
    attendance_id BIGINT NOT NULL REFERENCES attendance_records(id) ON DELETE CASCADE,
    break_start TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    break_end TIMESTAMP WITH TIME ZONE,
    reason VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. OVERTIME REQUESTS TABLE
CREATE TABLE overtime_requests (
    id BIGSERIAL PRIMARY KEY,
    employee_id INT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    work_date DATE NOT NULL,
    requested_minutes INT NOT NULL,
    reason TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'PENDING', -- PENDING, APPROVED, REJECTED
    approved_by INT REFERENCES employees(id),
    approved_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 7. ADJUSTMENT REQUESTS TABLE (For missed checkins/checkouts)
CREATE TABLE adjustment_requests (
    id BIGSERIAL PRIMARY KEY,
    attendance_id BIGINT REFERENCES attendance_records(id) ON DELETE CASCADE,
    employee_id INT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    work_date DATE NOT NULL,
    requested_clock_in TIMESTAMP WITH TIME ZONE,
    requested_clock_out TIMESTAMP WITH TIME ZONE,
    reason TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'PENDING', -- PENDING, APPROVED, REJECTED
    approved_by INT REFERENCES employees(id),
    approved_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 8. AUDIT LOGS TABLE (Immutable operations log)
CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    actor_id INT REFERENCES employees(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL, -- e.g. LOGIN, CHECK_IN, APPROVE_OVERTIME
    entity_name VARCHAR(50) NOT NULL, -- e.g. attendance_records, overtime_requests
    entity_id BIGINT,
    description TEXT NOT NULL,
    ip_address VARCHAR(45) NOT NULL,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_created_at ON audit_logs(created_at);
