import { Response, NextFunction } from 'express';
import { CustomRequest } from '../middleware/auth';
import { EmployeeService } from '../services/employee_service';
import { AppError } from '../middleware/error_handler';
import { db } from '../config/db';
import { SecurityUtil } from '../utils/security_util';
import { logger } from '../config/logger';

export class EmployeeController {
  private employeeService = new EmployeeService();

  /**
   * GET /api/employees/me
   */
  getMe = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const userId = req.user?.id;
      if (!userId) {
        return next(new AppError('Unauthorized: Access session details not found', 401));
      }

      const emp = await this.employeeService.getMe(userId);
      res.status(200).json({
        success: true,
        data: emp
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * GET /api/employees
   */
  getEmployees = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const emps = await this.employeeService.getEmployees();
      res.status(200).json({
        success: true,
        data: emps
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * GET /api/employees/:id
   */
  getEmployeeById = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return next(new AppError('Invalid Employee ID parameter', 400));
      }

      const emp = await this.employeeService.getEmployeeById(id);
      res.status(200).json({
        success: true,
        data: emp
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * POST /api/employees (Admin only)
   */
  createEmployee = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { employeeCode, firstName, lastName, phone, designation, departmentId, shiftId,
              joiningDate, employmentStatus, username, email, password, roles } = req.body;

      if (!employeeCode || !firstName || !lastName) {
        return next(new AppError('Employee Code, First Name and Last Name are required', 400));
      }

      const newEmp = await this.employeeService.createEmployee({
        employeeCode,
        firstName,
        lastName,
        phone: phone || '',
        designation: designation || '',
        departmentId: departmentId ? parseInt(departmentId) : undefined,
        shiftId: shiftId ? parseInt(shiftId) : undefined,
        joiningDate: joiningDate || new Date().toISOString().split('T')[0],
        employmentStatus: employmentStatus || 'ACTIVE'
      });

      const ip = (req as any).ip || '127.0.0.1';

      // Optionally create login account if credentials provided
      if (username && email && password) {
        if (String(password).length < 6) {
          return next(new AppError('Login password must be at least 6 characters', 400));
        }
        const existing = await db.query(
          'SELECT id FROM users WHERE username = $1 OR email = $2',
          [username.trim(), email.trim()]
        );
        if (existing.rows.length > 0) {
          return next(new AppError('Username or email is already taken by another account', 400));
        }

        const hash = SecurityUtil.hashPassword(String(password));
        await db.query(
          `INSERT INTO users (employee_id, username, email, password_hash, status, shift_id)
           VALUES ($1, $2, $3, $4, 'ACTIVE', $5)`,
          [newEmp.id, username.trim(), email.trim(), hash, newEmp.shiftId || null]
        );

        const userRes = await db.query('SELECT id FROM users WHERE username = $1', [username.trim()]);
        if (userRes.rows.length > 0) {
          const userId = userRes.rows[0].id;
          const roleList: string[] = Array.isArray(roles) && roles.length > 0 ? roles : ['Employee'];
          for (const roleName of roleList) {
            const roleRes = await db.query('SELECT id FROM roles WHERE role_name = $1', [roleName]);
            if (roleRes.rows.length > 0) {
              await db.query(
                'INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
                [userId, roleRes.rows[0].id]
              );
            }
          }
          await db.query(
            `INSERT INTO audit_logs (actor_id, action, entity_name, entity_id, description, ip_address)
             VALUES ($1,$2,$3,$4,$5,$6)`,
            [req.user?.id, 'ADMIN_EMPLOYEE_CREATED', 'employees', newEmp.id,
             `Employee ${newEmp.employeeCode} created with login: ${username}`, ip]
          );
          logger.info(`[Admin] Employee ${newEmp.employeeCode} created with login account: ${username}`);
        }
      } else {
        await db.query(
          `INSERT INTO audit_logs (actor_id, action, entity_name, entity_id, description, ip_address)
           VALUES ($1,$2,$3,$4,$5,$6)`,
          [req.user?.id, 'ADMIN_EMPLOYEE_CREATED', 'employees', newEmp.id,
           `Employee ${newEmp.employeeCode} created (no login)`, ip]
        );
      }

      res.status(201).json({
        success: true,
        message: (username && email && password)
          ? 'Employee profile and login account created successfully'
          : 'Employee profile created. Add login credentials via "Manage Roles" and "Reset Password".',
        data: newEmp
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * PUT /api/employees/:id (Admin only)
   */
  updateEmployee = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return next(new AppError('Invalid Employee ID parameter', 400));
      }

      const updated = await this.employeeService.updateEmployee(id, req.body);
      res.status(200).json({
        success: true,
        message: 'Employee profile updated successfully',
        data: updated
      });
    } catch (error) {
      next(error);
    }
  };

  /**
   * DELETE /api/employees/:id (Admin only)
   */
  deleteEmployee = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) {
        return next(new AppError('Invalid Employee ID parameter', 400));
      }

      await this.employeeService.deleteEmployee(id);
      res.status(200).json({
        success: true,
        message: 'Employee profile deleted successfully'
      });
    } catch (error) {
      next(error);
    }
  };

  resetPassword = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) return next(new AppError('Invalid Employee ID', 400));
      const { newPassword } = req.body;
      if (!newPassword || String(newPassword).length < 6) return next(new AppError('Password must be at least 6 characters', 400));
      const userResult = await db.query('SELECT id, username FROM users WHERE employee_id = $1', [id]);
      if (userResult.rows.length === 0) return next(new AppError('No user account linked to this employee', 404));
      const userId = userResult.rows[0].id;
      const hash = SecurityUtil.hashPassword(String(newPassword));
      await db.query('UPDATE users SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', [hash, userId]);
      const _ip = (req as any).ip || '127.0.0.1';
      await db.query(`INSERT INTO audit_logs (actor_id, action, entity_name, entity_id, description, ip_address) VALUES ($1,$2,$3,$4,$5,$6)`,
        [req.user?.id, 'ADMIN_PASSWORD_RESET', 'users', userId, `Password reset for user: ${userResult.rows[0].username}`, _ip]);
      logger.info(`[Admin] Password reset for employee ${id} by ${req.user?.email}`);
      res.json({ success: true, message: 'Password reset successfully' });
    } catch (error) { next(error); }
  };

  getEmployeeRoles = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) return next(new AppError('Invalid Employee ID', 400));
      const allRoles = await db.query('SELECT id, role_name FROM roles ORDER BY id');
      const assignedResult = await db.query(`
        SELECT r.id, r.role_name FROM roles r
        INNER JOIN user_roles ur ON ur.role_id = r.id
        INNER JOIN users u ON u.id = ur.user_id
        WHERE u.employee_id = $1`, [id]);
      const userResult = await db.query('SELECT id, username, email, status FROM users WHERE employee_id = $1', [id]);
      res.json({ success: true, data: { allRoles: allRoles.rows, assignedRoles: assignedResult.rows, userAccount: userResult.rows[0] || null } });
    } catch (error) { next(error); }
  };

  updateEmployeeRoles = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) return next(new AppError('Invalid Employee ID', 400));
      const { roleIds } = req.body;
      if (!Array.isArray(roleIds) || roleIds.length === 0) return next(new AppError('roleIds must be a non-empty array', 400));

      // HR can only assign Employee (4) and Manager (3) roles, not Admin (1) or HR (2)
      const isHROnly = req.user?.roles?.includes('HR') && !req.user?.roles?.includes('Admin');
      if (isHROnly) {
        const privilegedRoles = await db.query(`SELECT id FROM roles WHERE role_name IN ('Admin','HR')`);
        const privilegedIds = privilegedRoles.rows.map((r: any) => Number(r.id));
        const forbidden = roleIds.map(Number).filter((rid: number) => privilegedIds.includes(rid));
        if (forbidden.length > 0) {
          return next(new AppError('HR users cannot assign Admin or HR roles. Contact a system administrator.', 403));
        }
      }

      const userResult = await db.query('SELECT id, username FROM users WHERE employee_id = $1', [id]);
      if (userResult.rows.length === 0) return next(new AppError('No user account linked to this employee', 404));
      const userId = userResult.rows[0].id;
      await db.query('DELETE FROM user_roles WHERE user_id = $1', [userId]);
      for (const roleId of roleIds) {
        await db.query('INSERT INTO user_roles (user_id, role_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [userId, Number(roleId)]);
      }
      const numIds = roleIds.map(Number);
      const placeholders = numIds.map((_: number, i: number) => `$${i + 1}`).join(',');
      const roleNames = await db.query(`SELECT role_name FROM roles WHERE id IN (${placeholders})`, numIds);
      const rolesStr = roleNames.rows.map((r: any) => r.role_name).join(', ');
      const _ip = (req as any).ip || '127.0.0.1';
      await db.query(`INSERT INTO audit_logs (actor_id, action, entity_name, entity_id, description, ip_address) VALUES ($1,$2,$3,$4,$5,$6)`,
        [req.user?.id, 'ADMIN_ROLES_UPDATE', 'users', userId, `Roles set to: ${rolesStr} for ${userResult.rows[0].username}`, _ip]);
      res.json({ success: true, message: 'Roles updated successfully' });
    } catch (error) { next(error); }
  };

  updateStatus = async (req: CustomRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const id = parseInt(req.params.id);
      if (isNaN(id)) return next(new AppError('Invalid Employee ID', 400));
      const { status } = req.body;
      if (!['ACTIVE', 'INACTIVE', 'SUSPENDED'].includes(status)) return next(new AppError('Status must be ACTIVE, INACTIVE, or SUSPENDED', 400));
      await db.query('UPDATE employees SET employment_status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', [status, id]);
      const userStatus = status === 'ACTIVE' ? 'ACTIVE' : 'SUSPENDED';
      await db.query('UPDATE users SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE employee_id = $2', [userStatus, id]);
      const _ip = (req as any).ip || '127.0.0.1';
      await db.query(`INSERT INTO audit_logs (actor_id, action, entity_name, entity_id, description, ip_address) VALUES ($1,$2,$3,$4,$5,$6)`,
        [req.user?.id, 'ADMIN_STATUS_CHANGE', 'employees', id, `Employment status changed to: ${status}`, _ip]);
      res.json({ success: true, message: `Employee status updated to ${status}` });
    } catch (error) { next(error); }
  };
}
