import { AdjustmentRepository, DBAdjustmentRequest } from '../repositories/adjustment_repository';
import { AttendanceRepository } from '../repositories/attendance_repository';
import { AutomationJobsService } from './automation_jobs';
import { AppError } from '../middleware/error_handler';
import { db } from '../config/db';
import crypto from 'crypto';

export class AdjustmentService {
  private adjustmentRepo = new AdjustmentRepository();
  private attendanceRepo = new AttendanceRepository();

  private localDateString(date: Date): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private isGlobalReviewer(roles: string[]): boolean {
    return roles.includes('Admin') || roles.includes('HR');
  }

  private async getReviewerDepartmentId(reviewerId: number, roles: string[]): Promise<number | undefined> {
    if (this.isGlobalReviewer(roles)) return undefined;
    if (!roles.includes('Manager')) throw new AppError('Forbidden: Reviewer role is not allowed', 403);

    const res = await db.query(
      `SELECT e.department_id
       FROM users u
       INNER JOIN employees e ON e.id = u.employee_id
       WHERE u.id = $1`,
      [reviewerId]
    );
    const departmentId = res.rows[0]?.department_id;
    if (!departmentId) throw new AppError('Forbidden: Manager is not assigned to a department', 403);
    return departmentId;
  }

  private async assertReviewScope(requestUserId: number, reviewerId: number, roles: string[]): Promise<void> {
    const reviewerDepartmentId = await this.getReviewerDepartmentId(reviewerId, roles);
    if (!reviewerDepartmentId) return;

    const res = await db.query(
      `SELECT e.department_id
       FROM users u
       INNER JOIN employees e ON e.id = u.employee_id
       WHERE u.id = $1`,
      [requestUserId]
    );
    if (res.rows[0]?.department_id !== reviewerDepartmentId) {
      throw new AppError('Forbidden: Managers can only review requests from their own department', 403);
    }
  }

  /**
   * Submit a new attendance adjustment request
   */
  async createRequest(
    userId: number,
    adjustmentType: string,
    requestedCheckinTime: string | null,
    requestedCheckoutTime: string | null,
    reason: string,
    ipAddress: string,
    submitterRoles: string[] = [],
    explicitMinutes?: number,
    requestDate?: string | null
  ): Promise<string> {
    // Rule 1: Reason is required
    if (!reason || reason.trim() === '') {
      throw new AppError('Validation Error: A reason is required to submit an attendance adjustment request.', 400);
    }

    if (!adjustmentType) {
      throw new AppError('Bad Request: Adjustment type is required', 400);
    }

    let parsedDateStr: string;
    let requestedMinutes = 0;

    if (adjustmentType === 'TIME_ADJUSTMENT') {
      // TIME_ADJUSTMENT uses requestDate + requestedMinutes directly — no checkin/checkout required
      if (!requestDate) {
        throw new AppError('Bad Request: requestDate is required for time adjustments.', 400);
      }
      if (!explicitMinutes || explicitMinutes <= 0 || explicitMinutes > 480) {
        throw new AppError('Bad Request: requestedMinutes must be between 1 and 480 for time adjustments.', 400);
      }
      parsedDateStr = requestDate;
      requestedMinutes = explicitMinutes;
    } else {
      // Standard correction/adjustment: require at least one time field
      const timeToParse = requestedCheckinTime || requestedCheckoutTime;
      if (!timeToParse) {
        throw new AppError('Bad Request: Either requested check-in or check-out time must be provided.', 400);
      }
      try {
        const dateObj = new Date(timeToParse);
        if (isNaN(dateObj.getTime())) throw new Error();
        parsedDateStr = this.localDateString(dateObj);
      } catch {
        throw new AppError('Bad Request: Invalid date format for check-in/check-out time.', 400);
      }
      // Calculate requested minutes if both times are provided
      if (requestedCheckinTime && requestedCheckoutTime) {
        const inTime = new Date(requestedCheckinTime);
        const outTime = new Date(requestedCheckoutTime);
        requestedMinutes = Math.max(0, Math.round((outTime.getTime() - inTime.getTime()) / 60000));
      }
    }

    // Check that request is not for a future date
    const todayStr = this.localDateString(new Date());
    if (parsedDateStr > todayStr) {
      throw new AppError('Validation Error: Adjustment requests cannot be made for future dates.', 400);
    }

    // 3-day window enforced for correction types (MISSED_CHECKIN, MISSED_CHECKOUT, CUSTOM)
    const correctionTypes = ['MISSED_CHECKIN', 'MISSED_CHECKOUT', 'CUSTOM'];
    if (correctionTypes.includes(adjustmentType)) {
      const cutoff = new Date();
      cutoff.setDate(cutoff.getDate() - 3);
      if (parsedDateStr < this.localDateString(cutoff)) {
        throw new AppError('Correction requests can only be submitted within 3 days of the date. Older records must be corrected by HR directly.', 400);
      }
      // Per-type required fields
      if (adjustmentType === 'MISSED_CHECKIN' && !requestedCheckinTime) {
        throw new AppError('Correction for check-in requires a requested check-in time.', 400);
      }
      if (adjustmentType === 'MISSED_CHECKOUT' && !requestedCheckoutTime) {
        throw new AppError('Correction for check-out requires a requested check-out time.', 400);
      }
      if (adjustmentType === 'CUSTOM' && (!requestedCheckinTime || !requestedCheckoutTime)) {
        throw new AppError('Correction for both times requires both check-in and check-out times.', 400);
      }
    }

    // Block duplicate PENDING requests for the same date (allow resubmission after rejection)
    const existing = await this.adjustmentRepo.findByUserAndDate(userId, parsedDateStr);
    if (existing && existing.status === 'PENDING') {
      throw new AppError('A pending correction request for this date already exists. Wait for the current request to be reviewed before submitting again.', 400);
    }

    // Check if attendance record exists to link it
    const attendance = await this.attendanceRepo.findTodayRecord(userId, parsedDateStr);

    const requestId = await this.adjustmentRepo.create({
      userId,
      attendanceId: attendance ? attendance.id : null,
      adjustmentType: adjustmentType as DBAdjustmentRequest['adjustmentType'],
      requestedMinutes,
      requestedCheckinTime,
      requestedCheckoutTime,
      reason,
    });

    // Auto-route based on submitter role
    const isManager = submitterRoles.includes('Manager') && !submitterRoles.includes('HR') && !submitterRoles.includes('Admin');
    const isHR = submitterRoles.includes('HR') && !submitterRoles.includes('Admin');
    const submittedByRole = isHR ? 'HR' : isManager ? 'Manager' : 'Employee';

    await db.query(`UPDATE adjustment_requests SET submitted_by_role = $1 WHERE id = $2`, [submittedByRole, requestId]);

    // Manager and HR requests skip the manager approval stage — HR requests go straight to Admin
    if (isManager || isHR) {
      await db.query(
        `UPDATE adjustment_requests SET manager_approved_at = CURRENT_TIMESTAMP, manager_approved_by = $1 WHERE id = $2`,
        [userId, requestId]
      );
    }

    // Write audit log
    await AutomationJobsService.writeAuditHook(
      userId,
      'CREATE_ADJUSTMENT_REQUEST',
      'adjustment_requests',
      null,
      `Submitted adjustment request of type ${adjustmentType} for date ${parsedDateStr}. ID: ${requestId}`,
      ipAddress
    );

    return requestId;
  }

