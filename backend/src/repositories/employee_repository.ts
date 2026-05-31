import { db } from '../config/db';

export interface DBEmployee {
  id: number;
  employeeCode: string;
  firstName: string;
  lastName: string;
  phone?: string;
  designation?: string;
  departmentId?: number;
  shiftId?: number;
  joiningDate: string;
  employmentStatus: 'ACTIVE' | 'INACTIVE' | 'SUSPENDED';
  createdAt: Date;
  updatedAt: Date;
  departmentName?: string;
  shiftName?: string;
  // Linked user account fields
  username?: string;
  email?: string;
  userId?: number;
  roleNames?: string;  // comma-separated role names
}

export class EmployeeRepository {
  
  /**
   * Fetch all employees joining departments, shifts, user account, and roles
   */
  async findAll(): Promise<DBEmployee[]> {
    const query = `
      SELECT e.*, d.department_name, s.shift_name,
             u.id AS user_id, u.username, u.email,
             GROUP_CONCAT(r.role_name, ', ') AS role_names
      FROM employees e
      LEFT JOIN departments d ON d.id = e.department_id
      LEFT JOIN shifts s ON s.id = e.shift_id
      LEFT JOIN users u ON u.employee_id = e.id
      LEFT JOIN user_roles ur ON ur.user_id = u.id
      LEFT JOIN roles r ON r.id = ur.role_id
      GROUP BY e.id
      ORDER BY e.employee_code ASC
    `;
    const res = await db.query(query);
    return res.rows.map((row) => this.mapRowToEmployee(row));
  }

  /**
   * Fetch employee by primary ID
   */
  async findById(id: number): Promise<DBEmployee | null> {
    const query = `
      SELECT e.*, d.department_name, s.shift_name 
      FROM employees e
      LEFT JOIN departments d ON d.id = e.department_id
      LEFT JOIN shifts s ON s.id = e.shift_id
      WHERE e.id = $1
    `;
    const res = await db.query(query, [id]);
    if (res.rows.length === 0) return null;
    return this.mapRowToEmployee(res.rows[0]);
  }

  /**
   * Fetch employee by associated User ID
   */
  async findByUserId(userId: number): Promise<DBEmployee | null> {
    const query = `
      SELECT e.*, d.department_name, s.shift_name 
      FROM employees e
      INNER JOIN users u ON u.employee_id = e.id
      LEFT JOIN departments d ON d.id = e.department_id
      LEFT JOIN shifts s ON s.id = e.shift_id
      WHERE u.id = $1
    `;
    const res = await db.query(query, [userId]);
    if (res.rows.length === 0) return null;
    return this.mapRowToEmployee(res.rows[0]);
  }

  /**
   * Create a new employee record
   */
  async create(emp: Omit<DBEmployee, 'id' | 'createdAt' | 'updatedAt'>): Promise<number> {
    const query = `
      INSERT INTO employees (
        employee_code, first_name, last_name, phone, designation, 
        department_id, shift_id, joining_date, employment_status
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING id
    `;
    const values = [
      emp.employeeCode, emp.firstName, emp.lastName, emp.phone, emp.designation,
      emp.departmentId || null, emp.shiftId || null, emp.joiningDate, emp.employmentStatus
    ];
    const res = await db.query(query, values);
    return res.rows[0].id;
  }

  /**
   * Update an employee record details
   */
  async update(id: number, emp: Partial<Omit<DBEmployee, 'id' | 'createdAt' | 'updatedAt'>>): Promise<void> {
    const setClause: string[] = [];
    const values: any[] = [];
    let paramIndex = 1;

    Object.entries(emp).forEach(([key, val]) => {
      // Map camelCase keys back to snake_case column names
      const colName = this.camelToSnake(key);
      setClause.push(`${colName} = $${paramIndex}`);
      values.push(val === undefined ? null : val);
      paramIndex++;
    });

    if (setClause.length === 0) return;

    values.push(id);
    const query = `
      UPDATE employees
      SET ${setClause.join(', ')}, updated_at = CURRENT_TIMESTAMP
      WHERE id = $${paramIndex}
    `;
    await db.query(query, values);
  }

  /**
   * Delete an employee record
   */
  async delete(id: number): Promise<void> {
    // Delete associated user first due to CASCADE, or rely on cascade
    const query = 'DELETE FROM employees WHERE id = $1';
    await db.query(query, [id]);
  }

  private mapRowToEmployee(row: any): DBEmployee {
    return {
      id: row.id,
      employeeCode: row.employee_code,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      designation: row.designation,
      departmentId: row.department_id,
      shiftId: row.shift_id,
      joiningDate: typeof row.joining_date === 'string' ? row.joining_date : row.joining_date.toISOString().split('T')[0],
      employmentStatus: row.employment_status,
      createdAt: new Date(row.created_at),
      updatedAt: new Date(row.updated_at),
      departmentName: row.department_name,
      shiftName: row.shift_name,
      username: row.username ?? undefined,
      email: row.email ?? undefined,
      userId: row.user_id ?? undefined,
      roleNames: row.role_names ?? undefined
    };
  }

  private camelToSnake(str: string): string {
    return str.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);
  }
}
