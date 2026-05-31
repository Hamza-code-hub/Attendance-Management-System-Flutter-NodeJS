import { db } from '../config/db';
import crypto from 'crypto';

export interface DBAdjustmentRequest {
  id: string;
  userId: number;
  attendanceId: string | null;
  adjustmentType: 'MISSED_CHECKIN' | 'MISSED_CHECKOUT' | 'LATE_COMPENSATION' | 'EARLY_LEAVE' | 'CUSTOM' | 'TIME_ADJUSTMENT';
  requestedMinutes: number;
  approvedMinutes: number;
  requestedCheckinTime: string | null;
  requestedCheckoutTime: string | null;
  reason: string;
  status: 'PENDING' | 'APPROVED' | 'REJECTED';
  hrComment: string | null;
  managerApprovedAt?: string | null;
  managerApprovedBy?: number | null;
  reviewedBy: number | null;
  reviewedAt: string | null;
  createdAt: string;
  updatedAt: string;
  // Joins
  username?: string;
  firstName?: string;
  lastName?: string;
  departmentId?: number;
}

export class AdjustmentRepository {
  /**
   * Create a new adjustment request
   */
  async create(req: Omit<DBAdjustmentRequest, 'id' | 'approvedMinutes' | 'status' | 'hrComment' | 'reviewedBy' | 'reviewedAt' | 'createdAt' | 'updatedAt'>): Promise<string> {
    const id = crypto.randomUUID();
    const query = `
      INSERT INTO adjustment_requests (
        id, user_id, attendance_id, adjustment_type, requested_minutes, requested_checkin_time, requested_checkout_time, reason
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    `;
    await db.query(query, [
      id,
      req.userId,
      req.attendanceId,
      req.adjustmentType,
      req.requestedMinutes,
      req.requestedCheckinTime,
      req.requestedCheckoutTime,
      req.reason,
    ]);
    return id;
  }

  /**
   * Find request by ID
   */
  async findById(id: string): Promise<DBAdjustmentRequest | null> {
    const query = 'SELECT * FROM adjustment_requests WHERE id = $1';
    const res = await db.query(query, [id]);
    if (res.rows.length === 0) return null;
    return this.mapRow(res.rows[0]);
  }

  /**
   * Find request by user ID and date (to prevent duplicates)
   */
  async findByUserAndDate(userId: number, date: string): Promise<DBAdjustmentRequest | null> {
    const query = `
      SELECT * FROM adjustment_requests 
      WHERE user_id = $1 
      AND (
        (requested_checkin_time LIKE $2) OR 
        (requested_checkout_time LIKE $3) OR
        (attendance_id IN (SELECT id FROM attendance_logs WHERE user_id = $4 AND date = $5))
      )
    `;
    const datePattern = `${date}%`;
    const res = await db.query(query, [userId, datePattern, datePattern, userId, date]);
    if (res.rows.length === 0) return null;
    return this.mapRow(res.rows[0]);
  }

  /**
   * Fetch personal request history for an employee
   */
  async findHistoryByUser(userId: number): Promise<DBAdjustmentRequest[]> {
    const query = 'SELECT * FROM adjustment_requests WHERE user_id = $1 ORDER BY created_at DESC';
    const res = await db.query(query, [userId]);
    return res.rows.map(row => this.mapRow(row));
  }

  /**
   * Fetch pending requests for review, joined with user names.
   * submittedByRoles — when provided, only rows whose submitted_by_role is in this list are returned.
   * Passing undefined means "all roles" (Admin view).
   */
  async findPending(
    departmentId?: number,
    stage: 'manager' | 'hr' | 'all' = 'manager',
    submittedByRoles?: string[]
  ): Promise<DBAdjustmentRequest[]> {
    const params: any[] = [];
    let scopeWhere = '';
    if (departmentId) {
      params.push(departmentId);
      scopeWhere = `AND e.department_id = $${params.length}`;
    }

    const stageWhere = stage === 'all'
      ? ''
      : stage === 'manager'
        ? 'AND a.manager_approved_at IS NULL'
        : 'AND a.manager_approved_at IS NOT NULL';

    let roleWhere = '';
    if (submittedByRoles && submittedByRoles.length > 0) {
      const placeholders = submittedByRoles.map((_, i) => `$${params.length + 1 + i}`).join(', ');
      params.push(...submittedByRoles);
      roleWhere = `AND (a.submitted_by_role IS NULL OR a.submitted_by_role IN (${placeholders}))`;
    }

    const query = `
      SELECT a.*, u.username, e.first_name, e.last_name, e.department_id
      FROM adjustment_requests a
      JOIN users u ON u.id = a.user_id
      JOIN employees e ON e.id = u.employee_id
      WHERE a.status = 'PENDING' ${stageWhere} ${scopeWhere} ${roleWhere}
      ORDER BY a.created_at ASC
    `;
    const res = await db.query(query, params);
    return res.rows.map(row => {
      const mapped = this.mapRow(row);
      mapped.username = row.username;
      mapped.firstName = row.first_name;
      mapped.lastName = row.last_name;
      mapped.departmentId = row.department_id;
      return mapped;
    });
  }

  /**
   * Update request review decision
   */
  async reviewRequest(
    id: string,
    status: 'APPROVED' | 'REJECTED',
    approvedMinutes: number,
    hrComment: string | null,
    reviewedBy: number
  ): Promise<void> {
    const query = `
      UPDATE adjustment_requests
      SET status = $1,
          approved_minutes = $2,
          hr_comment = $3,
          reviewed_by = $4,
          reviewed_at = CURRENT_TIMESTAMP,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = $5
    `;
    await db.query(query, [status, approvedMinutes, hrComment, reviewedBy, id]);
  }

  async managerApprove(requestId: string, managerId: number): Promise<void> {
    await db.query(
      `UPDATE adjustment_requests
       SET manager_approved_at = CURRENT_TIMESTAMP, manager_approved_by = $1, updated_at = CURRENT_TIMESTAMP
       WHERE id = $2 AND status = 'PENDING' AND manager_approved_at IS NULL`,
      [managerId, requestId]
    );
  }

  private mapRow(row: any): DBAdjustmentRequest {
    return {
      id: row.id,
      userId: row.user_id,
      attendanceId: row.attendance_id,
      adjustmentType: row.adjustment_type,
      requestedMinutes: row.requested_minutes,
      approvedMinutes: row.approved_minutes,
      requestedCheckinTime: row.requested_checkin_time,
      requestedCheckoutTime: row.requested_checkout_time,
      reason: row.reason,
      status: row.status,
      hrComment: row.hr_comment,
      managerApprovedAt: row.manager_approved_at ?? null,
      managerApprovedBy: row.manager_approved_by ?? null,
      reviewedBy: row.reviewed_by,
      reviewedAt: row.reviewed_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }
}
