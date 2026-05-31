import { Router } from 'express';
import { OvertimeController } from '../controllers/overtime_controller';
import { protect, authorize } from '../middleware/auth';

const router = Router();
const controller = new OvertimeController();

// Employee routes
router.post('/request', protect, controller.request);
router.get('/history', protect, controller.history);

// HR/Admin/Manager routes. Managers are scoped to their own department in service layer.
router.get('/pending', protect, authorize('HR', 'Admin', 'Manager'), controller.pending);
router.post('/review/:id', protect, authorize('HR', 'Admin', 'Manager'), controller.review);

export default router;
