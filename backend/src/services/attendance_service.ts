import { AttendanceRepository, DBAttendanceLog } from '../repositories/attendance_repository';
import { AdjustmentRepository } from '../repositories/adjustment_repository';
import { AppError } from '../middleware/error_handler';
import { db } from '../config/db';
import { logger } from '../config/logger';

export class AttendanceService {
  private attendanceRepo = new AttendanceRepository();

  private todayString(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private localDateString(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  /**
   * Automatically sweep and mark missed checkouts for a user
   */
  private async sweepMissedCheckouts(userId: number): Promise<void> {
    try {
      // Find unclosed sessions older than 12 hours
      const limitTime = new Date(Date.now() - 12 * 60 * 60 * 1000);
      const unclosed = await this.attendanceRepo.findUnclosedSessionsBefore(limitTime);
      
      const userUnclosed = unclosed.filter(s => s.userId === userId);
      for (const session of userUnclosed) {
        logger.info(`[Auto Sweep] Flagging unclosed attendance session ID ${session.id} for user ${userId} as MISSED_CHECKOUT.`);
        await this.attendanceRepo.markAsMissedCheckout(session.id);
      }
    } catch (err: any) {
      logger.error(`[Auto Sweep] Failed to compile missed checkout sweeps for user ${userId}: ${err.message}`);
    }
  }

  /**
   * Retrieve today's attendance states (check-in, break, checkout details)
   */
  async getTodayState(userId: number): Promise<any> {
    // 1. Run sweep first to clean historical inconsistencies
    await this.sweepMissedCheckouts(userId);

    const todayString = this.todayString();
    const todayRecord = await this.attendanceRepo.findTodayRecord(userId, todayString);

    if (!todayRecord) {
      return { status: 'NOT_CHECKED_IN' };
    }

    if (todayRecord.checkOutTime) {
      return {
        status: 'CHECKED_OUT',
        checkInTime: todayRecord.checkInTime,
        checkOutTime: todayRecord.checkOutTime,
        statusLabel: todayRecord.status,
        totalWorkedMinutes: todayRecord.totalWorkedMinutes
      };
    }

    // Check if on active break
    const activeBreak = await this.attendanceRepo.findActiveBreak(todayRecord.id);

    return {
      status: activeBreak ? 'BREAK_ACTIVE' : 'CHECKED_IN',
      checkInTime: todayRecord.checkInTime,
      activeBreakStart: activeBreak?.breakStart,
      statusLabel: todayRecord.status,
      attendanceId: todayRecord.id
    };
  }

  /**
   * Process daily check-in (Server timestamp enforced!)
   */
  async checkIn(userId: number): Promise<DBAttendanceLog> {
    const todayString = this.todayString();

    // 1. Validate if already checked in today (Rule 1)
    const existing = await this.attendanceRepo.findTodayRecord(userId, todayString);
    if (existing) {
      throw new AppError('Conflict: You have already checked in for today', 400);
    }

    // Rule 6: Prevent multiple active attendance sessions
    const { db } = require('../config/db');
    const activeSessionRes = await db.query('SELECT id FROM attendance_logs WHERE user_id = $1 AND check_out_time IS NULL', [userId]);
    if (activeSessionRes.rows.length > 0) {
      throw new AppError('Conflict: You already have an active attendance session in progress. Please clock out first.', 400);
    }

    // 2. Load User Shift settings (Rule 4 & 5)
    const shift = await this.attendanceRepo.getUserShift(userId);
    let status: 'ON_TIME' | 'LATE' | 'EARLY' | 'SHIFT_NOT_ASSIGNED' = 'ON_TIME';
    let shiftId: number | null = null;

    if (!shift) {
      status = 'SHIFT_NOT_ASSIGNED';
      logger.warn(`[Attendance Core] User ${userId} checking in without shift assignment. Flagged status.`);
    } else {
      shiftId = shift.id;
      const [shiftHour, shiftMin] = shift.startTime.split(':').map(Number);
      const graceMinutes = shift.gracePeriod;

      const now = new Date();

      // Shift start exact time
      const shiftStartTime = new Date();
      shiftStartTime.setHours(shiftHour, shiftMin, 0, 0);

      // Late deadline: shift start + grace period
      const deadline = new Date();
      deadline.setHours(shiftHour, shiftMin + graceMinutes, 0, 0);

      if (now.getTime() > deadline.getTime()) {
        status = 'LATE';
      } else if (now.getTime() < shiftStartTime.getTime()) {
        status = 'EARLY';
      } else {
        status = 'ON_TIME';
      }
    }

    const now = new Date();
    logger.info(`[Attendance Core] User ${userId} checking in at ${now.toISOString()} | Status evaluated: ${status}`);
    return await this.attendanceRepo.createCheckIn(userId, shiftId, status, todayString);
  }

  /**
   * Process daily check-out (Server timestamp enforced!)
   */
  async checkOut(userId: number): Promise<void> {
    const todayString = this.todayString();
    
    // 1. Fetch current daily log
    const todayRecord = await this.attendanceRepo.findTodayRecord(userId, todayString);
    if (!todayRecord) {
      throw new AppError('Bad Request: You have not checked in for today yet', 400);
    }

    // Rule 2: Prevent checkout if already checked out
    if (todayRecord.checkOutTime) {
      throw new AppError('Conflict: You have already checked out for today', 400);
    }

    const now = new Date();

    // Rule: Checkout must be on the same calendar date as check-in
    const checkInDateStr = this.localDateString(todayRecord.checkInTime);
    const nowDateStr = this.localDateString(now);
    if (checkInDateStr !== nowDateStr) {
      throw new AppError('Check-out must be on the same day as check-in. If you forgot to check out yesterday, please submit a correction request.', 400);
    }

    // Rule 3: Break auto-close before checkout
    const activeBreak = await this.attendanceRepo.findActiveBreak(todayRecord.id);
    if (activeBreak) {
      logger.info(`[Attendance Core] Active break session found on clock-out. Auto-closing break ID: ${activeBreak.id}`);
      const breakDuration = Math.max(0, Math.round((now.getTime() - activeBreak.breakStart.getTime()) / 60000));
      await this.attendanceRepo.endBreak(activeBreak.id, breakDuration);
    }

    // Fetch shift for overtime detection
    const shift = await this.attendanceRepo.getUserShift(userId);

    // 3. Calculate worked minutes (Subtracting break durations)
    const grossMinutes = Math.max(0, Math.round((now.getTime() - todayRecord.checkInTime.getTime()) / 60000));
    const breakMinutes = await this.attendanceRepo.getSumBreaksDuration(todayRecord.id);
    const netWorkedMinutes = Math.max(0, grossMinutes - breakMinutes);

    // Detect overtime: compare actual checkout time vs assigned shift end time
    let overtimeMinutes = 0;
    if (shift) {
      const [endH, endM] = shift.endTime.split(':').map(Number);
      const shiftEnd = new Date(now);
      shiftEnd.setHours(endH, endM, 0, 0);
      // Night shift: if shift ends next day (endTime < startTime), add 24h
      const [startH] = shift.startTime.split(':').map(Number);
      if (endH < startH) shiftEnd.setDate(shiftEnd.getDate() + 1);
      if (now.getTime() > shiftEnd.getTime()) {
        overtimeMinutes = Math.max(0, Math.round((now.getTime() - shiftEnd.getTime()) / 60000));
      }
    }

    logger.info(`[Attendance Core] User ${userId} checking out. Gross: ${grossMinutes}m | Breaks: ${breakMinutes}m | Net: ${netWorkedMinutes}m | OT: ${overtimeMinutes}m`);
    await this.attendanceRepo.updateCheckOut(todayRecord.id, userId, netWorkedMinutes, overtimeMinutes);

    // Auto-create a LATE_CHECKOUT approval request when employee checks out after shift end
    if (shift && overtimeMinutes > 0) {
      try {
        const existing = await db.query(
          `SELECT id FROM adjustment_requests WHERE attendance_id = ? AND adjustment_type = 'LATE_CHECKOUT'`,
          [todayRecord.id]
        );
        if (existing.rows.length === 0) {
          const adjustmentRepo = new AdjustmentRepository();
          const shiftEndDisplay = shift.endTime ?? '18:00';
          const reqId = await adjustmentRepo.create({
            userId,
            attendanceId: todayRecord.id,
            adjustmentType: 'LATE_CHECKOUT',
            requestedMinutes: overtimeMinutes,
            requestedCheckinTime: null,
            requestedCheckoutTime: null,
            reason: `Late checkout: ${overtimeMinutes} min after shift end (${shiftEndDisplay}). Pending manager → HR approval.`,
            managerApprovedAt: null,
            managerApprovedBy: null,
          });
          // Link the request back to the attendance record
          await db.query(
            `UPDATE attendance_logs SET late_checkout_request_id = ? WHERE id = ?`,
            [reqId, todayRecord.id]
          );
          logger.info(`[Attendance] Auto-created LATE_CHECKOUT request ${reqId} for user ${userId} — ${overtimeMinutes}m overtime`);
        }
      } catch (err: any) {
        // Non-fatal: checkout already recorded, just log the issue
        logger.error(`[Attendance] Failed to auto-create LATE_CHECKOUT request for user ${userId}: ${err.message}`);
      }
    }
  }

  /**
   * Start break log
   */
  async startBreak(userId: number): Promise<void> {
    const todayString = this.todayString();
    const todayRecord = await this.attendanceRepo.findTodayRecord(userId, todayString);

    if (!todayRecord || todayRecord.checkOutTime) {
      throw new AppError('Bad Request: Active attendance session is required to log breaks', 400);
    }

    // Check if break already active
    const activeBreak = await this.attendanceRepo.findActiveBreak(todayRecord.id);
    if (activeBreak) {
      throw new AppError('Conflict: You already have an active break session in progress', 400);
    }

    logger.info(`[Attendance Core] User ${userId} starting break.`);
    await this.attendanceRepo.startBreak(todayRecord.id);
  }

  /**
   * End break log
   */
  async endBreak(userId: number): Promise<void> {
    const todayString = this.todayString();
    const todayRecord = await this.attendanceRepo.findTodayRecord(userId, todayString);

    if (!todayRecord) {
      throw new AppError('Bad Request: Attendance log not found', 400);
    }

    // Find active break session
    const activeBreak = await this.attendanceRepo.findActiveBreak(todayRecord.id);
    if (!activeBreak) {
      throw new AppError('Bad Request: No active break session found to end', 400);
    }

    // Calculate break duration
    const now = new Date();
    const duration = Math.max(0, Math.round((now.getTime() - activeBreak.breakStart.getTime()) / 60000));

    logger.info(`[Attendance Core] User ${userId} ending break. Duration: ${duration} minutes.`);
    await this.attendanceRepo.endBreak(activeBreak.id, duration);
  }

  /**
   * Get user attendance logs history with optional date range filter
   */
  async getHistory(userId: number, fromDate?: string, toDate?: string): Promise<any[]> {
    return await this.attendanceRepo.getUserHistory(userId, fromDate, toDate);
  }

  /**
   * Get a single attendance record for a specific date (used by correction form validation)
   */
  async getRecordForDate(userId: number, date: string): Promise<any | null> {
    return await this.attendanceRepo.findTodayRecord(userId, date);
  }
}
