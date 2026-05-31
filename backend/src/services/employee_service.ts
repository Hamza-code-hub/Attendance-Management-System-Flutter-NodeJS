import { EmployeeRepository, DBEmployee } from '../repositories/employee_repository';
import { AppError } from '../middleware/error_handler';
import { logger } from '../config/logger';

export class EmployeeService {
  private employeeRepo = new EmployeeRepository();

  /**
   * Fetch admin list of employees
   */
  async getEmployees(): Promise<DBEmployee[]> {
    return await this.employeeRepo.findAll();
  }

  /**
   * Fetch employee details by ID
   */
  async getEmployeeById(id: number): Promise<DBEmployee> {
    const emp = await this.employeeRepo.findById(id);
    if (!emp) {
      throw new AppError('Employee profile not found', 404);
    }
    return emp;
  }

  /**
   * Fetch self profile (for me endpoint)
   */
  async getMe(userId: number): Promise<DBEmployee> {
    const emp = await this.employeeRepo.findByUserId(userId);
    if (!emp) {
      throw new AppError('Employee session details not found', 404);
    }
    return emp;
  }

  /**
   * Create new employee record
   */
  async createEmployee(emp: Omit<DBEmployee, 'id' | 'createdAt' | 'updatedAt'>): Promise<DBEmployee> {
    logger.info(`[Employee Service] Admin creating new employee with code: ${emp.employeeCode}`);
    
    // Check duplicate code
    const list = await this.employeeRepo.findAll();
    const isDuplicate = list.some(e => e.employeeCode === emp.employeeCode);
    if (isDuplicate) {
      throw new AppError(`Conflict: Employee Code ${emp.employeeCode} already exists`, 400);
    }

    const id = await this.employeeRepo.create(emp);
    return await this.getEmployeeById(id);
  }

  /**
   * Update employee details
   */
  async updateEmployee(id: number, emp: Partial<Omit<DBEmployee, 'id' | 'createdAt' | 'updatedAt'>>): Promise<DBEmployee> {
    logger.info(`[Employee Service] Admin modifying employee ID: ${id}`);
    
    // Verify existence
    await this.getEmployeeById(id);

    if (emp.employeeCode) {
      const list = await this.employeeRepo.findAll();
      const isDuplicate = list.some(e => e.employeeCode === emp.employeeCode && e.id !== id);
      if (isDuplicate) {
        throw new AppError(`Conflict: Employee Code ${emp.employeeCode} already exists`, 400);
      }
    }

    await this.employeeRepo.update(id, emp);
    return await this.getEmployeeById(id);
  }

  /**
   * Delete an employee record (Case 2: Attendance records remain due to database FK ON DELETE SET NULL / logs referencing user table directly or cascade handles appropriately, and history stays complete!)
   */
  async deleteEmployee(id: number): Promise<void> {
    logger.warn(`[Employee Service] Admin deleting employee ID: ${id}`);
    await this.getEmployeeById(id);
    await this.employeeRepo.delete(id);
  }
}
