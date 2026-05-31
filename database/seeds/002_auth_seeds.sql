-- ============================================================================
-- PHASE 2: AUTHENTICATION AND ROLE MANAGEMENT SEEDS
-- ============================================================================

-- 1. Seed Roles
INSERT INTO roles (id, role_name) VALUES
(1, 'Admin'),
(2, 'HR'),
(3, 'Manager'),
(4, 'Employee')
ON CONFLICT (id) DO UPDATE SET role_name = EXCLUDED.role_name;

-- Adjust sequence
SELECT setval('roles_id_seq', (SELECT MAX(id) FROM roles));

-- Note: In a production local database, users should be created via the Admin panel.
-- To ensure ease of evaluation, the backend includes an automatic startup seeder 
-- that detects if the 'users' table is empty and populates these default testing accounts
-- using the exact PBKDF2/SHA-512 cryptographic service:
--
-- * Admin User:
--   Email: admin@office.local
--   Username: admin_user
--   Password: AdminPass123
--
-- * HR User:
--   Email: hr@office.local
--   Username: hr_user
--   Password: HRPass123
--
-- * Manager User:
--   Email: manager@office.local
--   Username: manager_user
--   Password: ManagerPass123
--
-- * Employee User:
--   Email: employee@office.local
--   Username: employee_user
--   Password: EmpPass123
