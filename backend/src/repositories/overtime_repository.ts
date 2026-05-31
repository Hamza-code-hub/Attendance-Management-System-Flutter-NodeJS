import { db } from '../config/db';
import crypto from 'crypto';

export interface DBOvertimeRequest {
  id: string;
  userId: number;
  attendanceId: string | null;
  requestDate: string;
  requestedMinutes: number;
  approvedMinutes: number;
  reason: string;
  status: 'PENDING' | 'APPROVED' | 'REJECTED' | 'PARTIAL';
  hrComment: string | null;
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

export class OvertimeRepository {
  /**
   * Create a new overtime request
   */
  async create(req: Omit<DBOvertimeRequest, 'id' | 'approvedMinutes' | 'status' | 'hrComment' | 'reviewedBy' | 'reviewedAt' | 'createdAt' | 'updatedAt'>): Promise<string> {
    const id = crypto.randomUUID();
    const query = `
      INSERT INTO overtime_requests (
        id, user_id, attendance_id, request_date, requested_minutes, reason
      )
      VALUES ($1, $2, $3, $4, $5, $6)
    `;
    await db.query(query, [
      id,
      req.userId,
      req.attendanceId,
      req.requestDate,
      req.requestedMinutes,
      req.reason,
    ]);
    return id;
  }

  /**
   * Find request by ID
   */
  async findById(id: string): Promise<DBOvertimeRequest | null> {
    const query = 'SELECT * FROM overtime_requests WHERE id = $1';
    const res = await db.query(query, [id]);
    if (res.rows.length === 0) return null;
    return this.mapRow(res.rows[0]);
  }

  /**
   * Find request by user ID and date (to prevent duplicates)
   */
  async findByUserAndDate(userId: number, date: string): Promise<DBOvertimeRequest | null> {
    const query = 'SELECT * FROM overtime_requests WHERE user_id = $1 AND request_date = $2';
    const res = await db.query(query, [userId, date]);
    if (res.rows.length === 0) return null;
    return this.mapRow(res.rows[0]);
  }

  /**
   * Fetch personal request history for an employee
   */
  async findHistoryByUser(userId: number): Promise<DBOvertimeRequest[]> {
    const query = 'SELECT * FROM overtime_requests WHERE user_id = $1 ORDER BY request_date DESC, created_at DESC';
    const res = await db.query(query, [userId]);
    return res.rows.map(row => this.mapRow(row));
  }

  /**
   * Fetch pending overtime requests for review.
   * submittedByRoles — when provided only rows with matching submitted_by_role are returned.
   * Passing undefined means Admin view (no role restriction).
   */
  async findPending(departmentId?: number, submittedByRoles?: string[]): Promise<DBOvertimeRequest[]> {
    const params: any[] = [];
    let scopeWhere = '';
    if (departmentId) {
      params.push(departmentId);
      scopeWhere = `AND e.department_id = $${params.length}`;
    }

    let roleWhere = '';
    if (submittedByRoles && submittedByRoles.length > 0) {
      const placeholders = submittedByRoles.map((_, i) => `$${params.length + 1 + i}`).join(', ');
      params.push(...submittedByRoles);
      roleWhere = `AND (o.submitted_by_role IS NULL OR o.submitted_by_role IN (${placeholders}))`;
    }

    const query = `
      SELECT o.*, u.username, e.first_name, e.last_name, e.department_id
      FROM overtime_requests o
      JOIN users u ON u.id = o.user_id
      LEFT JOIN employees e ON e.id = u.employee_id
      WHERE o.status = 'PENDING' ${scopeWhere} ${roleWhere}
      ORDER BY o.created_at ASC
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
    status: 'APPROVED' | 'REJECTED' | 'PARTIAL',
    approvedMinutes: number,
    hrComment: string | null,
    reviewedBy: number
  ): Promise<void> {
    const query = `
      UPDATE overtime_requests
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

  private mapRow(row: any): DBOvertimeRequest {
    return {
      id: row.id,
      userId: row.user_id,
      attendanceId: row.attendance_id,
      requestDate: row.request_date,
      requestedMinutes: row.requested_minutes,
      approvedMinutes: row.approved_minutes,
      reason: row.reason,
      status: row.status,
      hrComment: row.hr_comment,
      reviewedBy: row.reviewed_by,
      reviewedAt: row.reviewed_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }
}
