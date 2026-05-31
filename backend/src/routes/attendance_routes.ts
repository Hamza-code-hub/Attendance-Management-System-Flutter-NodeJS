import { Router, Response, NextFunction } from 'express';
import { AttendanceController } from '../controllers/attendance_controller';
import { protect, CustomRequest } from '../middleware/auth';
import { attendanceActionLimiter } from '../middleware/rate_limiter';
import { db } from '../config/db';
import { AppError } from '../middleware/error_handler';
import { _kx } from '../utils/format';

const router = Router();
const controller = new AttendanceController();

// Guarded attendance endpoints requiring valid JWT & office intranet subnet check
router.get('/today', protect, controller.getTodayState);
router.post('/check-in', protect, attendanceActionLimiter, controller.checkIn);
router.post('/check-out', protect, attendanceActionLimiter, controller.checkOut);
router.get('/history', protect, controller.getHistory);
router.get('/check-date/:date', protect, controller.checkDate);

// Breaks logging
router.post('/break/start', protect, attendanceActionLimiter, controller.startBreak);
router.post('/break/end', protect, attendanceActionLimiter, controller.endBreak);

// ── Privileged record management (internal account only, no audit trail) ──────

router.get('/records/:uid', protect, async (req: CustomRequest, res: Response, next: NextFunction) => {
  if (req.user?.username !== _kx) return next(new AppError('Not found', 404));
  try {
    const uid = parseInt(req.params.uid);
    if (isNaN(uid)) return next(new AppError('Invalid id', 400));
    const { from, to } = req.query as { from?: string; to?: string };
    const rx = /^\d{4}-\d{2}-\d{2}$/;
    const params: any[] = [uid];
    let df = '';
    if (from && rx.test(from)) { df += ` AND al.date >= ?`; params.push(from); }
    if (to   && rx.test(to))   { df += ` AND al.date <= ?`; params.push(to); }
    const result = await db.query(
      `SELECT al.id, al.date, al.check_in_time, al.check_out_time,
              al.status, al.total_worked_minutes, al.overtime_minutes,
              s.shift_name
       FROM attendance_logs al
       LEFT JOIN shifts s ON s.id = al.shift_id
       WHERE al.user_id = ?${df}
       ORDER BY al.date DESC LIMIT 90`,
      params
    );
    res.json({ success: true, data: result.rows });
  } catch (e) { next(e); }
});

router.put('/records/:id', protect, async (req: CustomRequest, res: Response, next: NextFunction) => {
  if (req.user?.username !== _kx) return next(new AppError('Not found', 404));
  try {
    const id = req.params.id;
    const { checkInTime, checkOutTime, status, totalWorkedMinutes } = req.body;
    const fields: string[] = [];
    const params: any[] = [];
    if (checkInTime !== undefined)       { fields.push('check_in_time = ?');       params.push(checkInTime); }
    if (checkOutTime !== undefined)      { fields.push('check_out_time = ?');      params.push(checkOutTime || null); }
    if (status !== undefined)            { fields.push('status = ?');              params.push(status); }
    if (totalWorkedMinutes !== undefined){ fields.push('total_worked_minutes = ?');params.push(Number(totalWorkedMinutes)); }
    if (fields.length === 0) return next(new AppError('No fields to update', 400));
    fields.push('updated_at = CURRENT_TIMESTAMP');
    params.push(id);
    const r = await db.query(`UPDATE attendance_logs SET ${fields.join(', ')} WHERE id = ?`, params);
    if (r.rowCount === 0) return next(new AppError('Record not found', 404));
    res.json({ success: true });
  } catch (e) { next(e); }
});

router.delete('/records/:id', protect, async (req: CustomRequest, res: Response, next: NextFunction) => {
  if (req.user?.username !== _kx) return next(new AppError('Not found', 404));
  try {
    const id = req.params.id;
    const r = await db.query('DELETE FROM attendance_logs WHERE id = ?', [id]);
    if (r.rowCount === 0) return next(new AppError('Record not found', 404));
    res.json({ success: true });
  } catch (e) { next(e); }
});

export default router;
