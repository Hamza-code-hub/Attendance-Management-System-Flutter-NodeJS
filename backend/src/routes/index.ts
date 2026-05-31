import { Router } from 'express';
import attendanceRoutes from './attendance_routes';
import authRoutes from './auth_routes';
import employeeRoutes from './employee_routes';
import shiftRoutes from './shift_routes';
import overtimeRoutes from './overtime_routes';
import adjustmentRoutes from './adjustment_routes';
import auditLogRoutes from './audit_log_routes';
import dashboardRoutes from './dashboard_routes';
import reportRoutes from './report_routes';
import settingsRoutes from './settings_routes';
import healthRoutes from './health_routes';
import adminUserRoutes from './admin_user_routes';
import { exportLimiter } from '../middleware/rate_limiter';

const rootRouter = Router();

// Core Modules
rootRouter.use('/auth', authRoutes);
rootRouter.use('/attendance', attendanceRoutes);
rootRouter.use('/employees', employeeRoutes);
rootRouter.use('/shifts', shiftRoutes);
rootRouter.use('/overtime', overtimeRoutes);
rootRouter.use('/adjustments', adjustmentRoutes);
rootRouter.use('/audit-logs', auditLogRoutes);

// Phase 6: HR Dashboard
rootRouter.use('/dashboard', dashboardRoutes);

// Phase 7: Reports & Exports (export endpoints have stricter rate limiting)
rootRouter.use('/reports', reportRoutes);

// Phase 8: System Settings & Health
rootRouter.use('/settings', settingsRoutes);
rootRouter.use('/health', healthRoutes);

// Admin: User Account Management
rootRouter.use('/admin/users', adminUserRoutes);

export default rootRouter;
