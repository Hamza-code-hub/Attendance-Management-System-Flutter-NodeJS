import { Response, NextFunction } from 'express';
import { CustomRequest } from '../middleware/auth';
import { AuthService } from '../services/auth_service';
import { AppError } from '../middleware/error_handler';

export class AuthController {
  private authService = new AuthService();

  /**
   * POST /api/auth/login
   */
  login = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { usernameOrEmail, password, deviceInfo } = req.body;
      if (!usernameOrEmail || !password) {
        return next(new AppError('Username/email and password are required', 400));
      }

      const ip = req.ip || '127.0.0.1';
      const devInfo = deviceInfo || req.headers['user-agent'] || 'Unknown Browser';

      const result = await this.authService.login(usernameOrEmail, password, devInfo, ip);

      res.status(200).json({
        success: true,
        message: 'Login successful',
        data: result
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/auth/logout
   */
  logout = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { refreshToken } = req.body;
      if (!refreshToken) {
        return next(new AppError('Refresh token is required for logging out', 400));
      }

      const ip = req.ip || '127.0.0.1';
      await this.authService.logout(refreshToken, ip);

      res.status(200).json({
        success: true,
        message: 'Successfully logged out session'
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/auth/refresh
   */
  refresh = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { refreshToken, deviceInfo } = req.body;
      if (!refreshToken) {
        return next(new AppError('Refresh token is required', 400));
      }

      const ip = req.ip || '127.0.0.1';
      const devInfo = deviceInfo || req.headers['user-agent'] || 'Unknown Browser';

      const result = await this.authService.refresh(refreshToken, devInfo, ip);

      res.status(200).json({
        success: true,
        message: 'Token rotated successfully',
        data: result
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * GET /api/auth/me
   */
  me = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const user = await this.authService.getMe(userId);

      res.status(200).json({
        success: true,
        data: user
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/auth/change-password
   */
  changePassword = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const userId = req.user?.id;
      const { oldPassword, newPassword } = req.body;
      
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }
      if (!oldPassword || !newPassword) {
        return next(new AppError('Current password and new password are required', 400));
      }

      const ip = req.ip || '127.0.0.1';
      await this.authService.changePassword(userId, oldPassword, newPassword, ip);

      res.status(200).json({
        success: true,
        message: 'Password updated successfully. Other active sessions revoked.'
      });
    } catch (error) {
      next(error);
    }
  };
}
