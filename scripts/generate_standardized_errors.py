#!/usr/bin/env python3
"""Generate migration 006 from frozen, immutable deployed definitions through 005.

Offline development recipe only. Never edit an applied migration by regeneration.
"""

from collections import defaultdict
from pathlib import Path
import re

from error_contract import ERRORS, identifier_for_message

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ['sql/legacy/v001/04_procedures.sql', 'sql/legacy/v001/05_triggers_roles.sql',
           'sql/migrations/003_indicator_values.sql', 'sql/migrations/004_session_identity_and_provenance.sql',
           'sql/migrations/005_temporal_history.sql']
SIGNAL = re.compile(r"SIGNAL\s+SQLSTATE\s+'45000'\s+SET\s+MESSAGE_TEXT\s*=\s*([^;]+);")


def deployed_objects():
    objects = {}
    groups = defaultdict(list)
    pattern = (r'CREATE\s+(PROCEDURE|FUNCTION|TRIGGER)\s+`?(\w+)`?[\s\S]*?\nEND\s*//'
               r'|DROP\s+(PROCEDURE|FUNCTION|TRIGGER)\s+(?:IF\s+EXISTS\s+)?`?(\w+)`?')
    for name in SOURCES:
        for match in re.finditer(pattern, (ROOT / name).read_text()):
            kind, object_name = (match[1], match[2]) if match[1] else (match[3], match[4])
            key = (kind, object_name)
            if kind == 'TRIGGER':
                for names in groups.values():
                    if object_name in names:
                        names.remove(object_name)
            objects.pop(key, None)
            if not match[1]:
                continue
            objects[key] = match[0]
            if kind == 'TRIGGER':
                group = re.search(r'(BEFORE|AFTER)\s+(INSERT|UPDATE|DELETE)\s+ON\s+`?(\w+)`?', match[0]).groups()
                ordering = re.search(r'FOR EACH ROW\s+(PRECEDES|FOLLOWS)\s+(\w+)', match[0])
                if ordering:
                    position = groups[group].index(ordering[2]) + (ordering[1] == 'FOLLOWS')
                    groups[group].insert(position, object_name)
                else:
                    groups[group].append(object_name)
    return objects, groups


def standardize(sql):
    def replace(match):
        expression = match[1].strip()
        identifier = 'VSM_INVALID_INDICATOR' if expression == 'v_Message' else identifier_for_message(expression[1:-1].replace("''", "'"))
        return f"SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = {ERRORS[identifier][0]}, MESSAGE_TEXT = {expression};"
    return SIGNAL.sub(replace, sql)


