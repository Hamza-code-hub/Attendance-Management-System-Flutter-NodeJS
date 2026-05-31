-- ============================================================================
-- INITIAL SEED DATA - ATTENDANCE MANAGEMENT SYSTEM
-- ============================================================================

-- 1. Insert Default Roles
INSERT INTO roles (id, name, description) VALUES
(1, 'Admin', 'Full system configuration, settings, backup, and log access.'),
(2, 'HR', 'Employee management, shift schedules, overtime, adjustment approvals, and Excel reports generation.'),
(3, 'Employee', 'Standard check-in/out, break logs, overtime requests, and adjustment requests.')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

-- Reset standard roles sequence
SELECT setval('roles_id_seq', (SELECT MAX(id) FROM roles));

-- 2. Insert Standard Office Shifts
INSERT INTO shifts (id, name, start_time, end_time, grace_period_minutes) VALUES
(1, 'Standard Morning Shift', '09:00:00', '18:00:00', 15),
(2, 'Evening Shift', '14:00:00', '22:00:00', 15),
(3, 'Night Shift', '22:00:00', '06:00:00', 15)
ON CONFLICT (id) DO UPDATE SET 
    name = EXCLUDED.name, 
    start_time = EXCLUDED.start_time, 
    end_time = EXCLUDED.end_time, 
    grace_period_minutes = EXCLUDED.grace_period_minutes;

-- Reset standard shifts sequence
SELECT setval('shifts_id_seq', (SELECT MAX(id) FROM shifts));

-- 3. Insert Starter Employees
-- Passwords are placeholders representing standard bcrypt/argon2 hashes of "Password123"
INSERT INTO employees (employee_code, first_name, last_name, email, password_hash, role_id, shift_id) VALUES
('EMP001', 'System', 'Administrator', 'admin@office.local', '$2b$10$vI8aWBndfN6v/vR6vC9WKuK3Uj/eF/8k1b9B/1q2P3O4N5M6L7K8J', 1, 1),
('EMP002', 'Sarah', 'HR Manager', 'hr@office.local', '$2b$10$vI8aWBndfN6v/vR6vC9WKuK3Uj/eF/8k1b9B/1q2P3O4N5M6L7K8J', 2, 1),
('EMP003', 'John', 'Doe', 'employee@office.local', '$2b$10$vI8aWBndfN6v/vR6vC9WKuK3Uj/eF/8k1b9B/1q2P3O4N5M6L7K8J', 3, 1)
ON CONFLICT (email) DO NOTHING;
