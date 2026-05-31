import { Response, NextFunction } from 'express';
import { CustomRequest } from '../middleware/auth';
import { ShiftService } from '../services/shift_service';
import { AppError } from '../middleware/error_handler';

export class ShiftController {
  private shiftService = new ShiftService();

  /**
   * GET /api/shifts
   */
  getShifts = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const shifts = await this.shiftService.getShifts();
      res.status(200).json({
        success: true,
        data: shifts
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * GET /api/shifts/:id
   */
  getShiftById = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return next(new AppError('Invalid Shift ID parameter', 400));
      }

      const shift = await this.shiftService.getShiftById(id);
      res.status(200).json({
        success: true,
        data: shift
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/shifts (Admin only)
   */
  createShift = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { shiftName, shiftStart, shiftEnd, graceMinutes, nightShiftEnabled, allowOvertime, active } = req.body;
      if (!shiftName || !shiftStart || !shiftEnd) {
        return next(new AppError('Shift Name, Shift Start and Shift End times are required', 400));
      }

      const newShift = await this.shiftService.createShift({
        shiftName,
        shiftStart,
        shiftEnd,
        graceMinutes: graceMinutes ? parseInt(graceMinutes) : 10,
        nightShiftEnabled: nightShiftEnabled === true,
        allowOvertime: allowOvertime !== false,
        active: active !== false
      });

      res.status(201).json({
        success: true,
        message: 'Shift configuration created successfully',
        data: newShift
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * PUT /api/shifts/:id (Admin only)
   */
  updateShift = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return next(new AppError('Invalid Shift ID parameter', 400));
      }

      const updated = await this.shiftService.updateShift(id, req.body);
      res.status(200).json({
        success: true,
        message: 'Shift configuration updated successfully',
        data: updated
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * DELETE /api/shifts/:id (Admin only)
   */
  deleteShift = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return next(new AppError('Invalid Shift ID parameter', 400));
      }

      await this.shiftService.deleteShift(id);
      res.status(200).json({
        success: true,
        message: 'Shift configuration deleted successfully'
      });
    } catch (error) {
      next(error);
    }
  };
}
