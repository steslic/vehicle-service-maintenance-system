"""Stable wire identifiers for database errors; never allocate codes by message order.

Messages below describe version-5 SIGNAL sites for the offline migration recipe.
Runtime classification uses numeric codes and SQLSTATE, never message matching.
This is a versioned protocol, not administrator-editable business reference data.
"""

ERRORS = {
    'VSM_INVALID_APPOINTMENT': (51001, 'validation'),
    'VSM_INVALID_INDICATOR': (51002, 'validation'),
    'VSM_UNKNOWN_INDICATOR': (51003, 'validation'),
    'VSM_REQUIRED_FIELD': (51004, 'validation'),
    'VSM_INVALID_PROFILE': (51005, 'validation'),
    'VSM_INVALID_PARTS_DOCUMENT': (51006, 'validation'),
    'VSM_INVALID_PART_ITEM': (51007, 'validation'),
    'VSM_PREMATURE_PROVENANCE': (51008, 'validation'),
    'VSM_INVALID_AUDIT_QUERY': (51009, 'validation'),
    'VSM_INVENTORY_REASON_REQUIRED': (51010, 'validation'),
    'VSM_UNREGISTERED_SESSION': (52001, 'forbidden'),
    'VSM_ACTOR_MISMATCH': (52002, 'forbidden'),
    'VSM_LOGIN_MAPPING_MISMATCH': (52003, 'forbidden'),
    'VSM_DELEGATION_DENIED': (52004, 'forbidden'),
    'VSM_ACTOR_INACTIVE': (52005, 'forbidden'),
    'VSM_OPERATION_DENIED': (52006, 'forbidden'),
    'VSM_PROVENANCE_IMMUTABLE': (52007, 'forbidden'),
    'VSM_HISTORY_WRITE_DENIED': (52008, 'forbidden'),
    'VSM_AUDIT_IMMUTABLE': (52009, 'forbidden'),
    'VSM_COMPLETION_ENTRY_REQUIRED': (52010, 'forbidden'),
    'VSM_REPAIR_NOT_FOUND': (53001, 'not_found'),
    'VSM_VEHICLE_NOT_FOUND': (53002, 'not_found'),
    'VSM_TECHNICIAN_NOT_FOUND': (53003, 'not_found'),
    'VSM_PART_NOT_FOUND': (53004, 'not_found'),
    'VSM_CUSTOMER_NOT_FOUND': (53005, 'not_found'),
    'VSM_USER_NOT_FOUND': (53006, 'not_found'),
    'VSM_SCHEDULE_CONFLICT': (54001, 'conflict'),
    'VSM_INVALID_TRANSITION': (54002, 'conflict'),
    'VSM_FINAL_STATE_IMMUTABLE': (54003, 'conflict'),
    'VSM_INSUFFICIENT_STOCK': (54004, 'conflict'),
    'VSM_RELATED_STATE_CONFLICT': (54005, 'conflict'),
    'VSM_ROLE_POLICY_CONFLICT': (54006, 'conflict'),
    'VSM_FINANCIAL_TOTAL_CONFLICT': (54007, 'conflict'),
    'VSM_NOTICE': (55001, 'warning'),
    'VSM_HISTORY_INCONSISTENT': (59001, 'critical'),
    'VSM_PARENT_INCONSISTENT': (59002, 'critical'),
    'VSM_PRINCIPAL_INCONSISTENT': (59003, 'critical'),
}

# Explicit review of the original deployed business messages. Multiple sites
# enforcing the same invariant share one stable identifier.
MESSAGE_IDS = {}


def messages(identifier, *values):
    for value in values:
        assert value not in MESSAGE_IDS, value
        MESSAGE_IDS[value] = identifier


messages('VSM_INVALID_APPOINTMENT', 'Invalid appointment information', 'Vehicle does not belong to the customer')
messages('VSM_UNKNOWN_INDICATOR', 'Unknown indicator domain')
messages('VSM_INVALID_PROFILE', 'User role and technician profile do not match')
messages('VSM_INVALID_PARTS_DOCUMENT', 'Parts must be a JSON array')
messages('VSM_INVALID_PART_ITEM', 'Each part needs an integer partId and a positive integer qty')
messages('VSM_PREMATURE_PROVENANCE', 'Cancellation information belongs to cancellation',
         'Draft estimates cannot contain approval metadata', 'Draft invoices cannot contain finalization metadata',
         'New repairs cannot contain completion metadata')
