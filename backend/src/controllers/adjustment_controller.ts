import { Response, NextFunction } from 'express';
import { CustomRequest } from '../middleware/auth';
import { AdjustmentService } from '../services/adjustment_service';
import { AppError } from '../middleware/error_handler';

export class AdjustmentController {
  private adjustmentService = new AdjustmentService();

  /**
   * POST /api/adjustments/request
   */
  request = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const { adjustmentType, requestedCheckinTime, requestedCheckoutTime, reason, requestedMinutes, requestDate } = req.body;
      const ipAddress = req.ip || '';

      const requestId = await this.adjustmentService.createRequest(
        userId,
        adjustmentType,
        requestedCheckinTime || null,
        requestedCheckoutTime || null,
        reason,
        ipAddress,
        req.user?.roles ?? [],
        requestedMinutes !== undefined ? Number(requestedMinutes) : undefined,
        requestDate || null
      );

      res.status(201).json({
        success: true,
        message: 'Adjustment request submitted successfully',
        data: { requestId }
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * GET /api/adjustments/history
   */
  history = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const history = await this.adjustmentService.getHistory(userId);

      res.status(200).json({
        success: true,
        data: history
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * GET /api/adjustments/pending
   */
  pending = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const user = req.user;
      if (!user) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const pending = await this.adjustmentService.getPendingRequests(user.id, user.roles);

      res.status(200).json({
        success: true,
        data: pending
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/adjustments/review/:id
   */
  review = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const reviewerId = req.user?.id;
      if (!reviewerId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const { id } = req.params;
      const { status, hrComment } = req.body;
      const ipAddress = req.ip || '';

      await this.adjustmentService.reviewRequest(
        id,
        reviewerId,
        req.user?.roles ?? [],
        status,
        hrComment || null,
        ipAddress
      );

      res.status(200).json({
        success: true,
        message: `Adjustment request has been reviewed successfully: ${status}`
      });
    } catch (error) {
      next(error);
    }
  };
}
