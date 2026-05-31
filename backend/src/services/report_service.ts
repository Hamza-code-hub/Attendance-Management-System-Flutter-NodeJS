import ExcelJS from 'exceljs';
import { ReportRepository } from '../repositories/report_repository';
import { logger } from '../config/logger';
import { AppError } from '../middleware/error_handler';

const MIN_DATE = '2020-01-01';
const MAX_EXPORT_ROWS = 5000;

type ReportType = 'attendance' | 'overtime' | 'adjustment' | 'late' | 'break';
type ExportFormat = 'excel' | 'csv';

export class ReportService {
  private repo = new ReportRepository();

  validateFilters(dateFrom: string, dateTo: string) {
    if (!dateFrom || !dateTo) throw new AppError('dateFrom and dateTo are required', 400);
    const from = new Date(dateFrom);
    const to = new Date(dateTo);
    if (isNaN(from.getTime()) || isNaN(to.getTime())) throw new AppError('Invalid date format', 400);
    if (from > to) throw new AppError('dateFrom must be before dateTo', 400);
    const diffDays = (to.getTime() - from.getTime()) / (1000 * 60 * 60 * 24);
    if (diffDays > 366) throw new AppError('Date range cannot exceed 12 months', 400);
  }

  async getReportData(type: ReportType, filters: any) {
    this.validateFilters(filters.dateFrom, filters.dateTo);
    switch (type) {
      case 'attendance': return this.repo.getAttendanceReport(filters);
      case 'overtime':   return this.repo.getOvertimeReport(filters);
      case 'adjustment': return this.repo.getAdjustmentReport(filters);
      case 'late':       return this.repo.getAttendanceReport({ ...filters, status: 'LATE' });
      case 'break':      return this.repo.getBreakReport(filters);
      default: throw new AppError(`Unknown report type: ${type}`, 400);
    }
  }

  async generateExport(type: ReportType, format: ExportFormat, filters: any): Promise<{
    buffer: Buffer;
    filename: string;
    contentType: string;
  }> {
    this.validateFilters(filters.dateFrom, filters.dateTo);
    logger.info(`[ReportService] Generating ${format} export for type=${type}`);

    if (type === 'attendance' && format === 'excel') {
      const exportMonth = String(filters.dateTo).slice(0, 7);
      return this.generateMonthlyMatrix(exportMonth, filters.departmentId);
    }

    let data: any[];
    switch (type) {
      case 'attendance': data = await this.repo.getAllAttendanceForExport(filters); break;
      case 'overtime':   data = await this.repo.getAllOvertimeForExport(filters); break;
      case 'adjustment': data = await this.repo.getAllAdjustmentsForExport(filters); break;
      case 'late':       data = await this.repo.getAllAttendanceForExport({ ...filters, status: 'LATE' }); break;
      case 'break':      data = await this.repo.getAllBreaksForExport(filters); break;
      default: throw new AppError(`Unknown report type: ${type}`, 400);
    }

    if (data.length > MAX_EXPORT_ROWS) {
      throw new AppError(`Export too large: ${data.length} rows. Narrow the date range.`, 400);
    }

    const timestamp = new Date().toISOString().split('T')[0];
    const filename = `${type}_report_${filters.dateFrom}_${filters.dateTo}`;

    if (format === 'csv') {
      const csv = this.toCsv(data, type);
      return {
        buffer: Buffer.from(csv, 'utf-8'),
        filename: `${filename}.csv`,
        contentType: 'text/csv',
      };
    }

    const buffer = await this.toExcel(data, type, filters);
    return {
      buffer,
      filename: `${filename}.xlsx`,
      contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };
  }

