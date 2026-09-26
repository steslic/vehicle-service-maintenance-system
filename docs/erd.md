# Vehicle Service Project ERD

## Purpose

This ER diagram represents the database design for the Vehicle Service and Maintenance Management System.

## Assumptions

- Assumption: Each scheduled service appointment has one primary technician assigned.
- Assumption: A customer may own multiple vehicles.
- Assumption: A vehicle may have multiple service appointments over time.
- Assumption: Each repair estimate and invoice applies to one service appointment.
- Assumption: Vehicle maintenance history is based on completed repair records.
- Assumption: Status values for service appointments, repair estimates, repairs, and invoices are maintained through controlled allowed values.
- Assumption: Each service appointment may have at most one repair estimate and at most one invoice.
- Assumption: A customer and a technician may each have at most one user account.
