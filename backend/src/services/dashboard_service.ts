import { DashboardRepository } from '../repositories/dashboard_repository';
import { logger } from '../config/logger';

export class DashboardService {
  private repo = new DashboardRepository();

  private todayString(): string {
    return new Date().toISOString().split('T')[0];
  }

  async getSummary(date?: string) {
    const d = date || this.todayString();
    try {
      const [
        presentCount,
        checkedOutCount,
        activeBreaks,
        lateCount,
        missingCheckouts,
        pendingOT,
        pendingAdj,
        totalActive,
      ] = await Promise.all([
        this.repo.getPresentCount(d),
        this.repo.getCheckedOutCount(d),
        this.repo.getActiveBreaksCount(d),
        this.repo.getLateCount(d),
        this.repo.getMissingCheckoutsCount(d),
        this.repo.getPendingOvertimeCount(),
        this.repo.getPendingAdjustmentsCount(),
        this.repo.getTotalActiveEmployees(),
      ]);

      return {
        date: d,
        presentCount: Number(presentCount),
        checkedOutCount: Number(checkedOutCount),
        activeBreaks: Number(activeBreaks),
        lateCount: Number(lateCount),
        missingCheckouts: Number(missingCheckouts),
        pendingOvertimeRequests: Number(pendingOT),
        pendingAdjustmentRequests: Number(pendingAdj),
        totalPendingApprovals: Number(pendingOT) + Number(pendingAdj),
        totalActiveEmployees: Number(totalActive),
        absentCount: Number(totalActive) - Number(presentCount) - Number(checkedOutCount),
      };
    } catch (err: any) {
      logger.error(`[DashboardService] getSummary error: ${err.message}`);
      throw err;
    }
  }

  async getPresentList(filters: any) {
    const d = filters.date || this.todayString();
    return this.repo.getPresentEmployees(d, filters);
  }

  async getLateList(filters: any) {
    const d = filters.date || this.todayString();
    return this.repo.getLateEmployees(d, filters);
  }

  async getPendingApprovals(filters: any) {
    return this.repo.getPendingApprovals(filters);
  }

  async getAttendanceMonitor(filters: any) {
    const d = filters.date || this.todayString();
    return this.repo.getAttendanceMonitor(d, filters);
  }

  async getShiftMonitor(date?: string) {
    const d = date || this.todayString();
    return this.repo.getShiftMonitor(d);
  }

  async getEmployeeDirectory(filters: any) {
    return this.repo.getEmployeeDirectory(filters);
  }
}