  private getColumns(type: ReportType): { header: string; key: string; width: number }[] {
    const base = [
      { header: 'Employee Code', key: 'employee_code', width: 16 },
      { header: 'Employee Name', key: 'employee_name', width: 24 },
      { header: 'Designation', key: 'designation', width: 20 },
      { header: 'Department', key: 'department_name', width: 20 },
    ];
    switch (type) {
      case 'attendance':
      case 'late':
        return [...base,
          { header: 'Date', key: 'date', width: 12 },
          { header: 'Check In', key: 'check_in_time', width: 20 },
          { header: 'Check Out', key: 'check_out_time', width: 20 },
          { header: 'Status', key: 'status', width: 16 },
          { header: 'Worked (mins)', key: 'total_worked_minutes', width: 14 },
          { header: 'Break (mins)', key: 'total_break_minutes', width: 14 },
          { header: 'Overtime (mins)', key: 'overtime_minutes', width: 14 },
          { header: 'Shift', key: 'shift_name', width: 20 },
        ];
      case 'overtime':
        return [...base,
          { header: 'Request Date', key: 'request_date', width: 14 },
          { header: 'Requested (mins)', key: 'requested_minutes', width: 16 },
          { header: 'Approved (mins)', key: 'approved_minutes', width: 16 },
          { header: 'Status', key: 'status', width: 14 },
          { header: 'Reason', key: 'reason', width: 30 },
          { header: 'HR Comment', key: 'hr_comment', width: 30 },
          { header: 'Reviewed At', key: 'reviewed_at', width: 20 },
        ];
      case 'adjustment':
        return [...base,
          { header: 'Type', key: 'adjustment_type', width: 20 },
          { header: 'Requested Check-in', key: 'requested_checkin_time', width: 22 },
          { header: 'Requested Check-out', key: 'requested_checkout_time', width: 22 },
          { header: 'Requested (mins)', key: 'requested_minutes', width: 16 },
          { header: 'Status', key: 'status', width: 14 },
          { header: 'Reason', key: 'reason', width: 30 },
          { header: 'HR Comment', key: 'hr_comment', width: 30 },
          { header: 'Submitted', key: 'created_at', width: 20 },
        ];
      case 'break':
        return [...base,
          { header: 'Date', key: 'date', width: 12 },
          { header: 'Break Start', key: 'break_start', width: 20 },
          { header: 'Break End', key: 'break_end', width: 20 },
          { header: 'Duration (mins)', key: 'duration_minutes', width: 16 },
          { header: 'Shift', key: 'shift_name', width: 20 },
        ];
      default: return base;
    }
  }

  private toCsv(data: any[], type: ReportType): string {
    const cols = this.getColumns(type);
    const header = cols.map(c => `"${c.header}"`).join(',');
    const rows = data.map(row =>
      cols.map(c => {
        const val = row[c.key] ?? '';
        return `"${String(val).replace(/"/g, '""')}"`;
      }).join(',')
    );
    return [header, ...rows].join('\r\n');
  }

