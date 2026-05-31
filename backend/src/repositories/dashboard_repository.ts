import { db } from '../config/db';

export class DashboardRepository {

  async getPresentCount(date: string): Promise<number> {
    const res = await db.query(
      `SELECT COUNT(*) as count FROM attendance_logs
       WHERE date = $1 AND check_in_time IS NOT NULL AND check_out_time IS NULL`,
      [date]
    );
    return res.rows[0]?.count ?? 0;
  }

  async getCheckedOutCount(date: string): Promise<number> {
    const res = await db.query(
      `SELECT COUNT(*) as count FROM attendance_logs
       WHERE date = $1 AND check_out_time IS NOT NULL`,
      [date]
    );
    return res.rows[0]?.count ?? 0;
  }

  async getActiveBreaksCount(date: string): Promise<number> {
    const res = await db.query(
      `SELECT COUNT(*) as count FROM break_logs bl
       INNER JOIN attendance_logs al ON al.id = bl.attendance_id
       WHERE al.date = $1 AND bl.break_end IS NULL`,
      [date]
    );
    return res.rows[0]?.count ?? 0;
  }

  async getLateCount(date: string, departmentId?: number): Promise<number> {
    let sql = `SELECT COUNT(*) as count FROM attendance_logs al
               INNER JOIN users u ON u.id = al.user_id
               INNER JOIN employees e ON e.id = u.employee_id
               WHERE al.date = $1 AND al.status = 'LATE'`;
    const params: any[] = [date];
    if (departmentId) {
      sql += ` AND e.department_id = $2`;
      params.push(departmentId);
    }
    const res = await db.query(sql, params);
    return res.rows[0]?.count ?? 0;
  }

  async getMissingCheckoutsCount(date: string): Promise<number> {
    const res = await db.query(
      `SELECT COUNT(*) as count FROM attendance_logs
       WHERE date = $1 AND check_in_time IS NOT NULL AND check_out_time IS NULL
       AND status = 'MISSED_CHECKOUT'`,
      [date]
    );
    return res.rows[0]?.count ?? 0;
  }

  async getPendingOvertimeCount(): Promise<number> {
    const res = await db.query(
      `SELECT COUNT(*) as count FROM overtime_requests WHERE status = 'PENDING'`
    );
    return res.rows[0]?.count ?? 0;
  }

  async getPendingAdjustmentsCount(): Promise<number> {
    const res = await db.query(
      `SELECT COUNT(*) as count FROM adjustment_requests WHERE status = 'PENDING'`
    );
    return res.rows[0]?.count ?? 0;
  }

  async getTotalActiveEmployees(): Promise<number> {
    const res = await db.query(
      `SELECT COUNT(*) as count FROM employees WHERE employment_status = 'ACTIVE'`
    );
    return res.rows[0]?.count ?? 0;
  }

  async getPresentEmployees(date: string, filters: {
    employeeId?: number;
    departmentId?: number;
    page?: number;
    limit?: number;
  }): Promise<{ data: any[]; total: number }> {
    const page = filters.page ?? 1;
    const limit = filters.limit ?? 20;
    const offset = (page - 1) * limit;
    const params: any[] = [date];

    let where = `WHERE al.date = $1 AND al.check_in_time IS NOT NULL`;
    if (filters.employeeId) {
      params.push(filters.employeeId);
      where += ` AND e.id = $${params.length}`;
    }
    if (filters.departmentId) {
      params.push(filters.departmentId);
      where += ` AND e.department_id = $${params.length}`;
    }

    const countRes = await db.query(
      `SELECT COUNT(*) as count
       FROM attendance_logs al
       INNER JOIN users u ON u.id = al.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN shifts s ON s.id = al.shift_id
       ${where}`,
      params
    );
    const total = countRes.rows[0]?.count ?? 0;

    params.push(limit, offset);
    const dataRes = await db.query(
      `SELECT al.id, al.date, al.check_in_time, al.check_out_time, al.status,
              al.total_worked_minutes,
              e.id as employee_id, e.employee_code, e.first_name || ' ' || e.last_name as employee_name,
              e.designation,
              d.department_name,
              s.shift_name, s.shift_start, s.shift_end
       FROM attendance_logs al
       INNER JOIN users u ON u.id = al.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN shifts s ON s.id = al.shift_id
       ${where}
       ORDER BY al.check_in_time DESC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );

    return { data: dataRes.rows, total };
  }

  async getLateEmployees(date: string, filters: {
    employeeId?: number;
    departmentId?: number;
    page?: number;
    limit?: number;
  }): Promise<{ data: any[]; total: number }> {
    const page = filters.page ?? 1;
    const limit = filters.limit ?? 20;
    const offset = (page - 1) * limit;
    const params: any[] = [date];

    let where = `WHERE al.date = $1 AND al.status = 'LATE'`;
    if (filters.employeeId) {
      params.push(filters.employeeId);
      where += ` AND e.id = $${params.length}`;
    }
    if (filters.departmentId) {
      params.push(filters.departmentId);
      where += ` AND e.department_id = $${params.length}`;
    }

    const countRes = await db.query(
      `SELECT COUNT(*) as count
       FROM attendance_logs al
       INNER JOIN users u ON u.id = al.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       ${where}`,
      params
    );
    const total = countRes.rows[0]?.count ?? 0;

    params.push(limit, offset);
    const dataRes = await db.query(
      `SELECT al.id, al.date, al.check_in_time, al.check_out_time, al.status,
              e.id as employee_id, e.employee_code, e.first_name || ' ' || e.last_name as employee_name,
              e.designation, d.department_name,
              s.shift_name, s.shift_start, s.grace_minutes
       FROM attendance_logs al
       INNER JOIN users u ON u.id = al.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN shifts s ON s.id = al.shift_id
       ${where}
       ORDER BY al.check_in_time ASC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );

    return { data: dataRes.rows, total };
  }

