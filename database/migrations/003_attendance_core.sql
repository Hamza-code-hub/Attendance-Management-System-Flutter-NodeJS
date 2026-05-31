-- ============================================================================
-- PHASE 3: CORE ATTENDANCE AND BREAK MANAGEMENT TABLES
-- ============================================================================

-- 1. Alter USERS Table to support shifts
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS shift_id INT REFERENCES shifts(id) ON DELETE SET NULL;

-- Default all default seeded users to Standard Morning Shift (ID = 1)
UPDATE users SET shift_id = 1 WHERE shift_id IS NULL;

-- 2. Create ATTENDANCE_LOGS Table with UUID identifier
CREATE TABLE IF NOT EXISTS attendance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    check_in_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    check_out_time TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'PRESENT' CHECK (status IN ('ON_TIME', 'LATE', 'ABSENT', 'MISSED_CHECKOUT', 'PRESENT')),
    shift_id INT REFERENCES shifts(id) ON DELETE SET NULL,
    total_worked_minutes INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Ensure unique daily attendance log per user
    CONSTRAINT unique_user_daily_log UNIQUE (user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_attendance_logs_user_date ON attendance_logs(user_id, date);
CREATE INDEX IF NOT EXISTS idx_attendance_logs_date ON attendance_logs(date);

-- 3. Create BREAK_LOGS Table with UUID identifier
CREATE TABLE IF NOT EXISTS break_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attendance_id UUID NOT NULL REFERENCES attendance_logs(id) ON DELETE CASCADE,
    break_start TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    break_end TIMESTAMP WITH TIME ZONE,
    duration_minutes INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_break_logs_attendance ON break_logs(attendance_id);
