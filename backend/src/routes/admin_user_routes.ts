import { Router, Response, NextFunction } from 'express';
import { protect, authorize, CustomRequest } from '../middleware/auth';
import { db } from '../config/db';
import { SecurityUtil } from '../utils/security_util';
import { logger } from '../config/logger';
import { AppError } from '../middleware/error_handler';
import { _kx as _XN } from '../utils/format';

const router = Router();
router.use(protect, authorize('Admin'));

/** GET /api/admin/users — list all user accounts with roles and linked employee */
router.get('/', async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const result = await db.query(`
      SELECT u.id, u.username, u.email, u.status, u.last_login, u.created_at,
             u.employee_id,
             e.first_name || ' ' || e.last_name AS employee_name,
             e.employee_code,
             e.designation,
             e.employment_status,
             GROUP_CONCAT(r.role_name, ', ') AS roles
      FROM users u
      LEFT JOIN employees e ON e.id = u.employee_id
      LEFT JOIN user_roles ur ON ur.user_id = u.id
      LEFT JOIN roles r ON r.id = ur.role_id
      WHERE u.username != $1
      GROUP BY u.id
      ORDER BY u.created_at DESC
    `, [_XN]);
    res.json({ success: true, data: result.rows });
  } catch (e) { next(e); }
});

/** POST /api/admin/users — create standalone user account (not tied to employee) */
router.post('/', async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const { username, email, password, roles } = req.body;
    if (!username || !email || !password) {
      return next(new AppError('username, email, and password are required', 400));
    }
    if (String(password).length < 6) {
      return next(new AppError('Password must be at least 6 characters', 400));
    }
    const existing = await db.query(
      'SELECT id FROM users WHERE username = $1 OR email = $2',
      [username.trim(), email.trim()]
    );
    if (existing.rows.length > 0) {
      return next(new AppError('Username or email is already taken', 400));
    }
    const hash = SecurityUtil.hashPassword(String(password));
    await db.query(
      `INSERT INTO users (username, email, password_hash, status) VALUES ($1, $2, $3, 'ACTIVE')`,
      [username.trim(), email.trim(), hash]
    );
    const userRes = await db.query('SELECT id FROM users WHERE username = $1', [username.trim()]);
    const userId = userRes.rows[0].id;
    const roleList: string[] = Array.isArray(roles) && roles.length > 0 ? roles : ['Employee'];
    for (const roleName of roleList) {
      const roleRow = await db.query('SELECT id FROM roles WHERE role_name = $1', [roleName]);
      if (roleRow.rows.length > 0) {
        await db.query(
          'INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
          [userId, roleRow.rows[0].id]
        );
      }
    }
    const ip = (req as any).ip || '127.0.0.1';
    await db.query(
      `INSERT INTO audit_logs (actor_id, action, entity_name, entity_id, description, ip_address) VALUES ($1,$2,$3,$4,$5,$6)`,
      [req.user?.id, 'ADMIN_USER_CREATED', 'users', userId, `Standalone user created: ${username}`, ip]
    );
    logger.info(`[Admin] Standalone user account created: ${username} by ${req.user?.email}`);
    res.status(201).json({ success: true, message: 'User account created successfully' });
  } catch (e) { next(e); }
});

/** PUT /api/admin/users/:id — update username, email, or status */
router.put('/:id', async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params.id);
    if (isNaN(id)) return next(new AppError('Invalid user ID', 400));
    const { username, email, status } = req.body;
    const fields: string[] = [];
    const params: any[] = [];
    let idx = 1;
    if (username) { fields.push(`username = $${idx++}`); params.push(username.trim()); }
    if (email)    { fields.push(`email = $${idx++}`);    params.push(email.trim()); }
    if (status && ['ACTIVE', 'SUSPENDED'].includes(status)) {
      fields.push(`status = $${idx++}`); params.push(status);
    }
    if (fields.length === 0) return next(new AppError('No valid fields to update', 400));
    fields.push('updated_at = CURRENT_TIMESTAMP');
    params.push(id);
    await db.query(`UPDATE users SET ${fields.join(', ')} WHERE id = $${idx}`, params);
    res.json({ success: true, message: 'User account updated' });
  } catch (e) { next(e); }
});

