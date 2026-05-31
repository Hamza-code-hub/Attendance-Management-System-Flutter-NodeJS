import { Router, Request, Response } from 'express';
import { db } from '../config/db';
import { logger } from '../config/logger';
import os from 'os';

const router = Router();

router.get('/', async (req: Request, res: Response) => {
  const start = Date.now();
  try {
    await db.query('SELECT 1');
    const dbLatency = Date.now() - start;

    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: Math.floor(process.uptime()),
      version: process.env.npm_package_version || '1.0.0',
      database: { status: 'connected', latencyMs: dbLatency },
      system: {
        platform: process.platform,
        nodeVersion: process.version,
        memoryUsedMB: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
        cpuLoadAvg: os.loadavg()[0].toFixed(2),
      },
    });
  } catch (err: any) {
    logger.error(`[Health] DB check failed: ${err.message}`);
    res.status(503).json({
      status: 'degraded',
      timestamp: new Date().toISOString(),
      database: { status: 'disconnected', error: err.message },
    });
  }
});

export default router;
