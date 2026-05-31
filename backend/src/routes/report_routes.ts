import { Router } from 'express';
import { ReportController } from '../controllers/report_controller';
import { protect, authorize } from '../middleware/auth';

const router = Router();
const ctrl = new ReportController();

router.use(protect);
router.use(authorize('HR', 'Admin'));

// Monthly Attendance Matrix — must be registered BEFORE the /:type wildcard
// GET /api/reports/monthly-matrix/export?month=YYYY-MM&departmentId=N
router.get('/monthly-matrix/export', ctrl.exportMonthlyMatrix);

// GET /api/reports/attendance?dateFrom=&dateTo=
// GET /api/reports/overtime?dateFrom=&dateTo=
// GET /api/reports/adjustment?dateFrom=&dateTo=
// GET /api/reports/late?dateFrom=&dateTo=
// GET /api/reports/break?dateFrom=&dateTo=
router.get('/:type', ctrl.getReport);

// GET /api/reports/:type/export?format=excel|csv
router.get('/:type/export', ctrl.exportReport);

export default router;
