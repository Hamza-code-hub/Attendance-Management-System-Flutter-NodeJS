import { db } from '../config/db';

export interface DBShift {
  id: number;
  shiftName: string;
  shiftStart: string;
  shiftEnd: string;
  graceMinutes: number;
  nightShiftEnabled: boolean;
  allowOvertime: boolean;
  active: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export class ShiftRepository {
  
  /**
   * Fetch all shifts
   */
  async findAll(): Promise<DBShift[]> {
    const query = 'SELECT * FROM shifts ORDER BY id ASC';
    const res = await db.query(query);
    return res.rows.map((row) => this.mapRowToShift(row));
  }

  /**
   * Fetch shift by ID
   */
  async findById(id: number): Promise<DBShift | null> {
    const query = 'SELECT * FROM shifts WHERE id = $1';
    const res = await db.query(query, [id]);
    if (res.rows.length === 0) return null;
    return this.mapRowToShift(res.rows[0]);
  }

  /**
   * Create new shift
   */
  async create(shift: Omit<DBShift, 'id' | 'createdAt' | 'updatedAt'>): Promise<number> {
    const query = `
      INSERT INTO shifts (
        shift_name, shift_start, shift_end, grace_minutes, night_shift_enabled, allow_overtime, active
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING id
    `;
    const values = [
      shift.shiftName, shift.shiftStart, shift.shiftEnd, shift.graceMinutes,
      shift.nightShiftEnabled, shift.allowOvertime, shift.active
    ];
    const res = await db.query(query, values);
    return res.rows[0].id;
  }

  /**
   * Update shift details
   */
  async update(id: number, shift: Partial<Omit<DBShift, 'id' | 'createdAt' | 'updatedAt'>>): Promise<void> {
    const setClause: string[] = [];
    const values: any[] = [];
    let paramIndex = 1;

    Object.entries(shift).forEach(([key, val]) => {
      const colName = this.camelToSnake(key);
      setClause.push(`${colName} = $${paramIndex}`);
      values.push(val === undefined ? null : val);
      paramIndex++;
    });

    if (setClause.length === 0) return;

    values.push(id);
    const query = `
      UPDATE shifts
      SET ${setClause.join(', ')}, updated_at = CURRENT_TIMESTAMP
      WHERE id = $${paramIndex}
    `;
    await db.query(query, values);
  }

  /**
   * Delete shift
   */
  async delete(id: number): Promise<void> {
    const query = 'DELETE FROM shifts WHERE id = $1';
    await db.query(query, [id]);
  }

  private mapRowToShift(row: any): DBShift {
    return {
      id: row.id,
      shiftName: row.shift_name,
      shiftStart: row.shift_start,
      shiftEnd: row.shift_end,
      graceMinutes: row.grace_minutes,
      nightShiftEnabled: row.night_shift_enabled,
      allowOvertime: row.allow_overtime,
      active: row.active,
      createdAt: new Date(row.created_at),
      updatedAt: new Date(row.updated_at)
    };
  }

  private camelToSnake(str: string): string {
    return str.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);
  }
}
