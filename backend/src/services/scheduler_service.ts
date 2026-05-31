import * as cron from 'node-cron';
import { db } from '../config/db';
import { logger } from '../config/logger';

export class SchedulerService {
  private jobs: cron.ScheduledTask[] = [];

  start() {
    logger.info('[Scheduler] Starting automated background jobs...');

    // 1. Sweep missed checkouts every hour (10 mins past each hour)
    this.jobs.push(
      cron.schedule('10 * * * *', () => this.sweepMissedCheckouts(), {
        name: 'missed-checkout-sweep',
      })
    );

    // 2. Clean expired sessions daily at 2:00 AM
    this.jobs.push(
      cron.schedule('0 2 * * *', () => this.cleanExpiredSessions(), {
        name: 'session-cleanup',
      })
    );

    // 3. Clean orphaned break records daily at 2:15 AM
    this.jobs.push(
      cron.schedule('15 2 * * *', () => this.cleanOrphanBreaks(), {
        name: 'orphan-break-cleanup',
      })
    );

    // 4. Log daily attendance summary at 11:59 PM
    this.jobs.push(
      cron.schedule('59 23 * * *', () => this.logDailySummary(), {
        name: 'daily-summary',
      })
    );

    logger.info('[Scheduler] All jobs scheduled successfully.');
  }

  stop() {
    this.jobs.forEach(j => j.stop());
    logger.info('[Scheduler] All scheduled jobs stopped.');
  }

  private async sweepMissedCheckouts(): Promise<void> {
    try {
      const cutoff = new Date(Date.now() - 12 * 60 * 60 * 1000).toISOString();
      const res = await db.query(
        `UPDATE attendance_logs SET status = 'MISSED_CHECKOUT', updated_at = CURRENT_TIMESTAMP
         WHERE check_out_time IS NULL AND check_in_time < $1 AND status NOT IN ('MISSED_CHECKOUT')`,
        [cutoff]
      );
      if (res.rowCount > 0) {
        logger.info(`[Scheduler] Swept ${res.rowCount} missed checkout(s).`);
      }
    } catch (err: any) {
      logger.error(`[Scheduler] sweepMissedCheckouts error: ${err.message}`);
    }
  }

  private async cleanExpiredSessions(): Promise<void> {
    try {
      const res = await db.query(
        `DELETE FROM sessions WHERE expires_at < CURRENT_TIMESTAMP`
      );
      logger.info(`[Scheduler] Cleaned ${res.rowCount} expired session(s).`);
    } catch (err: any) {
      logger.error(`[Scheduler] cleanExpiredSessions error: ${err.message}`);
    }
  }

  private async cleanOrphanBreaks(): Promise<void> {
    try {
      // Close breaks that have been open for more than 8 hours
      const cutoff = new Date(Date.now() - 8 * 60 * 60 * 1000).toISOString();
      const res = await db.query(
        `UPDATE break_logs
         SET break_end = CURRENT_TIMESTAMP,
             duration_minutes = CAST((julianday(CURRENT_TIMESTAMP) - julianday(break_start)) * 1440 AS INTEGER)
         WHERE break_end IS NULL AND break_start < $1`,
        [cutoff]
      );
      if (res.rowCount > 0) {
        logger.warn(`[Scheduler] Force-closed ${res.rowCount} orphaned break(s) > 8h.`);
      }
    } catch (err: any) {
      logger.error(`[Scheduler] cleanOrphanBreaks error: ${err.message}`);
    }
  }

  private async logDailySummary(): Promise<void> {
    try {
      const today = new Date().toISOString().split('T')[0];
      const [present, late, missed] = await Promise.all([
        db.query(`SELECT COUNT(*) as c FROM attendance_logs WHERE date = $1 AND check_in_time IS NOT NULL`, [today]),
        db.query(`SELECT COUNT(*) as c FROM attendance_logs WHERE date = $1 AND status = 'LATE'`, [today]),
        db.query(`SELECT COUNT(*) as c FROM attendance_logs WHERE date = $1 AND status = 'MISSED_CHECKOUT'`, [today]),
      ]);
      logger.info(`[DailySummary] ${today} — Present: ${present.rows[0]?.c}, Late: ${late.rows[0]?.c}, Missed Checkout: ${missed.rows[0]?.c}`);
    } catch (err: any) {
      logger.error(`[Scheduler] logDailySummary error: ${err.message}`);
    }
  }
}

export const scheduler = new SchedulerService();
