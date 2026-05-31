import { Response, NextFunction } from 'express';
import { CustomRequest } from '../middleware/auth';
import { AttendanceService } from '../services/attendance_service';
import { AppError } from '../middleware/error_handler';

export class AttendanceController {
  private attendanceService = new AttendanceService();

  private rejectClientIdentityOverride(req: CustomRequest): void {
    const forbiddenKeys = ['userId', 'user_id', 'employeeId', 'employee_id', 'attendanceId', 'attendance_id'];
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const query = req.query && typeof req.query === 'object' ? req.query : {};
    const attemptedKey = forbiddenKeys.find((key) => body[key] !== undefined || query[key] !== undefined);

    if (attemptedKey) {
      throw new AppError(
        `Forbidden attendance identity override: ${attemptedKey}. Attendance actions always use the logged-in user only.`,
        403
      );
    }
  }

  private rejectAdminAttendance(req: CustomRequest): void {
    if (req.user?.roles.includes('Admin')) {
      throw new AppError('Forbidden: Admin accounts cannot perform employee check-in, check-out, or break actions', 403);
    }
  }

  /**
   * GET /api/attendance/today
   */
  getTodayState = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      this.rejectClientIdentityOverride(req);
      this.rejectAdminAttendance(req);
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const state = await this.attendanceService.getTodayState(userId);
      res.status(200).json({
        success: true,
        data: state
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/attendance/check-in
   */
  checkIn = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      this.rejectClientIdentityOverride(req);
      this.rejectAdminAttendance(req);
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const log = await this.attendanceService.checkIn(userId);
      res.status(201).json({
        success: true,
        message: 'Successfully clocked in',
        data: log
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/attendance/check-out
   */
  checkOut = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      this.rejectClientIdentityOverride(req);
      this.rejectAdminAttendance(req);
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      await this.attendanceService.checkOut(userId);
      res.status(200).json({
        success: true,
        message: 'Successfully clocked out'
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/attendance/break/start
   */
  startBreak = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      this.rejectClientIdentityOverride(req);
      this.rejectAdminAttendance(req);
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      await this.attendanceService.startBreak(userId);
      res.status(200).json({
        success: true,
        message: 'Break session started successfully'
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/attendance/break/end
   */
  endBreak = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      this.rejectClientIdentityOverride(req);
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      await this.attendanceService.endBreak(userId);
      res.status(200).json({
        success: true,
        message: 'Break session ended successfully'
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * GET /api/attendance/check-date/:date
   * Returns check-in / check-out state for a specific date (YYYY-MM-DD) for the logged-in user.
   * Used by the correction form to validate before submission.
   */
  checkDate = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      this.rejectClientIdentityOverride(req);
      const userId = req.user?.id;
      if (!userId) return next(new AppError('Unauthorized: Access session details not found', 401));

      const { date } = req.params;
      if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
        return next(new AppError('Bad Request: date must be YYYY-MM-DD', 400));
      }

      const record = await this.attendanceService.getRecordForDate(userId, date);
      res.status(200).json({
        success: true,
        data: record
          ? {
              hasRecord: true,
              checkInTime: record.checkInTime ? new Date(record.checkInTime).toISOString() : null,
              checkOutTime: record.checkOutTime ? new Date(record.checkOutTime).toISOString() : null,
            }
          : { hasRecord: false, checkInTime: null, checkOutTime: null },
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * GET /api/attendance/history
   * Optional query params: from=YYYY-MM-DD&to=YYYY-MM-DD
   */
  getHistory = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      this.rejectClientIdentityOverride(req);
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const { from, to } = req.query as { from?: string; to?: string };
      const dateRx = /^\d{4}-\d{2}-\d{2}$/;
      const fromDate = from && dateRx.test(from) ? from : undefined;
      const toDate   = to   && dateRx.test(to)   ? to   : undefined;

      const logs = await this.attendanceService.getHistory(userId, fromDate, toDate);
      res.status(200).json({
        success: true,
        data: logs
      });
    } catch (error) {
      next(error);
    }
  };
}
