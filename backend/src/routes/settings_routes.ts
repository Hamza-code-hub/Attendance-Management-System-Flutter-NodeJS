import { Router, Response, NextFunction } from 'express';
import { protect, authorize, CustomRequest } from '../middleware/auth';
import { db } from '../config/db';
import { logger } from '../config/logger';

const router = Router();
router.use(protect);

/** GET /api/settings/departments — accessible to HR, Admin, Manager for report filtering */
router.get('/departments', authorize('Admin', 'HR', 'Manager'), async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const rows = await db.query(`SELECT id, department_name, description, created_at FROM departments ORDER BY department_name`);
    res.json({ success: true, data: rows.rows });
  } catch (e) { next(e); }
});

/** POST /api/settings/departments — create department (Admin only) */
router.post('/departments', authorize('Admin'), async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const { department_name, description } = req.body;
    if (!department_name) {
      res.status(400).json({ success: false, error: { message: 'department_name is required', status: 400 } });
      return;
    }
    await db.query(
      `INSERT INTO departments (department_name, description) VALUES ($1, $2)`,
      [department_name.trim(), description || null]
    );
    res.status(201).json({ success: true, message: 'Department created' });
  } catch (e) { next(e); }
});

/** PUT /api/settings/departments/:id — update department */
router.put('/departments/:id', authorize('Admin'), async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params.id);
    if (isNaN(id)) { res.status(400).json({ success: false, error: { message: 'Invalid department ID' } }); return; }
    const { department_name, description } = req.body;
    if (!department_name) { res.status(400).json({ success: false, error: { message: 'department_name is required' } }); return; }
    await db.query('UPDATE departments SET department_name = $1, description = $2 WHERE id = $3', [department_name.trim(), description || null, id]);
    res.json({ success: true, message: 'Department updated' });
  } catch (e) { next(e); }
});

/** DELETE /api/settings/departments/:id — delete department */
router.delete('/departments/:id', authorize('Admin'), async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params.id);
    if (isNaN(id)) { res.status(400).json({ success: false, error: { message: 'Invalid department ID' } }); return; }
    const check = await db.query('SELECT COUNT(*) as cnt FROM employees WHERE department_id = $1', [id]);
    if (parseInt(check.rows[0].cnt) > 0) {
      res.status(400).json({ success: false, error: { message: 'Cannot delete department with assigned employees. Reassign employees first.' } }); return;
    }
    await db.query('DELETE FROM departments WHERE id = $1', [id]);
    res.json({ success: true, message: 'Department deleted' });
  } catch (e) { next(e); }
});

router.use(authorize('Admin'));

/** GET /api/settings — retrieve all settings */
router.get('/', async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const rows = await db.query(`SELECT key, value, description, updated_at FROM settings ORDER BY key`);
    const settings: Record<string, any> = {};
    rows.rows.forEach((r: any) => { settings[r.key] = { value: r.value, description: r.description, updatedAt: r.updated_at }; });
    res.json({ success: true, data: settings });
  } catch (e) { next(e); }
});

/** PUT /api/settings — bulk update settings */
router.put('/', async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const updates: Record<string, string> = req.body;
    if (!updates || typeof updates !== 'object') {
      res.status(400).json({ success: false, error: { message: 'Body must be key-value pairs of settings', status: 400 } });
      return;
    }

    const allowedKeys = [
      'grace_period_minutes', 'office_subnet', 'enforce_subnet',
      'missed_checkout_hours', 'max_break_minutes', 'org_name',
      'allow_self_checkout', 'require_manager_approval',
      // Shift & break time (configurable by admin)
      'shift_name', 'shift_start', 'shift_end',
      'break_start', 'break_end',
    ];

    for (const [key, value] of Object.entries(updates)) {
      if (!allowedKeys.includes(key)) continue;
      await db.query(
        `INSERT INTO settings (key, value, updated_at) VALUES ($1, $2, CURRENT_TIMESTAMP)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = CURRENT_TIMESTAMP`,
        [key, String(value)]
      );
    }

    logger.info(`[Settings] Updated by user ${req.user?.email}: ${Object.keys(updates).join(', ')}`);
    res.json({ success: true, message: 'Settings updated successfully' });
  } catch (e) { next(e); }
});

export default router;
