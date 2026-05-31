import sqlite3 from 'sqlite3';
import { logger } from './logger';
import path from 'path';
import fs from 'fs';

const dbFile = path.resolve(__dirname, '../../attendance.db');
const isNewDb = !fs.existsSync(dbFile);

const sqlite = sqlite3.verbose();
const conn = new sqlite.Database(dbFile, (err) => {
  if (err) {
    logger.error(`SQLite database connection error: ${err.message}`);
  } else {
    logger.info(`SQLite Database connected successfully at: ${dbFile}`);
  }
});

// Enable SQLite Foreign Key support
conn.serialize(() => {
  conn.run('PRAGMA foreign_keys = ON;', (err) => {
    if (err) {
      logger.error(`Failed to enable PRAGMA foreign_keys: ${err.message}`);
    }
  });
});

export const db = {
  /**
   * Run a query simulating PostgreSQL's db.query interface
   */
  query: (text: string, params: any[] = []): Promise<{ rows: any[], rowCount: number }> => {
    return new Promise((resolve, reject) => {
      const trimmedText = text.trim();
      const isSelect = 
        trimmedText.toUpperCase().startsWith('SELECT') || 
        trimmedText.toUpperCase().includes('RETURNING');

      // Convert PostgreSQL $1, $2 params to SQLite ? placeholder params
      const sqliteText = trimmedText.replace(/\$\d+/g, '?');

      if (isSelect) {
        conn.all(sqliteText, params, (err, rows) => {
          if (err) {
            logger.error(`SQLite query error: ${err.message} | Query: ${sqliteText} | Params: ${JSON.stringify(params)}`);
            return reject(err);
          }
          resolve({ rows: rows || [], rowCount: rows ? rows.length : 0 });
        });
      } else {
        conn.run(sqliteText, params, function (err) {
          if (err) {
            logger.error(`SQLite query error: ${err.message} | Query: ${sqliteText} | Params: ${JSON.stringify(params)}`);
            return reject(err);
          }
          // Resolve with changes (simulates rowCount in inserts/updates)
          resolve({ rows: [], rowCount: this.changes || 0 });
        });
      }
    });
  },

  /**
   * Placeholder transaction checkout
   */
  getClient: async () => {
    logger.debug('SQLite does not require pool checkouts. Returning generic interface.');
    return {
      query: (t: string, p?: any[]) => db.query(t, p),
      release: () => {}
    };
  },

  /**
   * Graceful close
   */
  close: (): Promise<void> => {
    return new Promise((resolve, reject) => {
      conn.close((err) => {
        if (err) {
          logger.error(`Error closing SQLite connection: ${err.message}`);
          reject(err);
        } else {
          logger.info('SQLite database connection closed.');
          resolve();
        }
      });
    });
  }
};