  private async toExcel(data: any[], type: ReportType, filters: any): Promise<Buffer> {
    const workbook = new ExcelJS.Workbook();
    workbook.creator = 'Attendance Management System';
    workbook.created = new Date();

    const sheet = workbook.addWorksheet(`${type.charAt(0).toUpperCase() + type.slice(1)} Report`, {
      pageSetup: { paperSize: 9, orientation: 'landscape' },
    });

    // Title row
    sheet.mergeCells('A1', `${String.fromCharCode(64 + (this.getColumns(type).length))}1`);
    const titleCell = sheet.getCell('A1');
    titleCell.value = `${type.toUpperCase()} REPORT — ${filters.dateFrom} to ${filters.dateTo}`;
    titleCell.font = { bold: true, size: 14, color: { argb: 'FFFFFFFF' } };
    titleCell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1E3A8A' } };
    titleCell.alignment = { horizontal: 'center', vertical: 'middle' };
    sheet.getRow(1).height = 32;

    // Columns
    const cols = this.getColumns(type);
    sheet.columns = cols.map(c => ({ key: c.key, width: c.width }));

    // Header row
    const headerRow = sheet.addRow(cols.map(c => c.header));
    headerRow.height = 22;
    headerRow.eachCell((cell) => {
      cell.font = { bold: true, color: { argb: 'FFFFFFFF' }, size: 11 };
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1E40AF' } };
      cell.alignment = { horizontal: 'center', vertical: 'middle' };
      cell.border = {
        bottom: { style: 'thin', color: { argb: 'FF93C5FD' } },
      };
    });

    // Data rows
    data.forEach((row, idx) => {
      const dataRow = sheet.addRow(cols.map(c => row[c.key] ?? ''));
      dataRow.height = 18;
      const isEven = idx % 2 === 0;
      dataRow.eachCell((cell) => {
        cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: isEven ? 'FFF8FAFC' : 'FFFFFFFF' } };
        cell.alignment = { vertical: 'middle' };
        cell.border = { bottom: { style: 'hair', color: { argb: 'FFE2E8F0' } } };
        // Status color coding
        if (cell.value === 'LATE') cell.font = { color: { argb: 'FFD97706' } };
        if (cell.value === 'MISSED_CHECKOUT') cell.font = { color: { argb: 'FFDC2626' } };
        if (cell.value === 'ON_TIME' || cell.value === 'APPROVED') cell.font = { color: { argb: 'FF059669' } };
        if (cell.value === 'REJECTED') cell.font = { color: { argb: 'FFDC2626' } };
        if (cell.value === 'PENDING') cell.font = { color: { argb: 'FF7C3AED' } };
      });

      // Highlight overtime rows — graduated by severity
      const otMins = Number(row['overtime_minutes'] ?? 0);
      if (otMins > 0) {
        // 1–60 min (6 PM–7 PM): amber — moderate overtime
        // >60 min (past 7 PM): red/orange — extended overtime
        const isExtended = otMins > 60;
        const rowBg    = isExtended ? 'FFFFF0E6' : 'FFFEF3C7'; // orange-tint vs amber-tint
        const fontColor = isExtended ? 'FFEA580C' : 'FFD97706'; // deep orange vs amber
        const cols2 = this.getColumns(type);
        const checkOutIdx = cols2.findIndex(c => c.key === 'check_out_time');
        const otIdx       = cols2.findIndex(c => c.key === 'overtime_minutes');
        // Tint the entire row lightly
        dataRow.eachCell(cell => {
          cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: rowBg } };
        });
        // Bold + colored on checkout cell
        if (checkOutIdx >= 0) {
          const cell = dataRow.getCell(checkOutIdx + 1);
          cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: rowBg } };
          cell.font = { color: { argb: fontColor }, bold: true };
        }
        // Bold + colored on overtime_minutes cell with note
        if (otIdx >= 0) {
          const cell = dataRow.getCell(otIdx + 1);
          cell.value = `${otMins}m ${isExtended ? '🔴' : '🟡'}`;
          cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: rowBg } };
          cell.font = { color: { argb: fontColor }, bold: true };
        }
      }
    });

    // Auto-filter
    if (data.length > 0) {
      sheet.autoFilter = { from: { row: 2, column: 1 }, to: { row: 2, column: cols.length } };
    }

    // Summary footer
    sheet.addRow([]);
    const summaryRow = sheet.addRow([`Total Records: ${data.length}`, '', `Generated: ${new Date().toISOString()}`]);
    summaryRow.getCell(1).font = { italic: true, color: { argb: 'FF64748B' } };

    const buffer = await workbook.xlsx.writeBuffer();
    return Buffer.from(buffer);
  }

  // ── Monthly Attendance Matrix ─────────────────────────────────────────────
  // Row = employee  |  Column pair = one day (Check In + Check Out)
  // Merged date headers, colored rows by status, summary column at end

  async generateMonthlyMatrix(month: string, departmentId?: number, orgName?: string): Promise<{
    buffer: Buffer;
    filename: string;
    contentType: string;
  }> {
    const { employees, attendanceMap, dates, deptName } =
      await this.repo.getMonthlyMatrixData(month, departmentId);

    if (employees.length === 0) {
      throw new AppError('No employees found for the selected department', 404);
    }

    const [yr, mn] = month.split('-').map(Number);
    const monthLabel = new Date(yr, mn - 1, 1)
      .toLocaleString('en-US', { month: 'long', year: 'numeric' });

    const wb = new ExcelJS.Workbook();
    wb.creator = 'AttendX AMS';
    wb.created = new Date();

    const ws = wb.addWorksheet('Attendance', {
      pageSetup: { paperSize: 9, orientation: 'landscape', fitToPage: true, fitToWidth: 1 },
      views: [{ state: 'frozen', xSplit: 2, ySplit: 5 }], // freeze first 2 cols + first 5 rows
    });

    const daysCount = dates.length;
    // Column layout: 1=Employee, 2=Dept, then 2 cols per day, then 4 summary cols
    const summaryStartCol = 3 + daysCount * 2; // 1-indexed
    const totalCols = summaryStartCol + 3;      // Present, Absent, Late, Hours

    // ── Column widths ──────────────────────────────────────────────────────
    ws.getColumn(1).width = 24;   // Employee name
    ws.getColumn(2).width = 15;   // Department
    for (let i = 3; i < summaryStartCol; i += 2) {
      ws.getColumn(i).width = 7.5;   // In
      ws.getColumn(i + 1).width = 7.5; // Out
    }
    ws.getColumn(summaryStartCol).width = 9;     // Present
    ws.getColumn(summaryStartCol + 1).width = 9; // Absent
    ws.getColumn(summaryStartCol + 2).width = 9; // Late
    ws.getColumn(summaryStartCol + 3).width = 11; // Hours

    // ── Colour palette (CyberZeus deep navy) ──────────────────────────────
    const C = {
      navy:     '0A1628', navy2:    '0F1E38', navy3:    '152844',
      card:     '111D33', card2:    '142036', cardAlt:  '1A2B47',
      blue:     '1A6ED8', blue3:    '3D94F7', cyan:     '00C2FF',
      green:    '00D68F', amber:    'FFB020', red:      'FF4D6A',
      purple:   '7C5CFC', gold:     'F5A623',
      white:    'EEF2FF', muted:    '8BA3C7', dim:      '4A6080',
      weekend:  '0D1530',
    };
    const px = (hex: string) => ({ argb: `FF${hex}` });
    const fill = (hex: string) => ({ type: 'pattern' as const, pattern: 'solid' as const, fgColor: px(hex) });
    const font = (hex: string, opts: any = {}) => ({ color: px(hex), ...opts });

    const setCell = (r: number, c: number, cb: (cell: ExcelJS.Cell) => void) => cb(ws.getCell(r, c));

    // ── Row 1: Report title (merged across all columns) ────────────────────
    ws.mergeCells(1, 1, 1, totalCols);
    setCell(1, 1, cell => {
      cell.value = `MONTHLY ATTENDANCE REPORT — ${monthLabel.toUpperCase()}`;
      cell.font  = font(C.blue3, { bold: true, size: 14 });
      cell.fill  = fill(C.navy);
      cell.alignment = { horizontal: 'center', vertical: 'middle' };
    });
    ws.getRow(1).height = 34;

    // ── Row 2: Subtitle ───────────────────────────────────────────────────
    ws.mergeCells(2, 1, 2, totalCols);
    setCell(2, 1, cell => {
      cell.value = `${orgName || 'Company'}  ·  ${monthLabel}  ·  Department: ${deptName}  ·  ${employees.length} Employees  ·  ${dates.length} Days`;
      cell.font  = font(C.muted, { size: 10 });
      cell.fill  = fill(C.navy);
      cell.alignment = { horizontal: 'center', vertical: 'middle' };
    });
    ws.getRow(2).height = 20;

    // ── Row 3: Thin spacer ────────────────────────────────────────────────
    ws.getRow(3).height = 6;
    for (let c = 1; c <= totalCols; c++) ws.getCell(3, c).fill = fill(C.navy);

    // ── Row 4: Date headers + Employee/Dept fixed cols + SUMMARY ──────────
    ws.getRow(4).height = 30;

    // Employee — merge rows 4 and 5
    ws.mergeCells(4, 1, 5, 1);
    setCell(4, 1, cell => {
      cell.value = 'EMPLOYEE';
      cell.font  = font(C.blue3, { bold: true, size: 10 });
      cell.fill  = fill(C.navy2);
      cell.alignment = { horizontal: 'center', vertical: 'middle' };
      cell.border = { right: { style: 'thin', color: px(C.navy3) } };
    });

    // Dept — merge rows 4 and 5
    ws.mergeCells(4, 2, 5, 2);
    setCell(4, 2, cell => {
      cell.value = 'DEPT';
      cell.font  = font(C.blue3, { bold: true, size: 10 });
      cell.fill  = fill(C.navy2);
      cell.alignment = { horizontal: 'center', vertical: 'middle' };
      cell.border = { right: { style: 'medium', color: px(C.blue) } };
    });

    // One merged date cell per day (spans In + Out columns)
    dates.forEach((dateStr, i) => {
      const col = 3 + i * 2;
      const d = new Date(dateStr + 'T00:00:00');
      const isWeekend = d.getDay() === 0 || d.getDay() === 6;
      const dayNum  = String(d.getDate()).padStart(2, '0');
      const monthAb = d.toLocaleString('en-US', { month: 'short' });
      const weekDay = d.toLocaleString('en-US', { weekday: 'short' });

      ws.mergeCells(4, col, 4, col + 1);
      setCell(4, col, cell => {
        cell.value     = `${dayNum} ${monthAb}\n${weekDay}`;
        cell.font      = font(isWeekend ? C.dim : C.white, { bold: !isWeekend, size: 8 });
        cell.fill      = fill(isWeekend ? C.weekend : C.card2);
        cell.alignment = { horizontal: 'center', vertical: 'middle', wrapText: true };
        cell.border    = { left: { style: 'hair', color: px(C.navy3) } };
      });
    });

    // SUMMARY header — merge rows 4 across 4 cols
    ws.mergeCells(4, summaryStartCol, 4, totalCols);
    setCell(4, summaryStartCol, cell => {
      cell.value = 'MONTHLY SUMMARY';
      cell.font  = font(C.blue3, { bold: true, size: 10 });
      cell.fill  = fill(C.navy2);
      cell.alignment = { horizontal: 'center', vertical: 'middle' };
      cell.border = { left: { style: 'medium', color: px(C.blue) } };
    });

    // ── Row 5: Sub-headers: IN / OUT per day, then summary labels ─────────
    ws.getRow(5).height = 18;

    dates.forEach((dateStr, i) => {
      const col = 3 + i * 2;
      const d = new Date(dateStr + 'T00:00:00');
      const isWeekend = d.getDay() === 0 || d.getDay() === 6;
      const bg = isWeekend ? C.weekend : C.card;

      setCell(5, col, cell => {
        cell.value = 'Check in';
        cell.font  = font(C.green, { bold: true, size: 8 });
        cell.fill  = fill(bg);
        cell.alignment = { horizontal: 'center', vertical: 'middle' };
      });
      setCell(5, col + 1, cell => {
        cell.value = 'Check out';
        cell.font  = font(C.red, { bold: true, size: 8 });
        cell.fill  = fill(bg);
        cell.alignment = { horizontal: 'center', vertical: 'middle' };
        cell.border = { right: { style: 'hair', color: px(C.navy3) } };
      });
    });

    const summLabels = ['PRESENT', 'ABSENT', 'LATE', 'HOURS'];
    const summColors = [C.green, C.red, C.amber, C.blue3];
    summLabels.forEach((lbl, i) => {
      setCell(5, summaryStartCol + i, cell => {
        cell.value = lbl;
        cell.font  = font(summColors[i], { bold: true, size: 8 });
        cell.fill  = fill(C.navy2);
        cell.alignment = { horizontal: 'center', vertical: 'middle' };
      });
    });

    // ── Data rows ─────────────────────────────────────────────────────────
    const perDayPresent = new Array(daysCount).fill(0);
    let grandPresent = 0, grandAbsent = 0, grandLate = 0, grandMinutes = 0;

    // Work days count (exclude weekends)
    const workDays = dates.filter(d => {
      const wd = new Date(d + 'T00:00:00').getDay();
      return wd !== 0 && wd !== 6;
    }).length;

    employees.forEach((emp, empIdx) => {
      const rowNum = 6 + empIdx;
      ws.getRow(rowNum).height = 20;
      const empAtt = attendanceMap.get(emp.id) || new Map();
      const rowBg = empIdx % 2 === 0 ? C.card : C.card2;

      // Employee name cell
      setCell(rowNum, 1, cell => {
        cell.value = emp.full_name;
        cell.font  = font(C.white, { size: 10, bold: true });
        cell.fill  = fill(rowBg);
        cell.alignment = { vertical: 'middle', indent: 1 };
        cell.border = { right: { style: 'thin', color: px(C.navy3) } };
      });

      // Dept cell
      setCell(rowNum, 2, cell => {
        cell.value = emp.department_name || '—';
        cell.font  = font(C.muted, { size: 9 });
        cell.fill  = fill(rowBg);
        cell.alignment = { horizontal: 'center', vertical: 'middle' };
        cell.border = { right: { style: 'medium', color: px(C.blue) } };
      });

      // Per-day cells
      let empPresent = 0, empLate = 0, empMinutes = 0;

      dates.forEach((dateStr, dayIdx) => {
        const col = 3 + dayIdx * 2;
        const d = new Date(dateStr + 'T00:00:00');
        const isWeekend = d.getDay() === 0 || d.getDay() === 6;
        const rec = empAtt.get(dateStr);

        let inVal = '—', outVal = '—';
        let inColor = C.dim, outColor = C.dim;
        let cellBg = isWeekend ? C.weekend : rowBg;

        if (rec) {
          const s = rec.status as string;
          // Background tint by status
          if (!isWeekend) {
            if (['ON_TIME', 'PRESENT', 'CHECKED_IN', 'CHECKED_OUT', 'BREAK_ACTIVE'].includes(s)) cellBg = empIdx % 2 === 0 ? '001B0D' : '002B15';
            else if (s === 'LATE') { cellBg = empIdx % 2 === 0 ? '1A1000' : '221400'; inColor = C.amber; }
            else if (s === 'MISSED_CHECKOUT') cellBg = empIdx % 2 === 0 ? '1A0008' : '22000A';
          }

          const fmtTime = (ts: string | null) => {
            if (!ts) return '—';
            try {
              const dt = new Date(ts);
              const h = dt.getHours();
              const m = String(dt.getMinutes()).padStart(2, '0');
              const period = h >= 12 ? 'PM' : 'AM';
              const h12 = h % 12 || 12;
              return `${String(h12).padStart(2, '0')}:${m} ${period}`;
            } catch { return '—'; }
          };

          inVal  = fmtTime(rec.check_in_time);
          outVal = fmtTime(rec.check_out_time);
          inColor  = rec.status === 'LATE' ? C.amber : C.green;
          outColor = rec.check_out_time ? C.muted : C.dim;

          if (!isWeekend) {
            if (s !== 'ABSENT') { empPresent++; perDayPresent[dayIdx]++; }
            if (s === 'LATE') empLate++;
            empMinutes += (rec.total_worked_minutes as number) || 0;
          }
        } else if (!isWeekend) {
          // No record on a work day = absent
          inVal = 'ABS'; inColor = C.red;
          outVal = ''; outColor = C.dim;
          cellBg = empIdx % 2 === 0 ? '1A0005' : '220008';
        } else {
          inVal = ''; outVal = '';
        }

        setCell(rowNum, col, cell => {
          cell.value = inVal;
          cell.font  = font(inColor, { size: 9 });
          cell.fill  = fill(cellBg);
          cell.alignment = { horizontal: 'center', vertical: 'middle' };
        });
        setCell(rowNum, col + 1, cell => {
          cell.value = outVal;
          cell.font  = font(outColor, { size: 9 });
          cell.fill  = fill(cellBg);
          cell.alignment = { horizontal: 'center', vertical: 'middle' };
          cell.border = { right: { style: 'hair', color: px(C.navy3) } };
        });
      });

      const empAbsent = workDays - empPresent;
      const empHours  = Math.floor(empMinutes / 60);
      const empMins   = empMinutes % 60;

      // Summary cells
      [
        [summaryStartCol,     empPresent, C.green, true],
        [summaryStartCol + 1, empAbsent,  empAbsent > 0 ? C.red : C.dim, true],
        [summaryStartCol + 2, empLate,    empLate > 0 ? C.amber : C.dim, true],
        [summaryStartCol + 3, `${empHours}h ${empMins}m`, C.blue3, false],
      ].forEach(([col, val, color, bold]) => {
        setCell(rowNum, col as number, cell => {
          cell.value = val as any;
          cell.font  = font(color as string, { bold, size: 10 });
          cell.fill  = fill(C.navy2);
          cell.alignment = { horizontal: 'center', vertical: 'middle' };
        });
      });

      grandPresent += empPresent;
      grandAbsent  += empAbsent;
      grandLate    += empLate;
      grandMinutes += empMinutes;
    });

    // ── Totals row ─────────────────────────────────────────────────────────
    const totRow = 6 + employees.length;
    ws.getRow(totRow).height = 24;

    ws.mergeCells(totRow, 1, totRow, 2);
    setCell(totRow, 1, cell => {
      cell.value = `DAILY TOTALS  (${employees.length} employees)`;
      cell.font  = font(C.white, { bold: true, size: 10 });
      cell.fill  = fill(C.navy);
      cell.alignment = { horizontal: 'center', vertical: 'middle' };
    });

    dates.forEach((dateStr, i) => {
      const col = 3 + i * 2;
      const d = new Date(dateStr + 'T00:00:00');
      const isWeekend = d.getDay() === 0 || d.getDay() === 6;
      ws.mergeCells(totRow, col, totRow, col + 1);
      setCell(totRow, col, cell => {
        cell.value = isWeekend ? '' : perDayPresent[i];
        cell.font  = font(isWeekend ? C.dim : C.green, { bold: true, size: 10 });
        cell.fill  = fill(C.navy);
        cell.alignment = { horizontal: 'center', vertical: 'middle' };
      });
    });

    const grandHrs = Math.floor(grandMinutes / 60);
    [
      [summaryStartCol,     grandPresent, C.green],
      [summaryStartCol + 1, grandAbsent,  grandAbsent > 0 ? C.red : C.dim],
      [summaryStartCol + 2, grandLate,    grandLate > 0 ? C.amber : C.dim],
      [summaryStartCol + 3, `${grandHrs}h`, C.blue3],
    ].forEach(([col, val, color]) => {
      setCell(totRow, col as number, cell => {
        cell.value = val as any;
        cell.font  = font(color as string, { bold: true, size: 11 });
        cell.fill  = fill(C.navy);
        cell.alignment = { horizontal: 'center', vertical: 'middle' };
      });
    });

    const buffer = await wb.xlsx.writeBuffer();
    logger.info(`[MonthlyMatrix] Generated ${month} — ${employees.length} employees × ${dates.length} days`);
    return {
      buffer: Buffer.from(buffer),
      filename: `attendance_matrix_${month}${departmentId ? `_dept${departmentId}` : ''}.xlsx`,
      contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };
  }
}