  async getPendingApprovals(filters: {
    type?: 'overtime' | 'adjustment';
    employeeId?: number;
    departmentId?: number;
    dateFrom?: string;
    dateTo?: string;
    page?: number;
    limit?: number;
  }): Promise<{ data: any[]; total: number }> {
    const page = filters.page ?? 1;
    const limit = filters.limit ?? 20;
    const offset = (page - 1) * limit;

    const results: any[] = [];
    let total = 0;

    if (!filters.type || filters.type === 'overtime') {
      const params: any[] = ['PENDING'];
      let where = `WHERE ot.status = $1`;
      if (filters.employeeId) { params.push(filters.employeeId); where += ` AND e.id = $${params.length}`; }
      if (filters.departmentId) { params.push(filters.departmentId); where += ` AND e.department_id = $${params.length}`; }
      if (filters.dateFrom) { params.push(filters.dateFrom); where += ` AND ot.request_date >= $${params.length}`; }
      if (filters.dateTo) { params.push(filters.dateTo); where += ` AND ot.request_date <= $${params.length}`; }

      const cntRes = await db.query(
        `SELECT COUNT(*) as count FROM overtime_requests ot
         INNER JOIN users u ON u.id = ot.user_id
         INNER JOIN employees e ON e.id = u.employee_id
         ${where}`, params
      );
      total += cntRes.rows[0]?.count ?? 0;

      const dataRes = await db.query(
        `SELECT ot.id, 'overtime' as type, ot.request_date as date, ot.requested_minutes,
                ot.reason, ot.status, ot.created_at,
                e.id as employee_id, e.employee_code, e.first_name || ' ' || e.last_name as employee_name,
                d.department_name
         FROM overtime_requests ot
         INNER JOIN users u ON u.id = ot.user_id
         INNER JOIN employees e ON e.id = u.employee_id
         LEFT JOIN departments d ON d.id = e.department_id
         ${where}
         ORDER BY ot.created_at DESC`, params
      );
      results.push(...dataRes.rows.map(r => ({ ...r, requestedMinutes: r.requested_minutes })));
    }

    if (!filters.type || filters.type === 'adjustment') {
      const params: any[] = ['PENDING'];
      let where = `WHERE ar.status = $1`;
      if (filters.employeeId) { params.push(filters.employeeId); where += ` AND e.id = $${params.length}`; }
      if (filters.departmentId) { params.push(filters.departmentId); where += ` AND e.department_id = $${params.length}`; }
      if (filters.dateFrom) { params.push(filters.dateFrom); where += ` AND ar.created_at >= $${params.length}`; }
      if (filters.dateTo) { params.push(filters.dateTo); where += ` AND ar.created_at <= $${params.length}`; }

      const cntRes = await db.query(
        `SELECT COUNT(*) as count FROM adjustment_requests ar
         INNER JOIN users u ON u.id = ar.user_id
         INNER JOIN employees e ON e.id = u.employee_id
         ${where}`, params
      );
      total += cntRes.rows[0]?.count ?? 0;

      const dataRes = await db.query(
        `SELECT ar.id, 'adjustment' as type, ar.created_at as date,
                ar.adjustment_type, ar.requested_minutes, ar.reason, ar.status, ar.created_at,
                ar.requested_checkin_time, ar.requested_checkout_time,
                e.id as employee_id, e.employee_code, e.first_name || ' ' || e.last_name as employee_name,
                d.department_name
         FROM adjustment_requests ar
         INNER JOIN users u ON u.id = ar.user_id
         INNER JOIN employees e ON e.id = u.employee_id
         LEFT JOIN departments d ON d.id = e.department_id
         ${where}
         ORDER BY ar.created_at DESC`, params
      );
      results.push(...dataRes.rows.map(r => ({ ...r, requestedMinutes: r.requested_minutes })));
    }

    // Sort combined results by date
    results.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());

