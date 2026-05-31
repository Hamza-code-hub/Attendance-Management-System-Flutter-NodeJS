import rateLimit from 'express-rate-limit';
import { logger } from '../config/logger';

const onLimitReached = (req: any, res: any) => {
  logger.warn(`[RateLimit] Rate limit exceeded: IP=${req.ip} Path=${req.originalUrl}`);
};

/** General API rate limit: 200 req/15min per IP */
export const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: { message: 'Too many requests. Please wait before retrying.', status: 429 },
  },
  handler: (req, res, next, options) => {
    onLimitReached(req, res);
    res.status(429).json(options.message);
  },
});

/** Login throttle: 10 attempts/15min per IP */
export const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: { message: 'Too many login attempts. Account is temporarily locked. Try again in 15 minutes.', status: 429 },
  },
  handler: (req, res, next, options) => {
    logger.warn(`[LoginThrottle] Login rate limit hit: IP=${req.ip}`);
    res.status(429).json(options.message);
  },
});

/** Export limiter: 5 exports/5min (large file generation) */
export const exportLimiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  max: 5,
  message: {
    success: false,
    error: { message: 'Export limit reached. Please wait before downloading another report.', status: 429 },
  },
  handler: (req, res, next, options) => {
    logger.warn(`[ExportLimit] Export rate limit hit: IP=${req.ip}`);
    res.status(429).json(options.message);
  },
});

/** Attendance action limiter: prevents rapid repeated clock/break actions */
export const attendanceActionLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: { message: 'Too many attendance actions. Please wait a moment and try again.', status: 429 },
  },
  handler: (req, res, next, options) => {
    logger.warn(`[AttendanceLimit] Attendance action rate limit hit: IP=${req.ip}`);
    res.status(429).json(options.message);
  },
});
