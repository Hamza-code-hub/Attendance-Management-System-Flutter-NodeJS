import { Response, NextFunction } from 'express';
import { CustomRequest } from '../middleware/auth';
import { DashboardService } from '../services/dashboard_service';
import { AppError } from '../middleware/error_handler';
import { db } from '../config/db';

export class DashboardController {
  private svc = new DashboardService();

  private async scopedDepartmentId(req: CustomRequest, requestedDepartmentId?: number): Promise<number | undefined> {
    const roles = req.user?.roles ?? [];
    if (roles.includes('Admin') || roles.includes('HR')) return requestedDepartmentId;
    if (!roles.includes('Manager')) return requestedDepartmentId;

    const res = await db.query(
      `SELECT e.department_id
       FROM users u
       INNER JOIN employees e ON e.id = u.employee_id
       WHERE u.id = $1`,
      [req.user!.id]
    );
    const managerDepartmentId = res.rows[0]?.department_id;
    if (!managerDepartmentId) {
      // Manager has no department assigned — return unrestricted view (shows all employees)
      return requestedDepartmentId;
    }
    if (requestedDepartmentId && requestedDepartmentId !== managerDepartmentId) {
      throw new AppError('Forbidden: Managers can only view their own department team', 403);
    }
    return managerDepartmentId;
  }

  /** GET /api/dashboard/summary?date=YYYY-MM-DD */
  summary = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const date = req.query.date as string | undefined;
      const data = await this.svc.getSummary(date);
      res.json({ success: true, data });
    } catch (e) { next(e); }
  };

  /** GET /api/dashboard/present */
  present = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { date, employeeId, departmentId, page, limit } = req.query as any;
      const scopedDepartment = await this.scopedDepartmentId(req, departmentId ? Number(departmentId) : undefined);
      const result = await this.svc.getPresentList({
        date,
        employeeId: employeeId ? Number(employeeId) : undefined,
        departmentId: scopedDepartment,
        page: page ? Number(page) : 1,
        limit: limit ? Math.min(Number(limit), 100) : 20,
      });
      res.json({ success: true, ...result, page: Number(page || 1) });
    } catch (e) { next(e); }
  };

  /** GET /api/dashboard/late */
  late = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { date, employeeId, departmentId, page, limit } = req.query as any;
      const scopedDepartment = await this.scopedDepartmentId(req, departmentId ? Number(departmentId) : undefined);
      const result = await this.svc.getLateList({
        date,
        employeeId: employeeId ? Number(employeeId) : undefined,
        departmentId: scopedDepartment,
        page: page ? Number(page) : 1,
        limit: limit ? Math.min(Number(limit), 100) : 20,
      });
      res.json({ success: true, ...result, page: Number(page || 1) });
    } catch (e) { next(e); }
  };

  /** GET /api/dashboard/pending-approvals */
  pendingApprovals = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { type, employeeId, departmentId, dateFrom, dateTo, page, limit } = req.query as any;
      const scopedDepartment = await this.scopedDepartmentId(req, departmentId ? Number(departmentId) : undefined);
      const result = await this.svc.getPendingApprovals({
        type,
        employeeId: employeeId ? Number(employeeId) : undefined,
        departmentId: scopedDepartment,
        dateFrom,
        dateTo,
        page: page ? Number(page) : 1,
        limit: limit ? Math.min(Number(limit), 100) : 20,
      });
      res.json({ success: true, ...result, page: Number(page || 1) });
    } catch (e) { next(e); }
  };

  /** GET /api/dashboard/attendance-monitor */
  attendanceMonitor = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { date, employeeId, departmentId, status, page, limit } = req.query as any;
      const scopedDepartment = await this.scopedDepartmentId(req, departmentId ? Number(departmentId) : undefined);
      const result = await this.svc.getAttendanceMonitor({
        date,
        employeeId: employeeId ? Number(employeeId) : undefined,
        departmentId: scopedDepartment,
        status,
        page: page ? Number(page) : 1,
        limit: limit ? Math.min(Number(limit), 100) : 25,
      });
      res.json({ success: true, ...result, page: Number(page || 1) });
    } catch (e) { next(e); }
  };

  /** GET /api/dashboard/shift-monitor */
  shiftMonitor = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { date } = req.query as any;
      const data = await this.svc.getShiftMonitor(date);
      res.json({ success: true, data });
    } catch (e) { next(e); }
  };

  /** GET /api/dashboard/employee-directory */
  employeeDirectory = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { search, departmentId, shiftId, status, page, limit } = req.query as any;
      const scopedDepartment = await this.scopedDepartmentId(req, departmentId ? Number(departmentId) : undefined);
      const result = await this.svc.getEmployeeDirectory({
        search,
        departmentId: scopedDepartment,
        shiftId: shiftId ? Number(shiftId) : undefined,
        status: status || 'ACTIVE',
        page: page ? Number(page) : 1,
        limit: limit ? Math.min(Number(limit), 100) : 25,
      });
      res.json({ success: true, ...result, page: Number(page || 1) });
    } catch (e) { next(e); }
  };
}