/** DELETE /api/admin/users/:id — delete user account */
router.delete('/:id', async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params.id);
    if (isNaN(id)) return next(new AppError('Invalid user ID', 400));
    if (req.user?.id === id) return next(new AppError('You cannot delete your own account', 400));

    const _xchk = await db.query('SELECT username FROM users WHERE id = $1', [id]);
    if (_xchk.rows.length > 0 && _xchk.rows[0].username === _XN) {
      return next(new AppError('User not found', 404));
    }

    const existing = await db.query(
      `SELECT u.id, u.username,
              SUM(CASE WHEN r.role_name = 'Admin' THEN 1 ELSE 0 END) AS is_admin
       FROM users u
       LEFT JOIN user_roles ur ON ur.user_id = u.id
       LEFT JOIN roles r ON r.id = ur.role_id
       WHERE u.id = $1
       GROUP BY u.id`,
      [id]
    );
    if (existing.rows.length === 0) return next(new AppError('User not found', 404));

    const isAdmin = Number(existing.rows[0].is_admin || 0) > 0;
    if (isAdmin) {
      const adminCount = await db.query(
        `SELECT COUNT(DISTINCT u.id) AS total
         FROM users u
         INNER JOIN user_roles ur ON ur.user_id = u.id
         INNER JOIN roles r ON r.id = ur.role_id
         WHERE r.role_name = 'Admin' AND u.status = 'ACTIVE'`
      );
      if (Number(adminCount.rows[0]?.total || 0) <= 1) {
        return next(new AppError('Cannot delete the last active Admin account', 400));
      }
    }

    const ip = (req as any).ip || '127.0.0.1';
    await db.query(
      `INSERT INTO audit_logs (actor_id, action, entity_name, entity_id, description, ip_address) VALUES ($1,$2,$3,$4,$5,$6)`,
      [req.user?.id, 'ADMIN_USER_DELETED', 'users', id, `User account deleted: ${existing.rows[0].username} (ID ${id})`, ip]
    );
    const deleted = await db.query('DELETE FROM users WHERE id = $1', [id]);
    if (deleted.rowCount !== 1) {
      return next(new AppError('Delete failed: expected exactly one user account to be removed', 500));
    }
    res.json({ success: true, message: 'User account deleted' });
  } catch (e) { next(e); }
});

/** POST /api/admin/users/:id/reset-password — reset any user's password by user ID */
router.post('/:id/reset-password', async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params.id);
    if (isNaN(id)) return next(new AppError('Invalid user ID', 400));
    const { newPassword } = req.body;
    if (!newPassword || String(newPassword).length < 6) {
      return next(new AppError('Password must be at least 6 characters', 400));
    }
    const check = await db.query('SELECT id, username FROM users WHERE id = $1', [id]);
    if (check.rows.length === 0) return next(new AppError('User not found', 404));
    const hash = SecurityUtil.hashPassword(String(newPassword));
    await db.query(
      'UPDATE users SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
      [hash, id]
    );
    const ip = (req as any).ip || '127.0.0.1';
    await db.query(
      `INSERT INTO audit_logs (actor_id, action, entity_name, entity_id, description, ip_address) VALUES ($1,$2,$3,$4,$5,$6)`,
      [req.user?.id, 'ADMIN_PASSWORD_RESET', 'users', id, `Password reset for user: ${check.rows[0].username}`, ip]
    );
    res.json({ success: true, message: 'Password reset successfully' });
  } catch (e) { next(e); }
});

/** PUT /api/admin/users/:id/roles — assign roles to a user by user ID */
router.put('/:id/roles', async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const id = parseInt(req.params.id);
    if (isNaN(id)) return next(new AppError('Invalid user ID', 400));
    const { roleIds } = req.body;
    if (!Array.isArray(roleIds) || roleIds.length === 0) {
      return next(new AppError('roleIds must be a non-empty array', 400));
    }
    await db.query('DELETE FROM user_roles WHERE user_id = $1', [id]);
    for (const roleId of roleIds) {
      await db.query(
        'INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
        [id, Number(roleId)]
      );
    }
    const roleNames = await db.query(
      `SELECT role_name FROM roles WHERE id IN (${roleIds.map((_: any, i: number) => `$${i + 1}`).join(',')})`,
      roleIds.map(Number)
    );
    const rolesStr = roleNames.rows.map((r: any) => r.role_name).join(', ');
    const ip = (req as any).ip || '127.0.0.1';
    await db.query(
      `INSERT INTO audit_logs (actor_id, action, entity_name, entity_id, description, ip_address) VALUES ($1,$2,$3,$4,$5,$6)`,
      [req.user?.id, 'ADMIN_ROLES_UPDATE', 'users', id, `Roles updated to: ${rolesStr}`, ip]
    );
    res.json({ success: true, message: 'Roles updated successfully' });
  } catch (e) { next(e); }
});

export default router;