    const paginated = results.slice(offset, offset + limit);
    return { data: paginated, total };
  }

  async getAttendanceMonitor(date: string, filters: {
    employeeId?: number;
    departmentId?: number;
    status?: string;
    page?: number;
    limit?: number;
  }): Promise<{ data: any[]; total: number }> {
    const page = filters.page ?? 1;
    const limit = filters.limit ?? 25;
    const offset = (page - 1) * limit;
    const params: any[] = [date];

    let where = `WHERE al.date = $1`;
    if (filters.employeeId) { params.push(filters.employeeId); where += ` AND e.id = $${params.length}`; }
    if (filters.departmentId) { params.push(filters.departmentId); where += ` AND e.department_id = $${params.length}`; }
    if (filters.status) { params.push(filters.status); where += ` AND al.status = $${params.length}`; }

    const countRes = await db.query(
      `SELECT COUNT(*) as count
       FROM attendance_logs al
       INNER JOIN users u ON u.id = al.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       ${where}`, params
    );
    const total = countRes.rows[0]?.count ?? 0;

    params.push(limit, offset);
    const dataRes = await db.query(
      `SELECT al.id, al.date, al.check_in_time, al.check_out_time, al.status,
              al.total_worked_minutes,
              e.id as employee_id, e.employee_code,
              e.first_name || ' ' || e.last_name as employee_name,
              e.designation, d.department_name,
              s.shift_name, s.shift_start, s.shift_end, s.grace_minutes,
              (SELECT COUNT(*) FROM break_logs bl WHERE bl.attendance_id = al.id) as break_count,
              (SELECT SUM(bl.duration_minutes) FROM break_logs bl WHERE bl.attendance_id = al.id AND bl.break_end IS NOT NULL) as total_break_minutes
       FROM attendance_logs al
       INNER JOIN users u ON u.id = al.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN shifts s ON s.id = al.shift_id
       ${where}
       ORDER BY al.check_in_time DESC NULLS LAST
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    return { data: dataRes.rows, total };
  }

  async getShiftMonitor(date: string): Promise<any[]> {
    const res = await db.query(
      `SELECT s.id, s.shift_name, s.shift_start, s.shift_end, s.grace_minutes,
              s.night_shift_enabled, s.allow_overtime,
              COUNT(DISTINCT e.id) as total_employees,
              COUNT(DISTINCT CASE WHEN al.date = $1 AND al.check_in_time IS NOT NULL THEN al.user_id END) as present_today,
              COUNT(DISTINCT CASE WHEN al.date = $1 AND al.status = 'LATE' THEN al.user_id END) as late_today,
              COUNT(DISTINCT CASE WHEN al.date = $1 AND al.check_out_time IS NOT NULL THEN al.user_id END) as checked_out_today
       FROM shifts s
       LEFT JOIN employees e ON e.shift_id = s.id AND e.employment_status = 'ACTIVE'
       LEFT JOIN users u ON u.employee_id = e.id
       LEFT JOIN attendance_logs al ON al.user_id = u.id
       WHERE s.active = 1
       GROUP BY s.id
       ORDER BY s.shift_start`,
      [date]
    );
    return res.rows;
  }

  async getEmployeeDirectory(filters: {
    search?: string;
    departmentId?: number;
    shiftId?: number;
    status?: string;
    page?: number;
    limit?: number;
  }): Promise<{ data: any[]; total: number }> {
    const page = filters.page ?? 1;
    const limit = filters.limit ?? 25;
    const offset = (page - 1) * limit;
    const params: any[] = [];

    const conditions: string[] = [];
    if (filters.status) { params.push(filters.status); conditions.push(`e.employment_status = $${params.length}`); }
    if (filters.departmentId) { params.push(filters.departmentId); conditions.push(`e.department_id = $${params.length}`); }
    if (filters.shiftId) { params.push(filters.shiftId); conditions.push(`e.shift_id = $${params.length}`); }
    if (filters.search) {
      params.push(`%${filters.search}%`);
      conditions.push(`(e.first_name || ' ' || e.last_name LIKE $${params.length} OR e.employee_code LIKE $${params.length} OR u.email LIKE $${params.length})`);
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const cntRes = await db.query(
      `SELECT COUNT(*) as count FROM employees e
       LEFT JOIN users u ON u.employee_id = e.id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN shifts s ON s.id = e.shift_id
       ${where}`, params
    );
    const total = cntRes.rows[0]?.count ?? 0;

    params.push(limit, offset);
    const dataRes = await db.query(
      `SELECT e.id, e.employee_code, e.first_name || ' ' || e.last_name as employee_name,
              e.designation, e.phone, e.joining_date, e.employment_status,
              d.id as department_id, d.department_name,
              s.id as shift_id, s.shift_name, s.shift_start, s.shift_end,
              u.email, u.username, u.status as user_status, u.last_login
       FROM employees e
       LEFT JOIN users u ON u.employee_id = e.id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN shifts s ON s.id = e.shift_id
       ${where}
       ORDER BY e.first_name ASC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    return { data: dataRes.rows, total };
  }
}