messages('VSM_INVALID_AUDIT_QUERY', 'Invalid audit page size or date range', 'Unknown temporal audit entity')
messages('VSM_INVENTORY_REASON_REQUIRED', 'Inventory adjustments require @adj_reason')
messages('VSM_UNREGISTERED_SESSION', 'Database session is not a registered principal')
messages('VSM_ACTOR_MISMATCH', 'Acting user must be the logged-in user', 'Approver must match the responsible actor',
         'Creating user must match the responsible actor', 'Finalizer must match the responsible actor',
         'Recording user must match the responsible actor')
messages('VSM_LOGIN_MAPPING_MISMATCH', 'Login mapping does not match the person')
messages('VSM_DELEGATION_DENIED', 'Service is not authorized to act for this person and operation')
messages('VSM_ACTOR_INACTIVE', 'Responsible actor is invalid or inactive')
messages('VSM_OPERATION_DENIED', 'Responsible person is not entitled to this operation',
         'Estimates must be approved or rejected by a Manager', 'Invoices must be finalized by a Service Advisor or Manager',
         'Recording user is not authorized to complete this repair', 'Technician is not assigned to this appointment',
         'Completing technician must be assigned to the appointment', 'Technicians may only update their own assigned repairs')
messages('VSM_PROVENANCE_IMMUTABLE', 'A line item cannot be moved to another estimate',
         'A line item cannot be moved to another invoice', 'A repair cannot be moved to another appointment',
         'An appointment cannot be moved to another vehicle', 'An estimate cannot be moved to another appointment',
         'An invoice cannot be moved to another appointment', 'Approval fields can only be set by the approval itself',
         'Cancellation date can only be set by cancellation', 'Completion fields can only be set by completion',
         'Creation timestamp cannot be changed', 'Finalization fields can only be set by finalization',
         'Parts usage provenance cannot be changed', 'Re-register login mappings before renaming a user',
         'Record IDs cannot be changed', 'The creating user cannot be changed', 'User identifiers cannot be changed')
messages('VSM_HISTORY_WRITE_DENIED', 'History inserts require protected maintenance', 'History records cannot be deleted',
         'History versions are immutable outside protected closing', 'Temporal events are immutable',
         'Temporal events cannot be deleted', 'Temporal events require protected history maintenance')
messages('VSM_AUDIT_IMMUTABLE', 'Audit records cannot be deleted', 'Audit records cannot be modified')
messages('VSM_COMPLETION_ENTRY_REQUIRED', 'Repair completion requires its procedure or a Manager')
messages('VSM_REPAIR_NOT_FOUND', 'Repair does not exist')
messages('VSM_USER_NOT_FOUND', 'Creating user does not exist')
messages('VSM_SCHEDULE_CONFLICT', 'Technician already has a conflicting appointment', 'Vehicle already has a conflicting appointment')
messages('VSM_INVALID_TRANSITION', 'Invalid appointment status transition', 'Invalid estimate status transition',
         'Invalid invoice status transition', 'Invalid repair status transition', 'New appointments must start in Scheduled status',
         'New invoices must start in Draft status', 'New repair estimates must start in Draft status', 'New repairs must start in Open status')
messages('VSM_FINAL_STATE_IMMUTABLE', 'Cannot add line items to a finalized estimate', 'Cannot add line items to a finalized invoice',
         'Cannot delete line items of a finalized estimate', 'Cannot delete line items of a finalized invoice',
         'Cannot modify line items of a finalized estimate', 'Cannot modify line items of a finalized invoice',
         'Completed or cancelled repairs cannot be modified', 'Completed, cancelled, or no-show appointments cannot be modified',
         'Finalized estimates cannot be deleted', 'Finalized estimates cannot be modified',
         'Finalized invoices cannot be deleted', 'Finalized invoices cannot be modified')
messages('VSM_INSUFFICIENT_STOCK', 'Insufficient parts inventory')
messages('VSM_RELATED_STATE_CONFLICT', 'A part does not exist or is inactive', 'Technician does not exist or is inactive',
         'Appointment has open repairs: complete or cancel them first', 'Appointment must be In Progress to complete a repair',
         'Repair must be In Progress to be completed', 'Repairs cannot be added to a completed, cancelled, or no-show appointment')
messages('VSM_ROLE_POLICY_CONFLICT', 'Role policy would invalidate existing user profiles')
messages('VSM_FINANCIAL_TOTAL_CONFLICT', 'Estimate total must equal the sum of its line items', 'Invoice total must equal the sum of its line items')
messages('VSM_HISTORY_INCONSISTENT', 'Current temporal history version is missing')
messages('VSM_PARENT_INCONSISTENT', 'Appointment for this repair does not exist')
messages('VSM_PRINCIPAL_INCONSISTENT', 'Unsupported principal type')


def identifier_for_message(message):
    if message.endswith(' cannot be blank'):
        return 'VSM_REQUIRED_FIELD'
    return MESSAGE_IDS[message]
