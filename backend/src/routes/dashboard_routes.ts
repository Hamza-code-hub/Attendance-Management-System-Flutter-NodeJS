import { Router } from 'express';
import { DashboardController } from '../controllers/dashboard_controller';
import { protect, authorize } from '../middleware/auth';

const router = Router();
const ctrl = new DashboardController();

router.use(protect);
router.use(authorize('HR', 'Admin', 'Manager'));

router.get('/summary', ctrl.summary);
router.get('/present', ctrl.present);
router.get('/late', ctrl.late);
router.get('/pending-approvals', ctrl.pendingApprovals);
router.get('/attendance-monitor', ctrl.attendanceMonitor);
router.get('/shift-monitor', ctrl.shiftMonitor);
router.get('/employee-directory', ctrl.employeeDirectory);

export default router;
