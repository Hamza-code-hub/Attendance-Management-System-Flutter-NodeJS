import { OvertimeRepository, DBOvertimeRequest } from '../repositories/overtime_repository';
import { AttendanceRepository } from '../repositories/attendance_repository';
import { AutomationJobsService } from './automation_jobs';
import { AppError } from '../middleware/error_handler';
import { db } from '../config/db';
import { logger } from '../config/logger';

export class OvertimeService {
  private overtimeRepo = new OvertimeRepository();
  private attendanceRepo = new AttendanceRepository();

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
    if (!departmentId) return undefined; // No dept — unrestricted
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
   * Request overtime hours
   */
  async createRequest(
    userId: number,
    requestDate: string,
    requestedMinutes: number,
    reason: string,
    ipAddress: string,
    submitterRoles: string[] = []
  ): Promise<string> {
    // Basic formatting validations
    if (!requestDate) {
      throw new AppError('Bad Request: Request date is required', 400);
    }
    if (!requestedMinutes || requestedMinutes <= 0) {
      throw new AppError('Bad Request: Requested minutes must be a positive integer', 400);
    }
    if (!reason || reason.trim() === '') {
      throw new AppError('Bad Request: A reason is required to submit a request', 400);
    }

    // Rule 1: Cannot create overtime request if attendance record is missing for the date
    const attendance = await this.attendanceRepo.findTodayRecord(userId, requestDate);
    if (!attendance) {
      throw new AppError('Conflict: No attendance check-in record found for the requested date. You must clock in first.', 400);
    }

    // Rule 2: Enforce a max allowed minutes limit (e.g. 480 minutes / 8 hours)
    const MAX_ALLOWED_MINUTES = 480;
    if (requestedMinutes > MAX_ALLOWED_MINUTES) {
      throw new AppError(`Validation Error: Requested minutes exceed the maximum limit of ${MAX_ALLOWED_MINUTES} minutes (8 hours).`, 400);
    }

    // Rule 3: Block duplicate requests for same day/attendance
    const existing = await this.overtimeRepo.findByUserAndDate(userId, requestDate);
    if (existing) {
      throw new AppError('Conflict: A request for this day already exists. Duplicate submissions are blocked.', 400);
    }

    // Rule 4: Overtime is only permitted if employee's shift allows it
    const shift = await this.attendanceRepo.getUserShift(userId);
    if (!shift || !shift.allowOvertime) {
      throw new AppError('Forbidden: Overtime requests are disabled for your current shift schedule.', 403);
    }

    // Insert request
    const requestId = await this.overtimeRepo.create({
      userId,
      attendanceId: attendance.id,
      requestDate,
      requestedMinutes,
      reason,
    });

    const isManager = submitterRoles.includes('Manager') && !submitterRoles.includes('HR') && !submitterRoles.includes('Admin');
    const isHR = submitterRoles.includes('HR') && !submitterRoles.includes('Admin');
    const submittedByRole = isHR ? 'HR' : isManager ? 'Manager' : 'Employee';

    await db.query(`UPDATE overtime_requests SET submitted_by_role = $1 WHERE id = $2`, [submittedByRole, requestId]);

    if (isManager) {
      // Manager's requests skip straight to HR queue (no manager approval needed)
      logger.info(`[OT Service] Manager request ${requestId} auto-routed to HR queue`);
    }

    // Write audit log
    await AutomationJobsService.writeAuditHook(
      userId,
      'CREATE_OVERTIME_REQUEST',
      'overtime_requests',
      null, // ID is string, table has INTEGER for entity_id in migrations, so pass null or let it log in description
      `Submitted overtime request of ${requestedMinutes} minutes for date ${requestDate}. ID: ${requestId}`,
      ipAddress
    );

    return requestId;
  }

  /**
   * Fetch personal request history
   */
  async getHistory(userId: number): Promise<DBOvertimeRequest[]> {
    return await this.overtimeRepo.findHistoryByUser(userId);
  }

  /**
   * Fetch pending overtime requests for the given reviewer role.
   *
   * Routing rules:
   *  • Manager  — sees Employee overtime in their dept only
   *  • HR       — sees Employee + Manager overtime (no dept restriction)
   *  • Admin    — sees everything (including HR's overtime)
   */
  async getPendingRequests(reviewerId: number, roles: string[]): Promise<DBOvertimeRequest[]> {
    const isAdmin = roles.includes('Admin');
    const isHR    = roles.includes('HR') && !isAdmin;

    if (isAdmin) {
      return await this.overtimeRepo.findPending(undefined, undefined);
    }

    if (isHR) {
      return await this.overtimeRepo.findPending(undefined, ['Employee', 'Manager']);
    }

    // Manager: Employee requests in their department
    const departmentId = await this.getReviewerDepartmentId(reviewerId, roles).catch(() => undefined);
    return await this.overtimeRepo.findPending(departmentId, ['Employee']);
  }

  /**
   * Review (Approve/Reject/Partial) overtime request
   */
  async reviewRequest(
    requestId: string,
    reviewerId: number,
    roles: string[],
    status: 'APPROVED' | 'REJECTED' | 'PARTIAL',
    approvedMinutes: number,
    hrComment: string | null,
    ipAddress: string
  ): Promise<void> {
    // Find request first
    const request = await this.overtimeRepo.findById(requestId);
    if (!request) {
      throw new AppError('Not Found: Overtime request not found', 404);
    }

    // Rule 5: Request already reviewed - cannot modify
    if (request.status !== 'PENDING') {
      throw new AppError('Conflict: This request has already been reviewed and cannot be modified.', 400);
    }

    await this.assertReviewScope(request.userId, reviewerId, roles);

    // Verify input status
    if (!['APPROVED', 'REJECTED', 'PARTIAL'].includes(status)) {
      throw new AppError('Bad Request: Invalid approval status. Allowed values are APPROVED, REJECTED, PARTIAL', 400);
    }

    // Verify minutes
    let finalApprovedMinutes = 0;
    if (status === 'APPROVED') {
      finalApprovedMinutes = request.requestedMinutes;
    } else if (status === 'PARTIAL') {
      if (approvedMinutes <= 0 || approvedMinutes > request.requestedMinutes) {
        throw new AppError(`Bad Request: Approved minutes for partial approval must be greater than 0 and less than requested minutes (${request.requestedMinutes})`, 400);
      }
      finalApprovedMinutes = approvedMinutes;
    }

    // Update DB
    await this.overtimeRepo.reviewRequest(requestId, status, finalApprovedMinutes, hrComment, reviewerId);

    // Write audit log
    await AutomationJobsService.writeAuditHook(
      reviewerId,
      `REVIEW_OVERTIME_${status}`,
      'overtime_requests',
      null,
      `Reviewed overtime request ID: ${requestId} status as ${status}. Approved minutes: ${finalApprovedMinutes}. HR Comment: ${hrComment}`,
      ipAddress
    );
  }
}
