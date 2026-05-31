import { ShiftRepository, DBShift } from '../repositories/shift_repository';
import { AppError } from '../middleware/error_handler';
import { logger } from '../config/logger';

export class ShiftService {
  private shiftRepo = new ShiftRepository();

  /**
   * Fetch all shifts
   */
  async getShifts(): Promise<DBShift[]> {
    return await this.shiftRepo.findAll();
  }

  /**
   * Fetch shift by ID
   */
  async getShiftById(id: number): Promise<DBShift> {
    const shift = await this.shiftRepo.findById(id);
    if (!shift) {
      throw new AppError('Shift schedule configuration not found', 404);
    }
    return shift;
  }

  /**
   * Create new shift schedule
   */
  async createShift(shift: Omit<DBShift, 'id' | 'createdAt' | 'updatedAt'>): Promise<DBShift> {
    logger.info(`[Shift Service] Admin creating shift schedule: ${shift.shiftName}`);
    
    // Check duplicates
    const list = await this.shiftRepo.findAll();
    const isDuplicate = list.some(s => s.shiftName === shift.shiftName);
    if (isDuplicate) {
      throw new AppError(`Conflict: Shift Name ${shift.shiftName} already exists`, 400);
    }

    const id = await this.shiftRepo.create(shift);
    return await this.getShiftById(id);
  }

  /**
   * Update shift schedule details
   */
  async updateShift(id: number, shift: Partial<Omit<DBShift, 'id' | 'createdAt' | 'updatedAt'>>): Promise<DBShift> {
    logger.info(`[Shift Service] Admin modifying shift schedule ID: ${id}`);
    
    await this.getShiftById(id);

    if (shift.shiftName) {
      const list = await this.shiftRepo.findAll();
      const isDuplicate = list.some(s => s.shiftName === shift.shiftName && s.id !== id);
      if (isDuplicate) {
        throw new AppError(`Conflict: Shift Name ${shift.shiftName} already exists`, 400);
      }
    }

    await this.shiftRepo.update(id, shift);
    return await this.getShiftById(id);
  }

  /**
   * Delete a shift configuration
   */
  async deleteShift(id: number): Promise<void> {
    logger.warn(`[Shift Service] Admin deleting shift ID: ${id}`);
    await this.getShiftById(id);
    await this.shiftRepo.delete(id);
  }
}
