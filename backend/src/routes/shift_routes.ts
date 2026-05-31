import { Router } from 'express';
import { ShiftController } from '../controllers/shift_controller';
import { protect, authorize } from '../middleware/auth';

const router = Router();
const controller = new ShiftController();

// Open to standard authenticated employees to review parameters
router.get('/', protect, controller.getShifts);
router.get('/:id', protect, controller.getShiftById);

// Admin creations and updates
router.post('/', protect, authorize('Admin'), controller.createShift);
router.put('/:id', protect, authorize('Admin'), controller.updateShift);
router.delete('/:id', protect, authorize('Admin'), controller.deleteShift);

export default router;
