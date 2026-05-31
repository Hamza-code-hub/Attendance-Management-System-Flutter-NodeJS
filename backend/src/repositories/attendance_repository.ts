import { db } from '../config/db';
import { randomUUID } from 'crypto';
import { AppError } from '../middleware/error_handler';

export interface DBAttendanceLog {
  id: string;
  userId: number;
  date: string;
  checkInTime: Date;
  checkOutTime?: Date;
  status: 'ON_TIME' | 'LATE' | 'ABSENT' | 'MISSED_CHECKOUT' | 'PRESENT';
  shiftId?: number;
  totalWorkedMinutes: number;
  createdAt: Date;
  updatedAt: Date;
}

export interface DBBreakLog {
  id: string;
  attendanceId: string;
  breakStart: Date;
  breakEnd?: Date;
  durationMinutes: number;
  createdAt: Date;
}

export class AttendanceRepository {

  /**
   * SQLite CURRENT_TIMESTAMP returns "YYYY-MM-DD HH:mm:ss" (UTC, no Z suffix).
   * new Date("YYYY-MM-DD HH:mm:ss") is parsed as LOCAL time in Node.js/V8,
   * causing a timezone offset error on every duration calculation.
   * This helper normalises to ISO 8601 with Z so Node.js treats it as UTC.
   */
  private parseSQLiteDate(val: any): Date {
    if (!val) return new Date(NaN);
    if (val instanceof Date) return val;
    const s = String(val);
    return new Date(s.includes('T') ? s : s.replace(' ', 'T') + 'Z');
  }

  /**
   * Find today's attendance log for a specific user
   */
  async findTodayRecord(userId: number, dateString: string): Promise<DBAttendanceLog | null> {
    const query = 'SELECT * FROM attendance_logs WHERE user_id = $1 AND date = $2';
    const result = await db.query(query, [userId, dateString]);
    
    if (result.rows.length === 0) return null;
    
    const row = result.rows[0];
    return {
      id: row.id,
      userId: row.user_id,
      date: typeof row.date === 'string' ? row.date : row.date.toISOString().split('T')[0],
      checkInTime: this.parseSQLiteDate(row.check_in_time),
      checkOutTime: row.check_out_time ? this.parseSQLiteDate(row.check_out_time) : undefined,
      status: row.status,
      shiftId: row.shift_id,
      totalWorkedMinutes: row.total_worked_minutes,
      createdAt: this.parseSQLiteDate(row.created_at),
      updatedAt: this.parseSQLiteDate(row.updated_at)
    };
  }

  /**
   * Insert a new daily attendance log (Server timestamp is enforced in SQL!)
   */
  async createCheckIn(userId: number, shiftId: number | null, status: string, dateString: string): Promise<DBAttendanceLog> {
    const id = randomUUID();
    const query = `
      INSERT INTO attendance_logs (id, user_id, date, check_in_time, status, shift_id, total_worked_minutes)
      VALUES ($1, $2, $3, CURRENT_TIMESTAMP, $4, $5, 0)
      RETURNING *
    `;
    const result = await db.query(query, [id, userId, dateString, status, shiftId]);
    const row = result.rows[0];
    
    return {
      id: row.id,
      userId: row.user_id,
      date: typeof row.date === 'string' ? row.date : row.date.toISOString().split('T')[0],
      checkInTime: this.parseSQLiteDate(row.check_in_time),
      status: row.status,
      shiftId: row.shift_id,
      totalWorkedMinutes: row.total_worked_minutes,
      createdAt: this.parseSQLiteDate(row.created_at),
      updatedAt: this.parseSQLiteDate(row.updated_at)
    };
  }

  /**
   * Update clock out record (Server timestamp is enforced in SQL!)
   */
  async updateCheckOut(id: string, userId: number, workedMinutes: number, overtimeMinutes: number = 0): Promise<void> {
    const query = `
      UPDATE attendance_logs
      SET check_out_time = CURRENT_TIMESTAMP, total_worked_minutes = $1, overtime_minutes = $2, updated_at = CURRENT_TIMESTAMP
      WHERE id = $3 AND user_id = $4 AND check_out_time IS NULL
    `;
    const result = await db.query(query, [workedMinutes, overtimeMinutes, id, userId]);
    if (result.rowCount === 0) {
      throw new AppError('Secure checkout failed: attendance session is already closed or does not belong to this user', 409);
    }
  }

  /**
   * Fetch active break for a specific attendance session (Where break_end is null)
   */
  async findActiveBreak(attendanceId: string): Promise<DBBreakLog | null> {
    const query = `
      SELECT * FROM break_logs 
      WHERE attendance_id = $1 AND break_end IS NULL
    `;
    const res = await db.query(query, [attendanceId]);
    if (res.rows.length === 0) return null;
    
    const row = res.rows[0];
    return {
      id: row.id,
      attendanceId: row.attendance_id,
      breakStart: this.parseSQLiteDate(row.break_start),
      createdAt: this.parseSQLiteDate(row.created_at),
      durationMinutes: row.duration_minutes
    };
  }

