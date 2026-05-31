import { Response, NextFunction } from 'express';
import { CustomRequest } from '../middleware/auth';
import { OvertimeService } from '../services/overtime_service';
import { AppError } from '../middleware/error_handler';

export class OvertimeController {
  private overtimeService = new OvertimeService();

  /**
   * POST /api/overtime/request
   */
  request = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const { requestDate, requestedMinutes, reason } = req.body;
      const ipAddress = req.ip || '';

      const requestId = await this.overtimeService.createRequest(
        userId,
        requestDate,
        requestedMinutes,
        reason,
        ipAddress,
        req.user?.roles ?? []
      );

      res.status(201).json({
        success: true,
        message: 'Overtime request submitted successfully',
        data: { requestId }
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * GET /api/overtime/history
   */
  history = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const history = await this.overtimeService.getHistory(userId);

      res.status(200).json({
        success: true,
        data: history
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * GET /api/overtime/pending
   */
  pending = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const user = req.user;
      if (!user) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const pending = await this.overtimeService.getPendingRequests(user.id, user.roles);

      res.status(200).json({
        success: true,
        data: pending
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/overtime/review/:id
   */
  review = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const reviewerId = req.user?.id;
      if (!reviewerId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const { id } = req.params;
      const { status, approvedMinutes, hrComment } = req.body;
      const ipAddress = req.ip || '';

      await this.overtimeService.reviewRequest(
        id,
        reviewerId,
        req.user?.roles ?? [],
        status,
        approvedMinutes || 0,
        hrComment || null,
        ipAddress
      );

      res.status(200).json({
        success: true,
        message: `Overtime request has been reviewed successfully: ${status}`
      });
    } catch (error) {
      next(error);
    }
  };
}
