import { db } from '../config/db';

export interface DBUser {
  id: number;
  employeeId?: string;
  username: string;
  email: string;
  passwordHash: string;
  status: string;
  lastLogin?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface DBSession {
  id: string;
  userId: number;
  refreshTokenHash: string;
  expiresAt: Date;
  deviceInfo?: string;
  createdAt: Date;
}

export class AuthRepository {
  /**
   * Find user by username or email
   */
  async findByUsernameOrEmail(identifier: string): Promise<any | null> {
    const query = `
      SELECT u.*, e.employment_status FROM users u
      LEFT JOIN employees e ON e.id = u.employee_id
      WHERE u.username = $1 OR u.email = $2
    `;
    const res = await db.query(query, [identifier, identifier]);
    if (res.rows.length === 0) return null;
    
    const row = res.rows[0];
    return {
      id: row.id,
      employeeId: row.employee_id,
      username: row.username,
      email: row.email,
      passwordHash: row.password_hash,
      status: row.status,
      lastLogin: row.last_login ? new Date(row.last_login) : undefined,
      createdAt: new Date(row.created_at),
      updatedAt: new Date(row.updated_at),
      employmentStatus: row.employment_status
    };
  }

  /**
   * Find user by immutable database ID
   */
  async findById(userId: number): Promise<any | null> {
    const query = `
      SELECT u.*, e.employment_status FROM users u
      LEFT JOIN employees e ON e.id = u.employee_id
      WHERE u.id = $1
    `;
    const res = await db.query(query, [userId]);
    if (res.rows.length === 0) return null;

    const row = res.rows[0];
    return {
      id: row.id,
      employeeId: row.employee_id,
      username: row.username,
      email: row.email,
      passwordHash: row.password_hash,
      status: row.status,
      lastLogin: row.last_login ? new Date(row.last_login) : undefined,
      createdAt: new Date(row.created_at),
      updatedAt: new Date(row.updated_at),
      employmentStatus: row.employment_status
    };
  }

  /**
   * Fetch roles assigned to a user
   */
  async getUserRoles(userId: number): Promise<string[]> {
    const query = `
      SELECT r.role_name FROM roles r
      INNER JOIN user_roles ur ON ur.role_id = r.id
      WHERE ur.user_id = $1
    `;
    const res = await db.query(query, [userId]);
    return res.rows.map((row) => row.role_name);
  }

  /**
   * Update last login timestamp
   */
  async updateLastLogin(userId: number): Promise<void> {
    const query = `
      UPDATE users SET last_login = CURRENT_TIMESTAMP
      WHERE id = $1
    `;
    await db.query(query, [userId]);
  }

  /**
   * Update password hash
   */
  async updatePasswordHash(userId: number, passwordHash: string): Promise<void> {
    const query = `
      UPDATE users SET password_hash = $1, updated_at = CURRENT_TIMESTAMP
      WHERE id = $2
    `;
    await db.query(query, [passwordHash, userId]);
  }

  /**
   * Create new user record (For auto-seeder & admin endpoints)
   */
  async createUser(user: Omit<DBUser, 'id' | 'createdAt' | 'updatedAt'>): Promise<number> {
    const query = `
      INSERT INTO users (employee_id, username, email, password_hash, status)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING id
    `;
    const res = await db.query(query, [user.employeeId, user.username, user.email, user.passwordHash, user.status]);
    return res.rows[0].id;
  }

  /**
   * Assign a role to a user
   */
  async assignRole(userId: number, roleName: string): Promise<void> {
    // 1. Fetch role ID by name
    const roleRes = await db.query('SELECT id FROM roles WHERE role_name = $1', [roleName]);
    let roleId: number;
    
    if (roleRes.rows.length === 0) {
      // Create role if missing
      const insRes = await db.query('INSERT INTO roles (role_name) VALUES ($1) RETURNING id', [roleName]);
      roleId = insRes.rows[0].id;
    } else {
      roleId = roleRes.rows[0].id;
    }

    // 2. Map link
    const query = `
      INSERT INTO user_roles (user_id, role_id)
      VALUES ($1, $2)
      ON CONFLICT DO NOTHING
    `;
    await db.query(query, [userId, roleId]);
  }

  /**
   * Save refresh token session in database
   */
  async saveSession(userId: number, refreshTokenHash: string, expiresAt: Date, deviceInfo?: string): Promise<void> {
    const id = require('crypto').randomUUID();
    const query = `
      INSERT INTO sessions (id, user_id, refresh_token_hash, expires_at, device_info)
      VALUES ($1, $2, $3, $4, $5)
    `;
    await db.query(query, [id, userId, refreshTokenHash, expiresAt.toISOString(), deviceInfo || 'Unknown Local Host']);
  }

  /**
   * Find session by refresh token hash
   */
  async findSession(refreshTokenHash: string): Promise<DBSession | null> {
    const query = 'SELECT * FROM sessions WHERE refresh_token_hash = $1';
    const res = await db.query(query, [refreshTokenHash]);
    if (res.rows.length === 0) return null;
    
    const row = res.rows[0];
    return {
      id: row.id,
      userId: row.user_id,
      refreshTokenHash: row.refresh_token_hash,
      expiresAt: new Date(row.expires_at),
      deviceInfo: row.device_info,
      createdAt: new Date(row.created_at)
    };
  }

  /**
   * Delete a session by refresh token hash (Logout / revocation)
   */
  async deleteSession(refreshTokenHash: string): Promise<void> {
    const query = 'DELETE FROM sessions WHERE refresh_token_hash = $1';
    await db.query(query, [refreshTokenHash]);
  }

  /**
   * Delete all sessions for a user (Password changes force logout everywhere)
   */
  async deleteAllUserSessions(userId: number): Promise<void> {
    const query = 'DELETE FROM sessions WHERE user_id = $1';
    await db.query(query, [userId]);
  }

  /**
   * Create an audit log entry in the immutable audit table
   */
  async createAuditLog(actorId: number | null, action: string, description: string, ipAddress: string): Promise<void> {
    const query = `
      INSERT INTO audit_logs (actor_id, action, entity_name, description, ip_address)
      VALUES ($1, $2, 'users', $3, $4)
    `;
    await db.query(query, [actorId, action, description, ipAddress]);
  }
}
