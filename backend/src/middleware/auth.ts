import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { logger } from '../config/logger';
import { AppError } from './error_handler';

export interface AuthenticatedUser {
  id: number;
  username: string;
  email: string;
  roles: string[];
}

export interface CustomRequest extends Request {
  user?: AuthenticatedUser;
}

/**
 * Protect routes by checking valid local JWT
 */
export const protect = async (
  req: CustomRequest,
  res: Response,
  next: NextFunction
) => {
  let token: string | undefined;

  if (
    req.headers.authorization &&
    req.headers.authorization.startsWith('Bearer')
  ) {
    token = req.headers.authorization.split(' ')[1];
  }

  if (!token) {
    return next(new AppError('Unauthorized: Access token is missing', 401));
  }

  try {
    const decoded = jwt.verify(
      token,
      process.env.JWT_SECRET || 'office_local_deployment_jwt_secret_key_2026_xyz123'
    ) as AuthenticatedUser;

    if (!decoded.id || typeof decoded.id !== 'number') {
      return next(new AppError('Unauthorized: Invalid access token subject', 401));
    }

    // Real-time database verification: never trust stale token roles/account state.
    const { db } = require('../config/db');
    const userRes = await db.query(`
      SELECT u.id, u.username, u.email, u.status, e.employment_status
      FROM users u
      LEFT JOIN employees e ON e.id = u.employee_id
      WHERE u.id = $1
    `, [decoded.id]);

    if (userRes.rows.length === 0) {
      return next(new AppError('Unauthorized: User session no longer exists', 401));
    }

    const dbUser = userRes.rows[0];
    if (dbUser.status !== 'ACTIVE' || dbUser.employment_status === 'INACTIVE') {
      return next(new AppError('Unauthorized: Your employee account has been deactivated or suspended.', 401));
    }

    const rolesRes = await db.query(`
      SELECT r.role_name
      FROM roles r
      INNER JOIN user_roles ur ON ur.role_id = r.id
      WHERE ur.user_id = $1
    `, [decoded.id]);

    req.user = {
      id: dbUser.id,
      username: dbUser.username,
      email: dbUser.email,
      roles: rolesRes.rows.map((row: any) => row.role_name),
    };
    next();
  } catch (error) {
    logger.warn(`Failed login or authentication attempt from IP: ${req.ip}`);
    return next(new AppError('Unauthorized: Invalid or expired access token', 401));
  }
};

/**
 * Restrict access based on standard office Roles
 */
export const authorize = (...roles: string[]) => {
  return (req: CustomRequest, res: Response, next: NextFunction) => {
    if (!req.user) {
      return next(new AppError('Forbidden: User authentication required', 403));
    }

    const hasRequiredRole = req.user.roles.some((r) => roles.includes(r));
    if (!hasRequiredRole) {
      logger.warn(`Unauthorized role access attempt by user ${req.user.email} (Roles: ${req.user.roles.join(', ')}) trying to access restricted route.`);
      return next(new AppError('Forbidden: You do not have permissions for this action', 403));
    }

    next();
  };
};

/**
 * Validate request origin IP subnet (office-only restriction)
 */
export const verifyOfficeSubnet = (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  const clientIp = req.ip || req.socket.remoteAddress || '';
  const enforceSubnet = process.env.ENFORCE_SUBNET === 'true';

  // Placeholder checking for office IP range configuration (e.g. 192.168.1.*)
  logger.info(`Validating office network access for request IP: ${clientIp}`);

  if (enforceSubnet) {
    // In real deployment, match clientIp against subnet (e.g. using ipaddr.js or simple range checks)
    // For local hosting, allow localhost/loopback interfaces
    const isLocalhost =
      clientIp === '127.0.0.1' ||
      clientIp === '::1' ||
      clientIp === '::ffff:127.0.0.1' ||
      clientIp.startsWith('192.168.100.') ||
      clientIp.startsWith('::ffff:192.168.100.');

    if (!isLocalhost) {
      logger.warn(`Blocked external IP connection attempt: ${clientIp}`);
      return next(
        new AppError(
          'Access Restricted: This system is only accessible from within the local office intranet network.',
          403
        )
      );
    }
  }

  next();
};