  /**
   * Start break log (Server timestamp is enforced in SQL!)
   */
  async startBreak(attendanceId: string): Promise<DBBreakLog> {
    const id = randomUUID();
    const query = `
      INSERT INTO break_logs (id, attendance_id, break_start, duration_minutes, created_at)
      VALUES ($1, $2, CURRENT_TIMESTAMP, 0, CURRENT_TIMESTAMP)
      RETURNING *
    `;
    const res = await db.query(query, [id, attendanceId]);
    const row = res.rows[0];
    return {
      id: row.id,
      attendanceId: row.attendance_id,
      breakStart: this.parseSQLiteDate(row.break_start),
      createdAt: this.parseSQLiteDate(row.created_at),
      durationMinutes: row.duration_minutes
    };
  }

  /**
   * End break log (Server timestamp is enforced in SQL!)
   */
  async endBreak(breakId: string, durationMinutes: number): Promise<void> {
    const query = `
      UPDATE break_logs
      SET break_end = CURRENT_TIMESTAMP, duration_minutes = $1
      WHERE id = $2
    `;
    await db.query(query, [durationMinutes, breakId]);
  }

  /**
   * Fetch sum of all closed breaks duration for an attendance session
   */
  async getSumBreaksDuration(attendanceId: string): Promise<number> {
    const query = `
      SELECT COALESCE(SUM(duration_minutes), 0) as total 
      FROM break_logs 
      WHERE attendance_id = $1 AND break_end IS NOT NULL
    `;
    const res = await db.query(query, [attendanceId]);
    return parseInt(res.rows[0].total);
  }

  /**
   * Fetch user attendance logs history with optional date range filter
   */
  async getUserHistory(userId: number, fromDate?: string, toDate?: string): Promise<any[]> {
    const params: any[] = [userId];
    let idx = 2;
    let dateFilter = '';

    if (fromDate) {
      dateFilter += ` AND al.date >= $${idx++}`;
      params.push(fromDate);
    }
    if (toDate) {
      dateFilter += ` AND al.date <= $${idx++}`;
      params.push(toDate);
    }

    const query = `
      SELECT al.*, s.shift_name
      FROM attendance_logs al
      LEFT JOIN shifts s ON s.id = al.shift_id
      WHERE al.user_id = $1${dateFilter}
      ORDER BY al.date DESC
      LIMIT 90
    `;
    const res = await db.query(query, params);
    return res.rows.map((row) => ({
      id: row.id,
      userId: row.user_id,
      date: typeof row.date === 'string' ? row.date : row.date.toISOString().split('T')[0],
      checkInTime: row.check_in_time ? new Date(row.check_in_time).toISOString() : null,
      checkOutTime: row.check_out_time ? new Date(row.check_out_time).toISOString() : null,
      status: row.status,
      shiftName: row.shift_name || 'Standard Morning Shift',
      totalWorkedMinutes: row.total_worked_minutes != null ? Number(row.total_worked_minutes) : 0
    }));
  }

  /**
   * Fetch user's shift settings (directly from shifts table assigned to users)
   */
  async getUserShift(userId: number): Promise<{ id: number; startTime: string; endTime: string; gracePeriod: number; allowOvertime: boolean } | null> {
    const query = `
      SELECT s.id, s.shift_start, s.shift_end, s.grace_minutes, s.allow_overtime 
      FROM shifts s
      INNER JOIN users u ON u.shift_id = s.id
      WHERE u.id = $1
    `;
    const res = await db.query(query, [userId]);
    if (res.rows.length === 0) return null;
    
    const row = res.rows[0];
    return {
      id: row.id,
      startTime: row.shift_start,
      endTime: row.shift_end,
      gracePeriod: row.grace_minutes,
      allowOvertime: row.allow_overtime === 1 || row.allow_overtime === true
    };
  }

  /**
   * Fetch older uncompleted sessions for automatic MISSED_CHECKOUT sweeps
   */
  async findUnclosedSessionsBefore(limitTime: Date): Promise<DBAttendanceLog[]> {
    const query = `
      SELECT * FROM attendance_logs
      WHERE check_out_time IS NULL AND check_in_time < $1
    `;
    const res = await db.query(query, [limitTime]);
    return res.rows.map((row) => ({
      id: row.id,
      userId: row.user_id,
      date: typeof row.date === 'string' ? row.date : row.date.toISOString().split('T')[0],
      checkInTime: this.parseSQLiteDate(row.check_in_time),
      status: row.status,
      totalWorkedMinutes: row.total_worked_minutes,
      createdAt: this.parseSQLiteDate(row.created_at),
      updatedAt: this.parseSQLiteDate(row.updated_at)
    }));
  }

  /**
   * Flag a session as MISSED_CHECKOUT
   */
  async markAsMissedCheckout(id: string): Promise<void> {
    const query = `
      UPDATE attendance_logs
      SET status = 'MISSED_CHECKOUT', updated_at = CURRENT_TIMESTAMP
      WHERE id = $1
    `;
    await db.query(query, [id]);
  }
}