def classifiers():
    identifiers = '\n'.join(f"        WHEN {code} THEN '{name}'" for name, (code, _) in ERRORS.items())
    categories = defaultdict(list)
    for code, category in ERRORS.values():
        categories[category].append(str(code))
    cases = '\n'.join(f"        WHEN p_Number IN ({', '.join(codes)}) THEN '{category}'" for category, codes in categories.items())
    return f"""
ALTER TABLE AuditLog
    ADD COLUMN ApplicationErrorID VARCHAR(64) NULL,
    ADD COLUMN ErrorClass VARCHAR(16) NULL,
    ADD COLUMN ErrorSQLSTATE CHAR(5) NULL,
    ADD COLUMN ErrorNumber INT NULL,
    ADD COLUMN ErrorMessage TEXT NULL,
    ADD COLUMN TransactionOutcome VARCHAR(16) NULL;

DELIMITER //
CREATE FUNCTION fn_ApplicationErrorID(p_Number INT)
RETURNS VARCHAR(64) DETERMINISTIC NO SQL
BEGIN
    RETURN CASE p_Number
{identifiers}
        ELSE NULL END;
END //

CREATE FUNCTION fn_ErrorClass(p_Number INT, p_State CHAR(5), p_IsWarning BOOLEAN)
RETURNS VARCHAR(16) DETERMINISTIC NO SQL
BEGIN
    RETURN CASE
        WHEN p_Number IS NULL AND p_State IS NULL THEN NULL
        WHEN p_Number = 0 AND p_State = '00000' AND NOT COALESCE(p_IsWarning, FALSE) THEN NULL
        WHEN p_IsWarning = TRUE OR LEFT(p_State, 2) = '01' THEN 'warning'
{cases}
        WHEN p_Number IN (1205, 1213) THEN 'retryable'
        WHEN p_Number IN (1044, 1045, 1142, 1143, 1227, 1370, 1698, 3118) THEN 'forbidden'
        WHEN p_Number IN (1062, 1169, 1451) THEN 'conflict'
        WHEN p_Number IN (1048, 1264, 1265, 1292, 1364, 1452, 3140, 3141, 3143, 3146, 3819)
          OR LEFT(p_State, 2) IN ('22', '23') THEN 'validation'
        ELSE 'critical' END;
END //

-- A decision contract, not an automatic retry loop. The caller must establish
-- the outcome; classification alone never proves a transaction rolled back.
CREATE FUNCTION fn_ErrorCallerAction(p_Number INT, p_State CHAR(5), p_IsWarning BOOLEAN,
    p_Outcome VARCHAR(16), p_Attempt INT)
RETURNS VARCHAR(32) DETERMINISTIC NO SQL
BEGIN
    DECLARE v_Class VARCHAR(16);
    SET v_Class = fn_ErrorClass(p_Number, p_State, p_IsWarning);
    IF p_Outcome IS NULL OR p_Outcome NOT IN ('rolled_back', 'not_started', 'completed', 'committed') OR LEFT(p_State, 2) = '08'
       OR p_Number IN (2006, 2013, 2055) THEN RETURN 'reconcile_outcome'; END IF;
    IF v_Class = 'warning' AND p_Outcome IN ('completed', 'committed') THEN RETURN 'accept_with_warning'; END IF;
    IF p_Outcome IN ('completed', 'committed') THEN RETURN 'review_completed_result'; END IF;
    IF v_Class = 'retryable' THEN
        IF p_Outcome <> 'rolled_back' THEN RETURN 'confirm_full_rollback'; END IF;
        IF p_Attempt IS NULL OR p_Attempt < 1 THEN RETURN 'review_retry_state'; END IF;
        IF p_Attempt >= 3 THEN RETURN 'stop_retry_budget'; END IF;
        RETURN 'retry_transaction';
    END IF;
    RETURN CASE v_Class WHEN 'validation' THEN 'correct_input' WHEN 'forbidden' THEN 'stop_and_authorize'
        WHEN 'not_found' THEN 'refresh_record' WHEN 'conflict' THEN 'refresh_state' ELSE 'stop_and_report' END;
END //
DELIMITER ;
"""


