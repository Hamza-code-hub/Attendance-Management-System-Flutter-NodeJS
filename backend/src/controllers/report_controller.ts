import { Response, NextFunction } from 'express';
import { CustomRequest } from '../middleware/auth';
import { ReportService } from '../services/report_service';
import { AppError } from '../middleware/error_handler';

export class ReportController {
  private svc = new ReportService();

  private parseFilters(query: any) {
    return {
      dateFrom: query.dateFrom as string,
      dateTo: query.dateTo as string,
      employeeId: query.employeeId ? Number(query.employeeId) : undefined,
      departmentId: query.departmentId ? Number(query.departmentId) : undefined,
      shiftId: query.shiftId ? Number(query.shiftId) : undefined,
      status: query.status as string | undefined,
      page: query.page ? Number(query.page) : 1,
      limit: query.limit ? Math.min(Number(query.limit), 200) : 50,
    };
  }

  /** GET /api/reports/:type  — paginated table data */
  getReport = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const type = req.params.type as any;
      const filters = this.parseFilters(req.query);
      const result = await this.svc.getReportData(type, filters);
      res.json({ success: true, ...result, page: filters.page });
    } catch (e) { next(e); }
  };

  /** GET /api/reports/:type/export?format=excel|csv  — file download */
  exportReport = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const type = req.params.type as any;
      const format = (req.query.format as string) === 'csv' ? 'csv' : 'excel';
      const filters = this.parseFilters(req.query);

      const { buffer, filename, contentType } = await this.svc.generateExport(type, format, filters);

      res.setHeader('Content-Type', contentType);
      res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
      res.setHeader('Content-Length', buffer.length);
      res.end(buffer);
    } catch (e) { next(e); }
  };

  /** GET /api/reports/monthly-matrix/export?month=YYYY-MM&departmentId=N
   *  Downloads a matrix Excel: employee rows × daily columns (Check In / Check Out)
   */
  exportMonthlyMatrix = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const month = req.query.month as string;
      if (!month || !/^\d{4}-\d{2}$/.test(month)) {
        res.status(400).json({ success: false, error: { message: 'month param required (YYYY-MM)', status: 400 } });
        return;
      }
      const monthNumber = Number(month.slice(5, 7));
      if (monthNumber < 1 || monthNumber > 12) {
        res.status(400).json({ success: false, error: { message: 'month must be between 01 and 12', status: 400 } });
        return;
      }
      const departmentId = req.query.departmentId ? Number(req.query.departmentId) : undefined;

      // Fetch org name from settings
      const { db } = await import('../config/db');
      const setting = await db.query(`SELECT value FROM settings WHERE key = 'org_name'`);
      const orgName = setting.rows[0]?.value as string | undefined;

      const { buffer, filename, contentType } =
        await this.svc.generateMonthlyMatrix(month, departmentId, orgName);

      res.setHeader('Content-Type', contentType);
      res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
      res.setHeader('Content-Length', buffer.length);
      res.end(buffer);
    } catch (e) { next(e); }
  };
}
