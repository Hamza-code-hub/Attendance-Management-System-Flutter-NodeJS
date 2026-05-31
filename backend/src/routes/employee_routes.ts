import { Router } from 'express';
import { EmployeeController } from '../controllers/employee_controller';
import { protect, authorize } from '../middleware/auth';

const router = Router();
const controller = new EmployeeController();

// Profile me access (any authenticated user)
router.get('/me', protect, controller.getMe);

// Admin restricted endpoints
router.get('/', protect, authorize('Admin', 'HR'), controller.getEmployees);
router.get('/:id', protect, authorize('Admin', 'HR'), controller.getEmployeeById);
router.post('/', protect, authorize('Admin'), controller.createEmployee);
router.put('/:id', protect, authorize('Admin'), controller.updateEmployee);
router.delete('/:id', protect, authorize('Admin'), controller.deleteEmployee);

// Admin account management
router.post('/:id/reset-password', protect, authorize('Admin', 'HR'), controller.resetPassword);
router.get('/:id/roles', protect, authorize('Admin', 'HR'), controller.getEmployeeRoles);
router.put('/:id/roles', protect, authorize('Admin', 'HR'), controller.updateEmployeeRoles);
router.put('/:id/status', protect, authorize('Admin', 'HR'), controller.updateStatus);

export default router;