// ============================================================================
// AUTOMATIC STARTUP DATABASE TABLES SCHEMAS AND SEEDING
// ============================================================================
if (isNewDb) {
  logger.info('[Startup Seeder] Newly created database detected. Starting SQLite schema build...');
  conn.serialize(() => {
    // 1. Create SHIFTS Table
    conn.run(`
      CREATE TABLE IF NOT EXISTS shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_name TEXT UNIQUE NOT NULL,
        shift_start TEXT NOT NULL,
        shift_end TEXT NOT NULL,
        grace_minutes INTEGER DEFAULT 10,
        night_shift_enabled INTEGER DEFAULT 0,
        allow_overtime INTEGER DEFAULT 1,
        active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 2. Create DEPARTMENTS Table
    conn.run(`
      CREATE TABLE IF NOT EXISTS departments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        department_name TEXT UNIQUE NOT NULL,
        description TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 3. Create EMPLOYEES Table
    conn.run(`
      CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_code TEXT UNIQUE NOT NULL,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        phone TEXT,
        designation TEXT,
        department_id INTEGER REFERENCES departments(id) ON DELETE SET NULL,
        shift_id INTEGER REFERENCES shifts(id) ON DELETE SET NULL,
        joining_date TEXT DEFAULT (date('now')),
        employment_status TEXT DEFAULT 'ACTIVE',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 4. Create USERS Table
    conn.run(`
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER UNIQUE REFERENCES employees(id) ON DELETE CASCADE,
        username TEXT UNIQUE NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        status TEXT DEFAULT 'ACTIVE',
        shift_id INTEGER REFERENCES shifts(id) ON DELETE SET NULL,
        last_login TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 5. Create ROLES Table
    conn.run(`
      CREATE TABLE IF NOT EXISTS roles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role_name TEXT UNIQUE NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 6. Create USER_ROLES Link Table
    conn.run(`
      CREATE TABLE IF NOT EXISTS user_roles (
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (user_id, role_id)
      )
    `);

    // 7. Create SESSIONS Table
    conn.run(`
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        refresh_token_hash TEXT UNIQUE NOT NULL,
        expires_at TEXT NOT NULL,
        device_info TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 8. Create ATTENDANCE_LOGS Table
    conn.run(`
      CREATE TABLE IF NOT EXISTS attendance_logs (
        id TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        date TEXT DEFAULT (date('now')),
        check_in_time TEXT DEFAULT CURRENT_TIMESTAMP,
        check_out_time TEXT,
        status TEXT DEFAULT 'PRESENT',
        shift_id INTEGER REFERENCES shifts(id) ON DELETE SET NULL,
        total_worked_minutes INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT unique_user_daily_log UNIQUE (user_id, date)
      )
    `);

    // 9. Create BREAK_LOGS Table
    conn.run(`
      CREATE TABLE IF NOT EXISTS break_logs (
        id TEXT PRIMARY KEY,
        attendance_id TEXT NOT NULL REFERENCES attendance_logs(id) ON DELETE CASCADE,
        break_start TEXT DEFAULT CURRENT_TIMESTAMP,
        break_end TEXT,
        duration_minutes INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // 10. Create AUDIT_LOGS Table
    conn.run(`
      CREATE TABLE IF NOT EXISTS audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actor_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
        action TEXT NOT NULL,
        entity_name TEXT NOT NULL,
        entity_id INTEGER,
        description TEXT NOT NULL,
        ip_address TEXT NOT NULL,
        user_agent TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Seeding static database Roles, Departments, and standard Shifts
    conn.run(`INSERT INTO roles (id, role_name) VALUES (1, 'Admin'), (2, 'HR'), (3, 'Manager'), (4, 'Employee')`);
    conn.run(`INSERT INTO departments (id, department_name, description) VALUES 
      (1, 'Administration', 'Office operations and security management.'),
      (2, 'Human Resources', 'Recruitment, approvals, and employee benefits.'),
      (3, 'Engineering', 'Software development and hardware engineering.'),
      (4, 'Operations', 'General office staff and administration support.')`);
    conn.run(`INSERT INTO shifts (id, shift_name, shift_start, shift_end, grace_minutes, night_shift_enabled, allow_overtime, active) VALUES
      (1, 'Standard Morning Shift', '09:00:00', '18:00:00', 20, 0, 1, 1),
      (2, 'Standard Evening Shift', '14:00:00', '22:00:00', 20, 0, 1, 1),
      (3, 'Night Shift Support', '22:00:00', '06:00:00', 10, 1, 1, 1)`);

    logger.info('[Startup Seeder] SQLite database tables schemas built and seeded successfully.');
  });
}

// Enforce creation of overtime_requests and adjustment_requests tables unconditionally on startup
conn.serialize(() => {
  conn.run(`
    CREATE TABLE IF NOT EXISTS overtime_requests (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      attendance_id TEXT REFERENCES attendance_logs(id) ON DELETE SET NULL,
      request_date TEXT NOT NULL,
      requested_minutes INTEGER NOT NULL,
      approved_minutes INTEGER DEFAULT 0,
      reason TEXT NOT NULL,
      status TEXT DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'PARTIAL')),
      hr_comment TEXT,
      reviewed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
      reviewed_at TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
  `);

  conn.run(`
    CREATE TABLE IF NOT EXISTS adjustment_requests (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      attendance_id TEXT REFERENCES attendance_logs(id) ON DELETE SET NULL,
      adjustment_type TEXT NOT NULL CHECK (adjustment_type IN ('MISSED_CHECKIN', 'MISSED_CHECKOUT', 'LATE_COMPENSATION', 'EARLY_LEAVE', 'CUSTOM')),
      requested_minutes INTEGER NOT NULL,
      approved_minutes INTEGER DEFAULT 0,
      requested_checkin_time TEXT,
      requested_checkout_time TEXT,
      reason TEXT NOT NULL,
      status TEXT DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
      hr_comment TEXT,
      reviewed_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
      reviewed_at TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
  `);
});

// Migration: safely add overtime_minutes column to existing databases
conn.run(`ALTER TABLE attendance_logs ADD COLUMN overtime_minutes INTEGER DEFAULT 0`, (err: any) => {
  if (err && !err.message.includes('duplicate column name')) {
    logger.warn(`[Migration] overtime_minutes column: ${err.message}`);
  }
});
conn.run(`ALTER TABLE adjustment_requests ADD COLUMN manager_approved_at TEXT`, (err: any) => {
  if (err && !err.message.includes('duplicate column name')) {
    logger.warn(`[Migration] manager_approved_at: ${err.message}`);
  }
});
conn.run(`ALTER TABLE adjustment_requests ADD COLUMN manager_approved_by INTEGER REFERENCES users(id) ON DELETE SET NULL`, (err: any) => {
  if (err && !err.message.includes('duplicate column name')) {
    logger.warn(`[Migration] manager_approved_by: ${err.message}`);
  }
});
conn.run(`ALTER TABLE adjustment_requests ADD COLUMN submitted_by_role TEXT DEFAULT 'Employee'`, (err: any) => {
  if (err && !err.message.includes('duplicate column name')) logger.warn(`[Migration] submitted_by_role adj: ${err.message}`);
});
conn.run(`ALTER TABLE overtime_requests ADD COLUMN submitted_by_role TEXT DEFAULT 'Employee'`, (err: any) => {
  if (err && !err.message.includes('duplicate column name')) logger.warn(`[Migration] submitted_by_role ot: ${err.message}`);
});