def public_procedure(sql, name):
    sql = sql.replace('    DECLARE v_CallContext CHAR(36);', '''    DECLARE v_CallContext CHAR(36);
    DECLARE v_ErrorState CHAR(5);
    DECLARE v_ErrorNumber INT;
    DECLARE v_ConditionCount INT;
    DECLARE v_ConditionIndex INT;
    DECLARE v_ConditionState CHAR(5);
    DECLARE v_ConditionNumber INT;
    DECLARE v_ConditionMessage TEXT;
    DECLARE v_CommitAttempted BOOLEAN DEFAULT FALSE;
    DECLARE v_RollbackSucceeded BOOLEAN DEFAULT TRUE;
    DECLARE v_Outcome VARCHAR(16) DEFAULT 'unknown';''')
    begin = sql.index('    DECLARE EXIT HANDLER FOR SQLEXCEPTION')
    end = sql.index('    SET v_RequestedUserID', begin)
    record = ("NULL, v_ErrorMessage, JSON_OBJECT('CustomerID', p_CustomerID, 'VehicleID', p_VehicleID, 'TechnicianID', p_TechnicianID, 'AppointmentDateTime', p_AppointmentDateTime), v_CallContext"
              if name == 'sp_CreateServiceAppointment' else
              "p_RepairID, v_ErrorMessage, JSON_OBJECT('TechnicianID', p_TechnicianID, 'Parts', p_Parts), v_CallContext")
    entity = 'ServiceAppointment' if name == 'sp_CreateServiceAppointment' else 'Repair'
    cleanup = 'DROP TEMPORARY TABLE IF EXISTS tmp_RepairParts;' if name == 'sp_CompleteRepair' else ''
    handler = f"""    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET STACKED DIAGNOSTICS v_ConditionCount = NUMBER;
        GET STACKED DIAGNOSTICS CONDITION 1
            v_ErrorState = RETURNED_SQLSTATE, v_ErrorNumber = MYSQL_ERRNO, v_ErrorMessage = MESSAGE_TEXT;
        -- Engine rollback can append HY000 warnings after the actual exception.
        -- Preserve an exception, not a trailing temporary-table rollback notice.
        SET v_ConditionIndex = 1;
        WHILE v_ConditionIndex <= v_ConditionCount DO
            GET STACKED DIAGNOSTICS CONDITION v_ConditionIndex
                v_ConditionState = RETURNED_SQLSTATE, v_ConditionNumber = MYSQL_ERRNO,
                v_ConditionMessage = MESSAGE_TEXT;
            IF LEFT(v_ConditionState, 2) NOT IN ('00', '01', '02')
               AND v_ConditionNumber NOT IN (1196, 1751, 1752) THEN
                SET v_ErrorState = v_ConditionState, v_ErrorNumber = v_ConditionNumber,
                    v_ErrorMessage = v_ConditionMessage;
            END IF;
            SET v_ConditionIndex = v_ConditionIndex + 1;
        END WHILE;
        IF v_TransactionStarted THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_RollbackSucceeded = FALSE;
                ROLLBACK;
            END;
            IF v_RollbackSucceeded AND NOT v_CommitAttempted THEN SET v_Outcome = 'rolled_back'; END IF;
        ELSE
            SET v_Outcome = 'not_started';
        END IF;
        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
            {cleanup}
        END;
        -- Never let logger/cleanup failures replace the original diagnostics.
        -- A failed rollback must not be followed by a commit of partial work.
        IF v_RollbackSucceeded THEN
            BEGIN
                DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
                CALL sp_RecordRejectedDiagnostic(v_RequestedUserID, '{name}', '{entity}',
                    {record}, v_ErrorState, v_ErrorNumber, v_Outcome);
                IF v_TransactionStarted THEN COMMIT; END IF;
            END;
        END IF;
        SET @app_user_id = NULL;
        SET @adj_reason = NULL;
        SET @context_id = NULL;
        RESIGNAL;
    END;

"""
    sql = sql[:begin] + handler + sql[end:]
    # Only the main success COMMIT, not the protected rejection-audit COMMIT.
    sql = sql.replace('\n    COMMIT;\n', '\n    SET v_CommitAttempted = TRUE;\n    COMMIT;\n')
    if name == 'sp_CreateServiceAppointment':
        site = '    -- Check that the creating user exists'
        checks = """    IF NOT EXISTS (SELECT 1 FROM Customer WHERE CustomerID = p_CustomerID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 53005, MESSAGE_TEXT = 'Customer does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Vehicle WHERE VehicleID = p_VehicleID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 53002, MESSAGE_TEXT = 'Vehicle does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM Technician WHERE TechnicianID = p_TechnicianID) THEN
        SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 53003, MESSAGE_TEXT = 'Technician does not exist';
    END IF;

"""
        assert site in sql
        sql = sql.replace(site, checks + site)
    else:
        site = '        -- Record all parts, capturing the current price and cost'
        # The original active-part check remains, but now distinguishes an
        # absent part before combining missing/inactive conditions.
        marker = '        -- Lock every requested part; all must exist and be active'
        checks = """        IF EXISTS (SELECT 1 FROM tmp_RepairParts t LEFT JOIN Part p ON p.PartID = t.PartID WHERE p.PartID IS NULL) THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 53004, MESSAGE_TEXT = 'Part does not exist';
        END IF;
"""
        assert marker in sql
        sql = sql.replace(marker, checks + marker, 1)
    return sql


