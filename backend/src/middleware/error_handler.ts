import { Request, Response, NextFunction } from 'express';
import { logger } from '../config/logger';

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly isOperational: boolean;

  constructor(message: string, statusCode: number, isOperational = true) {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    Object.setPrototypeOf(this, target.prototype); // Fix prototype chain
    Error.captureStackTrace(this, this.constructor);
  }
}

// Fix target constructor references in custom error class
const target = AppError;

export const errorHandler = (
  err: any,
  req: Request,
  res: Response,
  next: NextFunction
) => {
  const statusCode = err.statusCode || 500;
  const message = err.message || 'Internal Server Error';

  logger.error(`[${req.method}] ${req.originalUrl} - Error Status: ${statusCode} | Message: ${message} | Stack: ${err.stack}`);

  res.status(statusCode).json({
    success: false,
    error: {
      message: statusCode === 500 && process.env.NODE_ENV === 'production' 
        ? 'A serious system error occurred' 
        : message,
      status: statusCode,
      timestamp: new Date().toISOString(),
    },
  });
};
