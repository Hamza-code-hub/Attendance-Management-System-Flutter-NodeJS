import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import { logger } from './config/logger';
import { errorHandler } from './middleware/error_handler';
import { verifyOfficeSubnet } from './middleware/auth';
import { apiLimiter, loginLimiter } from './middleware/rate_limiter';
import rootRouter from './routes';

dotenv.config();

const app = express();

// 1. Security Headers
app.use(helmet({
  crossOriginEmbedderPolicy: false,
  contentSecurityPolicy: false,
}));

// 2. CORS for local office network
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  exposedHeaders: ['Content-Disposition'],
}));

app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));

// 3. Request Logging
app.use((req, res, next) => {
  logger.http(`${req.method} ${req.originalUrl} — IP: ${req.ip}`);
  next();
});

// 4. Office Subnet IP Restriction
app.use(verifyOfficeSubnet);

// 5. Global API Rate Limiting
app.use('/api', apiLimiter);

// 6. Stricter throttle on login
app.use('/api/auth/login', loginLimiter);

// 7. API Routes
app.use('/api', rootRouter);

// 8. 404 Fallback
app.use('*', (req, res) => {
  res.status(404).json({
    success: false,
    error: { message: `Not found: ${req.method} ${req.originalUrl}`, status: 404 },
  });
});

// 9. Global Error Handler
app.use(errorHandler);

export default app;