def diagnostic_writer(original):
    sql = original.replace('sp_RecordRejectedAttempt', 'sp_RecordRejectedDiagnostic', 1)
    sql = sql.replace('IN p_RecordID INT, IN p_Error TEXT, IN p_Request JSON, IN p_Context CHAR(36)',
                      '''IN p_RecordID INT, IN p_Error TEXT, IN p_Request JSON, IN p_Context CHAR(36),
    IN p_ErrorState CHAR(5), IN p_ErrorNumber INT, IN p_Outcome VARCHAR(16)''')
    sql = sql.replace('NewValue, ContextID, SessionAccount)',
                      'NewValue, ContextID, SessionAccount, ApplicationErrorID, ErrorClass, ErrorSQLSTATE, ErrorNumber, ErrorMessage, TransactionOutcome)')
    sql = sql.replace('COALESCE(p_Context, UUID()), USER());',
                      '''COALESCE(p_Context, UUID()), USER(), fn_ApplicationErrorID(p_ErrorNumber),
            fn_ErrorClass(p_ErrorNumber, p_ErrorState, FALSE), p_ErrorState, p_ErrorNumber, p_Error, p_Outcome);''')
    return sql


def generate():
    objects, groups = deployed_objects()
    selected = {key: standardize(sql) for key, sql in objects.items() if SIGNAL.search(sql)}
    routines = [name for kind, name in selected if kind == 'PROCEDURE']
    assert len(routines) == 6, routines
    parts = ['-- Generated from frozen deployed definitions through 005. Stop application writes before DDL.\n', classifiers()]
    parts.append('CREATE TEMPORARY TABLE tmp_ErrorRoutineGrants AS SELECT User, Host, Routine_name, Proc_priv FROM mysql.procs_priv\n'
                 'WHERE Db = DATABASE() AND LOWER(Routine_name) IN (' + ', '.join("'" + name.lower() + "'" for name in routines) + ');\nDELIMITER //\n')
    parts.append(diagnostic_writer(objects[('PROCEDURE', 'sp_RecordRejectedAttempt')]))
    for name in routines:
        sql = selected[('PROCEDURE', name)]
        if name in ('sp_CreateServiceAppointment', 'sp_CompleteRepair'):
            sql = public_procedure(sql, name)
        if name == 'sp_ListAuditTrail':
            sql = sql.replace('        DROP TEMPORARY TABLE IF EXISTS tmp_TemporalPage, tmp_TemporalPageIDs;\n        RESIGNAL;',
                              '''        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
            DROP TEMPORARY TABLE IF EXISTS tmp_TemporalPage, tmp_TemporalPageIDs;
        END;
        RESIGNAL;''')
        parts.append(f'DROP PROCEDURE `{name}` //\n' + sql)
    for names in groups.values():
        for i, name in enumerate(names):
            if ('TRIGGER', name) not in selected:
                continue
            sql = selected[('TRIGGER', name)]
            sql = re.sub(r'(FOR EACH ROW)\s+(?:PRECEDES|FOLLOWS)\s+\w+', r'\1', sql)
            order = f'FOLLOWS {names[i-1]}' if i else (f'PRECEDES {names[1]}' if len(names) > 1 else '')
            sql = sql.replace('FOR EACH ROW', 'FOR EACH ROW\n' + order, 1)
            parts.append(f'DROP TRIGGER `{name}` //\n' + sql)
    restorer = (ROOT / 'sql/migrations/004_session_identity_and_provenance.sql').read_text()
    restorer = re.search(r'CREATE PROCEDURE sp_RestorePublicRoutineGrants\(\)[\s\S]*?\nEND //', restorer)[0]
    restorer = restorer.replace('sp_RestorePublicRoutineGrants', 'sp_RestoreErrorRoutineGrants').replace('tmp_PublicRoutineGrants', 'tmp_ErrorRoutineGrants')
    parts.extend([restorer, 'DELIMITER ;\nCALL sp_RestoreErrorRoutineGrants();\nDROP PROCEDURE sp_RestoreErrorRoutineGrants;\nDROP TEMPORARY TABLE tmp_ErrorRoutineGrants;\n'])
    return '\n\n'.join(parts)


if __name__ == '__main__':
    print(generate(), end='')
