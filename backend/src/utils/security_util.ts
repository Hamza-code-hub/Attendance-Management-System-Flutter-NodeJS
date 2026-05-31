import crypto from 'crypto';
import jwt from 'jsonwebtoken';

const ITERATIONS = 100000;
const KEY_LENGTH = 64;
const DIGEST = 'sha512';

export const SecurityUtil = {
  /**
   * Hashes a raw password using standard PBKDF2/SHA-512
   */
  hashPassword: (password: string): string => {
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.pbkdf2Sync(
      password,
      salt,
      ITERATIONS,
      KEY_LENGTH,
      DIGEST
    ).toString('hex');
    
    // Combine salt and hash formatted with delimiter
    return `${salt}:${hash}`;
  },

  /**
   * Verifies a raw password against the stored salt:hash string
   */
  verifyPassword: (password: string, storedHash: string): boolean => {
    const parts = storedHash.split(':');
    if (parts.length !== 2) return false;
    
    const [salt, originalHash] = parts;
    const computedHash = crypto.pbkdf2Sync(
      password,
      salt,
      ITERATIONS,
      KEY_LENGTH,
      DIGEST
    ).toString('hex');
    
    return crypto.timingSafeEqual(
      Buffer.from(computedHash, 'hex'),
      Buffer.from(originalHash, 'hex')
    );
  },

  /**
   * Hashes a Refresh Token string (SHA-256 is secure for simple fast DB checking)
   */
  hashRefreshToken: (token: string): string => {
    return crypto.createHash('sha256').update(token).digest('hex');
  },

  /**
   * Generates a unique secure Refresh Token string
   */
  generateRefreshToken: (): string => {
    return crypto.randomBytes(40).toString('hex');
  },

  /**
   * Sign access JWT
   */
  signAccessToken: (payload: object): string => {
    const secret = process.env.JWT_SECRET || 'office_local_deployment_jwt_secret_key_2026_xyz123';
    const expireHours = process.env.JWT_EXPIRE_HOURS || '12';
    
    return jwt.sign(payload, secret, {
      expiresIn: `${expireHours}h` as any,
    });
  },

  /**
   * Verify access JWT
   */
  verifyAccessToken: (token: string): any => {
    const secret = process.env.JWT_SECRET || 'office_local_deployment_jwt_secret_key_2026_xyz123';
    return jwt.verify(token, secret);
  }
};
