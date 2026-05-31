import { Router } from 'express';
import { AuthController } from '../controllers/auth_controller';
import { protect } from '../middleware/auth';

const router = Router();
const controller = new AuthController();

// Public auth endpoints
router.post('/login', controller.login);
router.post('/refresh', controller.refresh);
router.post('/logout', controller.logout);

// Protected auth endpoints
router.get('/me', protect, controller.me);
router.post('/change-password', protect, controller.changePassword);

export default router;