  /**
   * Fetch personal request history
   */
  async getHistory(userId: number): Promise<DBAdjustmentRequest[]> {
    return await this.adjustmentRepo.findHistoryByUser(userId);
  }

  /**
   * Fetch pending adjustment requests for the given reviewer role.
   *
   * Routing rules:
   *  • Manager  — sees Employee requests at stage 1 (no manager approval yet) in their dept
   *  • HR       — sees Employee requests at stage 2 + Manager requests (all manager-approved)
   *  • Admin    — sees everything (including HR's own requests)
   */
  async getPendingRequests(reviewerId: number, roles: string[]): Promise<DBAdjustmentRequest[]> {
    const isAdmin = roles.includes('Admin');
    const isHR    = roles.includes('HR') && !isAdmin;
    const isGlobal = isAdmin || isHR;
    const departmentId = isGlobal ? undefined : await this.getReviewerDepartmentId(reviewerId, roles).catch(() => undefined);

    if (isAdmin) {
      // Admin sees every pending request regardless of submitter or stage
      return await this.adjustmentRepo.findPending(undefined, 'all', undefined);
    }

    if (isHR) {
      // HR sees stage-2 Employee requests + Manager requests (both have manager_approved_at set)
      return await this.adjustmentRepo.findPending(undefined, 'hr', ['Employee', 'Manager']);
    }

    // Manager sees stage-1 Employee requests in their department only
    return await this.adjustmentRepo.findPending(departmentId, 'manager', ['Employee']);
  }

