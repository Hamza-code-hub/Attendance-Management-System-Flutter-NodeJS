import { Router, Response, NextFunction } from 'express';
import { protect, authorize, CustomRequest } from '../middleware/auth';
import { db } from '../config/db';

const router = Router();

function buildAuditConditions(from?: string, to?: string, action?: string, username?: string) {
  const conditions: string[] = [];
  const params: any[] = [];
  let idx = 1;
  if (from)     { conditions.push(`al.created_at >= $${idx++}`); params.push(from); }
  if (to)       { conditions.push(`al.created_at <= date($${idx++}, '+1 day')`);  params.push(to); }
  if (action)   { conditions.push(`UPPER(al.action) LIKE $${idx++}`);             params.push(`%${action.toUpperCase()}%`); }
  if (username) { conditions.push(`UPPER(u.username) LIKE $${idx++}`);            params.push(`%${username.toUpperCase()}%`); }
  return { conditions, params, nextIdx: idx };
}

// GET /audit-logs — paginated list
router.get('/', protect, authorize('Admin'), async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const { from, to, action, username, page = '1', limit = '50' } = req.query as Record<string, string>;
    const pageNum  = Math.max(1, parseInt(page)  || 1);
    const limitNum = Math.min(200, Math.max(1, parseInt(limit) || 50));
    const offset   = (pageNum - 1) * limitNum;
    const { conditions, params, nextIdx } = buildAuditConditions(from, to, action, username);
    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const countRes = await db.query(
      `SELECT COUNT(*) AS total FROM audit_logs al LEFT JOIN users u ON u.id = al.actor_id ${where}`,
      params
    );
    const total = parseInt(countRes.rows[0].total);
    let idx = nextIdx;
    const dataRes = await db.query(
      `SELECT al.id, al.action, al.entity_name, al.entity_id, al.description,
              al.ip_address, al.created_at, u.username
       FROM audit_logs al LEFT JOIN users u ON u.id = al.actor_id
       ${where} ORDER BY al.created_at DESC
       LIMIT $${idx++} OFFSET $${idx}`,
      [...params, limitNum, offset]
    );
    res.json({
      success: true,
      data: { logs: dataRes.rows, pagination: { page: pageNum, limit: limitNum, total, pages: Math.ceil(total / limitNum) } }
    });
  } catch (error) { next(error); }
});

// GET /audit-logs/export — download all matching logs as CSV
router.get('/export', protect, authorize('Admin'), async (req: CustomRequest, res: Response, next: NextFunction) => {
  try {
    const { from, to, action, username } = req.query as Record<string, string>;
    const { conditions, params } = buildAuditConditions(from, to, action, username);
    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const dataRes = await db.query(
      `SELECT al.id, al.action, al.entity_name, al.entity_id, al.description,
              al.ip_address, al.created_at, u.username
       FROM audit_logs al LEFT JOIN users u ON u.id = al.actor_id
       ${where} ORDER BY al.created_at DESC LIMIT 10000`,
      params
    );

    const escape = (v: any) => {
      if (v == null) return '';
      const s = String(v).replace(/"/g, '""');
      return s.includes(',') || s.includes('"') || s.includes('\n') ? `"${s}"` : s;
    };

    const header = ['ID', 'Action', 'Entity', 'Entity ID', 'Description', 'IP Address', 'Timestamp', 'Username'].join(',');
    const rows = dataRes.rows.map((r: any) =>
      [r.id, r.action, r.entity_name, r.entity_id, r.description, r.ip_address, r.created_at, r.username]
        .map(escape).join(',')
    );
    const csv = [header, ...rows].join('\r\n');

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="audit_logs_${new Date().toISOString().slice(0,10)}.csv"`);
    res.send('﻿' + csv); // BOM for Excel UTF-8 compatibility
  } catch (error) { next(error); }
});

export default router;
