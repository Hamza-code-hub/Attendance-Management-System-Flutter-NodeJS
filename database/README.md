# PostgreSQL Database Migrations & Seeds

This directory contains the initial database migrations and starter seed data for the Attendance Management System.

## Contents
* `migrations/`: Contains the SQL schema definitions.
  * `001_initial_schema.sql`: Contains base tables (`roles`, `shifts`, `employees`, `attendance_records`, `breaks`, `overtime_requests`, `adjustment_requests`, `audit_logs`).
* `seeds/`: Contains initial default records.
  * `001_seed_data.sql`: Seed data for standard office roles, shifts, and starter admin/hr/employee accounts.

## Local deployment
1. Deploy a PostgreSQL container:
   ```bash
   docker-compose -f ../config/docker-compose.yml up -d
   ```
2. Run SQL script schemas (e.g. using `psql` or PGAdmin):
   ```bash
   psql -h localhost -U attendance_admin -d attendance_management -f migrations/001_initial_schema.sql
   psql -h localhost -U attendance_admin -d attendance_management -f seeds/001_seed_data.sql
   ```
