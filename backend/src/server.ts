import app from './app';
import { logger } from './config/logger';
import { db } from './config/db';
import { AuthService } from './services/auth_service';
import { scheduler } from './services/scheduler_service';

const PORT = process.env.PORT || 5000;
const authService = new AuthService();

// Ensure settings table exists on every startup
async function ensureSettingsTable() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL DEFAULT '',
      description TEXT,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
  `);
  // Seed defaults (won't overwrite existing)
  const defaults: [string, string, string][] = [
    ['grace_period_minutes', '10', 'Minutes after shift start before marking LATE'],
    ['office_subnet', '192.168.1.', 'Office IP subnet prefix for access control'],
    ['enforce_subnet', 'false', 'Restrict access to office subnet only'],
    ['missed_checkout_hours', '12', 'Hours after which unclosed sessions become MISSED_CHECKOUT'],
    ['max_break_minutes', '60', 'Maximum allowed break duration per day in minutes'],
    ['org_name', 'Company Attendance System', 'Organization display name'],
    ['allow_self_checkout', 'true', 'Allow employees to check out themselves'],
    ['require_manager_approval', 'false', 'Require manager approval for overtime requests'],
    // Shift & break time defaults
    ['shift_name', 'Morning Shift', 'Default shift name'],
    ['shift_start', '09:00', 'Shift start time (HH:mm)'],
    ['shift_end', '18:00', 'Shift end time (HH:mm)'],
    ['break_start', '13:00', 'Break start time (HH:mm)'],
    ['break_end', '14:00', 'Break end time (HH:mm)'],
  ];
  for (const [key, value, description] of defaults) {
    await db.query(
      `INSERT OR IGNORE INTO settings (key, value, description) VALUES ($1, $2, $3)`,
      [key, value, description]
    );
  }
}

const server = app.listen(Number(PORT), '0.0.0.0', async () => {
  logger.info('=======================================================');
  logger.info(` Attendance API running on port: ${PORT} (all interfaces)`);
  logger.info(` LAN URL: http://192.168.100.15:${PORT}`);
  logger.info(`=======================================================`);

  await ensureSettingsTable();
  await authService.startupAutoSeed();
  scheduler.start();
});

const handleShutdown = async (signal: string) => {
  logger.warn(`[${signal}] Graceful shutdown initiated...`);
  scheduler.stop();
  server.close(async () => {
    logger.info('HTTP server closed.');
    try {
      await db.close();
      process.exit(0);
    } catch {
      process.exit(1);
    }
  });
  setTimeout(() => process.exit(1), 5000);
};

process.on('SIGTERM', () => handleShutdown('SIGTERM'));
process.on('SIGINT', () => handleShutdown('SIGINT'));
process.on('unhandledRejection', (reason: any) => {
  logger.error(`Unhandled Rejection: ${reason?.message || reason}`);
});
process.on('uncaughtException', (error: Error) => {
  logger.error(`Uncaught Exception: ${error.message}`);
  process.exit(1);
});