  /**
   * Review (Approve/Reject/Manager-stage) adjustment request
   */
  async reviewRequest(
    requestId: string,
    reviewerId: number,
    roles: string[],
    status: 'APPROVED' | 'REJECTED' | 'MANAGER_APPROVE',
    hrComment: string | null,
    ipAddress: string
  ): Promise<void> {
    const request = await this.adjustmentRepo.findById(requestId);
    if (!request) throw new AppError('Not Found: Adjustment request not found', 404);
    if (request.status !== 'PENDING') throw new AppError('Conflict: This request has already been reviewed.', 400);

    const isGlobal = this.isGlobalReviewer(roles);
    const isManager = roles.includes('Manager');

    // Admin can move any request directly to HR stage (bypass manager step)
    if (isGlobal && status === 'MANAGER_APPROVE') {
      if (request.managerApprovedAt) throw new AppError('Conflict: Manager stage already completed.', 400);
      await this.adjustmentRepo.managerApprove(requestId, reviewerId);
      await AutomationJobsService.writeAuditHook(
        reviewerId, 'ADMIN_MANAGER_BYPASS', 'adjustment_requests', null,
        `Admin bypassed manager stage for adjustment ID: ${requestId}`, ipAddress
      );
      return;
    }

    // Manager stage: set manager_approved_at (does not change status to APPROVED yet)
    if (isManager && !isGlobal && status === 'MANAGER_APPROVE') {
      if (request.managerApprovedAt) throw new AppError('Conflict: Manager has already approved this request.', 400);
      await this.assertReviewScope(request.userId, reviewerId, roles);
      await this.adjustmentRepo.managerApprove(requestId, reviewerId);
      await AutomationJobsService.writeAuditHook(
        reviewerId, 'MANAGER_APPROVE_ADJUSTMENT', 'adjustment_requests', null,
        `Manager approved (stage 1) adjustment request ID: ${requestId}`, ipAddress
      );
      return;
    }

    // Manager can also REJECT at stage 1
    if (isManager && !isGlobal && status === 'REJECTED') {
      await this.assertReviewScope(request.userId, reviewerId, roles);
      await this.adjustmentRepo.reviewRequest(requestId, 'REJECTED', 0, hrComment, reviewerId);
      await AutomationJobsService.writeAuditHook(
        reviewerId, 'REVIEW_ADJUSTMENT_REJECTED', 'adjustment_requests', null,
        `Manager rejected adjustment request ID: ${requestId}`, ipAddress
      );
      return;
    }

    // HR/Admin final approval
    if (isGlobal) {
      if (!['APPROVED', 'REJECTED'].includes(status)) {
        throw new AppError('Bad Request: HR/Admin status must be APPROVED or REJECTED', 400);
      }

      // TIME_ADJUSTMENT is about makeup hours — no attendance log to patch
      if (status === 'APPROVED' && request.adjustmentType !== 'TIME_ADJUSTMENT') {
        const timeToParse = request.requestedCheckinTime || request.requestedCheckoutTime;
        if (!timeToParse) {
          throw new AppError('Bad Request: Adjustment request is missing time data and cannot be applied.', 400);
        }
        const dateStr = new Date(timeToParse).toISOString().split('T')[0];
        const shift = await this.attendanceRepo.getUserShift(request.userId);
        let attendanceStatus = 'ON_TIME';
        if (request.requestedCheckinTime) {
          if (!shift) { attendanceStatus = 'SHIFT_NOT_ASSIGNED'; }
          else {
            const checkIn = new Date(request.requestedCheckinTime);
            const [shiftHour, shiftMin] = shift.startTime.split(':').map(Number);
            const deadline = new Date(checkIn);
            deadline.setHours(shiftHour, shiftMin + shift.gracePeriod, 0, 0);
            attendanceStatus = checkIn.getTime() > deadline.getTime() ? 'LATE' : 'ON_TIME';
          }
        }
        const existingAttendance = await this.attendanceRepo.findTodayRecord(request.userId, dateStr);
        if (existingAttendance) {
          const checkIn = request.requestedCheckinTime ? new Date(request.requestedCheckinTime) : existingAttendance.checkInTime;
          const checkOut = request.requestedCheckoutTime ? new Date(request.requestedCheckoutTime) : (existingAttendance.checkOutTime || null);
          let workedMinutes = 0;
          if (checkIn && checkOut) {
            const grossMinutes = Math.max(0, Math.round((checkOut.getTime() - checkIn.getTime()) / 60000));
            const breakMinutes = await this.attendanceRepo.getSumBreaksDuration(existingAttendance.id);
            workedMinutes = Math.max(0, grossMinutes - breakMinutes);
          }
          await db.query(
            `UPDATE attendance_logs SET check_in_time=$1, check_out_time=$2, total_worked_minutes=$3, status=$4, updated_at=CURRENT_TIMESTAMP WHERE id=$5`,
            [checkIn.toISOString(), checkOut ? checkOut.toISOString() : null, workedMinutes, attendanceStatus, existingAttendance.id]
          );
        } else {
          const attendanceId = require('crypto').randomUUID();
          const checkIn = request.requestedCheckinTime ? new Date(request.requestedCheckinTime) : null;
          const checkOut = request.requestedCheckoutTime ? new Date(request.requestedCheckoutTime) : null;
          const workedMinutes = (checkIn && checkOut) ? Math.max(0, Math.round((checkOut.getTime() - checkIn.getTime()) / 60000)) : 0;
          await db.query(
            `INSERT INTO attendance_logs (id, user_id, date, check_in_time, check_out_time, status, shift_id, total_worked_minutes) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
            [attendanceId, request.userId, dateStr, checkIn?.toISOString() ?? null, checkOut?.toISOString() ?? null, attendanceStatus, shift?.id ?? null, workedMinutes]
          );
        }
      }

      const approvedMinutes = status === 'APPROVED' ? request.requestedMinutes : 0;
      await this.adjustmentRepo.reviewRequest(requestId, status as 'APPROVED' | 'REJECTED', approvedMinutes, hrComment, reviewerId);
      await AutomationJobsService.writeAuditHook(
        reviewerId, `REVIEW_ADJUSTMENT_${status}`, 'adjustment_requests', null,
        `HR/Admin reviewed adjustment ID: ${requestId} as ${status}. Comment: ${hrComment}`, ipAddress
      );
      return;
    }

    throw new AppError('Forbidden: You do not have permission to review this request.', 403);
  }
}
