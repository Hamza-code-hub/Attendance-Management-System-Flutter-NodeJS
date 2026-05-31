import { db } from '../config/db';

export class ReportRepository {

  async getAttendanceReport(filters: {
    dateFrom: string;
    dateTo: string;
    employeeId?: number;
    departmentId?: number;
    shiftId?: number;
    status?: string;
    page?: number;
    limit?: number;
  }): Promise<{ data: any[]; total: number }> {
    const params: any[] = [filters.dateFrom, filters.dateTo];
    let where = `WHERE al.date >= $1 AND al.date <= $2`;
    if (filters.employeeId) { params.push(filters.employeeId); where += ` AND e.id = $${params.length}`; }
    if (filters.departmentId) { params.push(filters.departmentId); where += ` AND e.department_id = $${params.length}`; }
    if (filters.shiftId) { params.push(filters.shiftId); where += ` AND al.shift_id = $${params.length}`; }
    if (filters.status) { params.push(filters.status); where += ` AND al.status = $${params.length}`; }

    const cntRes = await db.query(
      `SELECT COUNT(*) as count FROM attendance_logs al
       INNER JOIN users u ON u.id = al.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN shifts s ON s.id = al.shift_id
       ${where}`, params
    );
    const total = cntRes.rows[0]?.count ?? 0;

    const page = filters.page ?? 1;
    const limit = filters.limit ?? 50;
    const offset = (page - 1) * limit;
    params.push(limit, offset);

    const dataRes = await db.query(
      `SELECT al.id, al.date, al.check_in_time, al.check_out_time, al.status,
              al.total_worked_minutes, COALESCE(al.overtime_minutes, 0) as overtime_minutes,
              e.employee_code, e.first_name || ' ' || e.last_name as employee_name,
              e.designation,
              d.department_name,
              s.shift_name, s.shift_start, s.shift_end,
              (SELECT SUM(bl.duration_minutes) FROM break_logs bl
               WHERE bl.attendance_id = al.id AND bl.break_end IS NOT NULL) as total_break_minutes,
              (SELECT COUNT(*) FROM break_logs bl WHERE bl.attendance_id = al.id) as break_count
       FROM attendance_logs al
       INNER JOIN users u ON u.id = al.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN shifts s ON s.id = al.shift_id
       ${where}
       ORDER BY al.date DESC, e.first_name ASC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    return { data: dataRes.rows, total };
  }

  async getOvertimeReport(filters: {
    dateFrom: string;
    dateTo: string;
    employeeId?: number;
    departmentId?: number;
    status?: string;
    page?: number;
    limit?: number;
  }): Promise<{ data: any[]; total: number }> {
    const params: any[] = [filters.dateFrom, filters.dateTo];
    let where = `WHERE ot.request_date >= $1 AND ot.request_date <= $2`;
    if (filters.employeeId) { params.push(filters.employeeId); where += ` AND e.id = $${params.length}`; }
    if (filters.departmentId) { params.push(filters.departmentId); where += ` AND e.department_id = $${params.length}`; }
    if (filters.status) { params.push(filters.status); where += ` AND ot.status = $${params.length}`; }

    const cntRes = await db.query(
      `SELECT COUNT(*) as count FROM overtime_requests ot
       INNER JOIN users u ON u.id = ot.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       ${where}`, params
    );
    const total = cntRes.rows[0]?.count ?? 0;

    const page = filters.page ?? 1;
    const limit = filters.limit ?? 50;
    const offset = (page - 1) * limit;
    params.push(limit, offset);

    const dataRes = await db.query(
      `SELECT ot.id, ot.request_date, ot.requested_minutes, ot.approved_minutes,
              ot.reason, ot.status, ot.hr_comment, ot.reviewed_at, ot.created_at,
              e.employee_code, e.first_name || ' ' || e.last_name as employee_name,
              e.designation, d.department_name,
              r.first_name || ' ' || r.last_name as reviewer_name
       FROM overtime_requests ot
       INNER JOIN users u ON u.id = ot.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN users ru ON ru.id = ot.reviewed_by
       LEFT JOIN employees r ON r.id = ru.employee_id
       ${where}
       ORDER BY ot.request_date DESC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    return { data: dataRes.rows, total };
  }

  async getAdjustmentReport(filters: {
    dateFrom: string;
    dateTo: string;
    employeeId?: number;
    departmentId?: number;
    status?: string;
    page?: number;
    limit?: number;
  }): Promise<{ data: any[]; total: number }> {
    const params: any[] = [filters.dateFrom, filters.dateTo];
    let where = `WHERE ar.created_at >= $1 AND ar.created_at <= $2`;
    if (filters.employeeId) { params.push(filters.employeeId); where += ` AND e.id = $${params.length}`; }
    if (filters.departmentId) { params.push(filters.departmentId); where += ` AND e.department_id = $${params.length}`; }
    if (filters.status) { params.push(filters.status); where += ` AND ar.status = $${params.length}`; }

    const cntRes = await db.query(
      `SELECT COUNT(*) as count FROM adjustment_requests ar
       INNER JOIN users u ON u.id = ar.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       ${where}`, params
    );
    const total = cntRes.rows[0]?.count ?? 0;

    const page = filters.page ?? 1;
    const limit = filters.limit ?? 50;
    const offset = (page - 1) * limit;
    params.push(limit, offset);

    const dataRes = await db.query(
      `SELECT ar.id, ar.adjustment_type, ar.requested_minutes, ar.approved_minutes,
              ar.requested_checkin_time, ar.requested_checkout_time,
              ar.reason, ar.status, ar.hr_comment, ar.reviewed_at, ar.created_at,
              e.employee_code, e.first_name || ' ' || e.last_name as employee_name,
              e.designation, d.department_name
       FROM adjustment_requests ar
       INNER JOIN users u ON u.id = ar.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       ${where}
       ORDER BY ar.created_at DESC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    return { data: dataRes.rows, total };
  }

  async getLateReport(filters: {
    dateFrom: string;
    dateTo: string;
    employeeId?: number;
    departmentId?: number;
    page?: number;
    limit?: number;
  }): Promise<{ data: any[]; total: number }> {
    const params: any[] = [filters.dateFrom, filters.dateTo, 'LATE'];
    let where = `WHERE al.date >= $1 AND al.date <= $2 AND al.status = $3`;
    if (filters.employeeId) { params.push(filters.employeeId); where += ` AND e.id = $${params.length}`; }
    if (filters.departmentId) { params.push(filters.departmentId); where += ` AND e.department_id = $${params.length}`; }

    return this.getAttendanceReport({ ...filters, status: 'LATE' });
  }

  async getBreakReport(filters: {
    dateFrom: string;
    dateTo: string;
    employeeId?: number;
    departmentId?: number;
    page?: number;
    limit?: number;
  }): Promise<{ data: any[]; total: number }> {
    const params: any[] = [filters.dateFrom, filters.dateTo];
    let where = `WHERE al.date >= $1 AND al.date <= $2 AND bl.id IS NOT NULL`;
    if (filters.employeeId) { params.push(filters.employeeId); where += ` AND e.id = $${params.length}`; }
    if (filters.departmentId) { params.push(filters.departmentId); where += ` AND e.department_id = $${params.length}`; }

    const cntRes = await db.query(
      `SELECT COUNT(*) as count FROM attendance_logs al
       INNER JOIN users u ON u.id = al.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN break_logs bl ON bl.attendance_id = al.id
       ${where}`, params
    );
    const total = cntRes.rows[0]?.count ?? 0;

    const page = filters.page ?? 1;
    const limit = filters.limit ?? 50;
    const offset = (page - 1) * limit;
    params.push(limit, offset);

    const dataRes = await db.query(
      `SELECT bl.id, al.date, bl.break_start, bl.break_end, bl.duration_minutes,
              e.employee_code, e.first_name || ' ' || e.last_name as employee_name,
              e.designation, d.department_name, s.shift_name
       FROM attendance_logs al
       INNER JOIN users u ON u.id = al.user_id
       INNER JOIN employees e ON e.id = u.employee_id
       LEFT JOIN departments d ON d.id = e.department_id
       LEFT JOIN shifts s ON s.id = al.shift_id
       INNER JOIN break_logs bl ON bl.attendance_id = al.id
       ${where}
       ORDER BY al.date DESC, bl.break_start DESC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    return { data: dataRes.rows, total };
  }

  // Raw data for exports (no pagination)
  async getAllAttendanceForExport(filters: {
    dateFrom: string;
    dateTo: string;
    employeeId?: number;
    departmentId?: number;
    shiftId?: number;
    status?: string;
  }): Promise<any[]> {
    const result = await this.getAttendanceReport({ ...filters, page: 1, limit: 10000 });
    return result.data;
  }

  async getAllOvertimeForExport(filters: any): Promise<any[]> {
    const result = await this.getOvertimeReport({ ...filters, page: 1, limit: 10000 });
    return result.data;
  }

  async getAllAdjustmentsForExport(filters: any): Promise<any[]> {
    const result = await this.getAdjustmentReport({ ...filters, page: 1, limit: 10000 });
    return result.data;
  }

  async getAllBreaksForExport(filters: any): Promise<any[]> {
    const result = await this.getBreakReport({ ...filters, page: 1, limit: 10000 });
    return result.data;
  }

  // ── Monthly Matrix: row per employee, column per day ──────────────────────
  async getMonthlyMatrixData(month: string, departmentId?: number): Promise<{
    employees: any[];
    attendanceMap: Map<number, Map<string, any>>;
    dates: string[];
    deptName: string;
  }> {
    // Derive first + last day of the requested month
    const [year, mon] = month.split('-').map(Number);
    const firstDay = `${month}-01`;
    const lastDayDate = new Date(year, mon, 0); // day 0 of next month = last day of this month
    const lastDay = `${month}-${String(lastDayDate.getDate()).padStart(2, '0')}`;

    // Build all calendar dates for the month
    const dates: string[] = [];
    for (let day = 1; day <= lastDayDate.getDate(); day++) {
      dates.push(`${month}-${String(day).padStart(2, '0')}`);
    }

    // Fetch employees
    const empParams: any[] = [];
    let deptWhere = '';
    if (departmentId) {
      empParams.push(departmentId);
      deptWhere = `AND e.department_id = $${empParams.length}`;
    }
    const empRes = await db.query(
      `SELECT e.id, e.employee_code,
              e.first_name || ' ' || e.last_name AS full_name,
              d.department_name, d.id AS dept_id
       FROM employees e
       LEFT JOIN users u ON u.employee_id = e.id
       LEFT JOIN departments d ON d.id = e.department_id
       WHERE e.employment_status = 'ACTIVE' ${deptWhere}
       ORDER BY d.department_name, e.last_name, e.first_name`,
      empParams
    );

    // Fetch all attendance records for the month (with optional dept filter)
    const attParams: any[] = [firstDay, lastDay];
    let attDeptWhere = '';
    if (departmentId) {
      attParams.push(departmentId);
      attDeptWhere = `AND e.department_id = $${attParams.length}`;
    }
    const attRes = await db.query(
      `SELECT e.id AS employee_id, al.date,
              al.check_in_time, al.check_out_time,
              al.status, al.total_worked_minutes,
              COALESCE((
                SELECT SUM(bl.duration_minutes)
                FROM break_logs bl
                WHERE bl.attendance_id = al.id AND bl.break_end IS NOT NULL
              ), 0) AS total_break_minutes
       FROM attendance_logs al
       JOIN users u ON u.id = al.user_id
       JOIN employees e ON e.id = u.employee_id
       WHERE al.date >= $1 AND al.date <= $2 ${attDeptWhere}
       ORDER BY e.id, al.date`,
      attParams
    );

    // Build employeeId → date → record map
    const attendanceMap = new Map<number, Map<string, any>>();
    const dateKey = (value: any) => {
      if (value instanceof Date) return value.toISOString().slice(0, 10);
      return String(value).slice(0, 10);
    };

    for (const row of attRes.rows) {
      if (!attendanceMap.has(row.employee_id)) {
        attendanceMap.set(row.employee_id, new Map());
      }
      attendanceMap.get(row.employee_id)!.set(dateKey(row.date), row);
    }

    // Get dept name for subtitle
    let deptName = 'All Departments';
    if (departmentId && empRes.rows.length > 0) {
      deptName = empRes.rows[0].department_name || 'All Departments';
    }

    return { employees: empRes.rows, attendanceMap, dates, deptName };
  }
}
